#!/usr/bin/env python3
"""앱 '지도 수정' 요청 처리입니다. ROS 를 쓰지 않습니다."""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Optional

import keepout_mask as km

IDLE_DIALOG_STATES = frozenset({"", "idle", "none", "arrived", "failed", "estopped"})

RADIUS_MIN_M = 1.0
RADIUS_MAX_M = 3.0
MAX_HITS = 180

ACTIONS = (
    "get", "erase_count", "erase", "scan_check", "scan_start",
    "scan_cancel", "scan_apply", "scan_discard", "undo",
)

MESSAGES = {
    "done": "지도를 수정했습니다.",
    "undone": "되돌렸습니다.",
    "saved_only": "다음에 이 지도로 주행할 때 적용됩니다.",
    "busy_driving": "주행 중에는 지도를 수정할 수 없습니다.",
    "no_status": "로봇 상태를 받지 못했습니다.",
    "busy_session": "부분 스캔이 진행 중입니다.",
    "not_current_map": "현재 지도에서만 부분 스캔할 수 있습니다.",
    "apply_failed": "Nav2가 지도를 읽지 못해 수정을 취소했습니다.",
    "internal_error": "지도 수정 중 오류가 났습니다.",
    "no_pose": "로봇 위치나 라이다를 받지 못했습니다.",
    "no_session": "진행 중인 부분 스캔이 없습니다.",
    "bad_action": "알 수 없는 요청입니다.",
    "bad_args": "요청 값이 올바르지 않습니다.",
}


def lock_reason(status: str, current_goal: str, dialog_state: str, moving: bool) -> str:
    """지도를 고치면 안 되는 상태면 'busy_driving', 괜찮으면 ''."""
    if moving:
        return "busy_driving"
    if km.hold_apply(status, current_goal):
        return "busy_driving"
    if str(dialog_state or "").strip() not in IDLE_DIALOG_STATES:
        return "busy_driving"
    return ""


def mission_running(dialog_state: str) -> bool:
    """미션이 켜져 있는가 — 켜져 있으면 미션(장애물 안내)은 다시 켜질 때까지 옛 지도를 씁니다."""
    return bool(str(dialog_state or "").strip())


@dataclass(frozen=True)
class ScanInput:
    """스캔 한 장과 그 순간의 자세. guess 는 base 의 map 자세, sensor 는 base 기준 라이다 자리."""

    ranges: Any
    angle_min: float
    angle_increment: float
    guess: tuple
    sensor: tuple
    sigma: Optional[tuple] = None


class Refusal(Exception):
    """요청을 거절합니다. reason 은 앱의 분기용, message 는 사람용입니다."""

    def __init__(self, reason: str, message: str = "") -> None:
        super().__init__(message or MESSAGES.get(reason, reason))
        self.reason = reason
        self.message = message or MESSAGES.get(reason, reason)


class MapFixCore:
    """요청 하나를 받아 (accepted, reason, message, result) 를 돌려줍니다."""

    def __init__(
        self,
        maps_root: Path,
        *,
        apply: Callable[[str], tuple],
        status: Callable[[], Optional[dict]],
        now: Callable[[], Any],
        clock: Callable[[], float],
        grab_scan: Callable[[], Optional[ScanInput]],
        set_sensing: Callable[[bool], None],
        new_session_id: Callable[[], str] = lambda: uuid.uuid4().hex[:8],
        log: Callable[[str], None] = lambda text: None,
    ) -> None:
        self.maps_root = Path(maps_root)
        self._apply = apply
        self._status = status
        self._now = now
        self._clock = clock
        self._grab_scan = grab_scan
        self._set_sensing = set_sensing
        self._new_session_id = new_session_id
        self._log = log
        self.session = None
        self._sensing = False
        self.pending_apply = ""

    def handle(self, map_id: str, action: str, args_json: str) -> tuple[bool, str, str, dict]:
        import map_fix_store as store

        try:
            if action not in ACTIONS:
                raise Refusal("bad_action")
            args = self._parse(args_json)
            try:
                map_id = km.validate_map_id(map_id)
            except km.KeepoutError as error:
                raise Refusal(error.reason, error.message) from None
            return getattr(self, "_do_" + action)(store, map_id, args)
        except (Refusal, store.MapFixError) as error:
            return False, error.reason, error.message, {}
        except Exception as error:  # noqa: BLE001 - 예상 밖 예외로 노드가 죽으면 앱 기능 전체가 멈춥니다.
            import traceback

            self._log(f"지도 수정 {action}({map_id}) 처리 중 예외: {error!r}\n{traceback.format_exc()}")
            return False, "internal_error", MESSAGES["internal_error"], {}

    @staticmethod
    def _parse(args_json: str) -> dict:
        text = str(args_json or "").strip()
        if not text:
            return {}
        try:
            args = json.loads(text)
        except ValueError:
            raise Refusal("bad_args") from None
        if not isinstance(args, dict):
            raise Refusal("bad_args")
        return args

    def _robot(self) -> Optional[dict]:
        status = self._status()
        return status if isinstance(status, dict) else None

    def lock(self) -> str:
        """지금 잠겨 있으면 사유, 아니면 ''. 상태를 못 받았으면 잠급니다(모르면 하지 않는다)."""
        robot = self._robot()
        if robot is None:
            return "no_status"
        return lock_reason(
            str(robot.get("status", "")),
            str(robot.get("current_goal", "")),
            str(robot.get("dialog_state", "")),
            False,
        )

    def _require_unlocked(self) -> None:
        reason = self.lock()
        if reason:
            raise Refusal(reason)

    def _require_no_session(self) -> None:
        if self.session is not None:
            raise Refusal("busy_session")

    def _mission_stale(self) -> bool:
        robot = self._robot() or {}
        return mission_running(str(robot.get("dialog_state", "")))

    def _current_map_id(self) -> str:
        try:
            return (self.maps_root / "CURRENT_MAP").read_text(encoding="utf-8").strip()
        except OSError:
            return ""

    def _apply_or_save(self, map_id: str) -> tuple[bool, str, str]:
        """주행 지도면 Nav2 에 다시 읽히고, 아니면 파일만 둡니다."""
        if map_id != self._current_map_id():
            return False, "not_current_map", MESSAGES["saved_only"]
        applied, reason, message = self._apply(map_id)
        if applied:
            return True, "", message
        if reason not in ("no_nav2", "apply_timeout"):
            reason = "apply_failed"
        return False, reason, message

    def _settle(self, store, map_id: str, backup: Path, result: dict, done: str):
        """쓴 파일을 반영하고 응답을 만듭니다. Nav2 가 거부하면 백업으로 되돌립니다."""
        applied, reason, message = self._apply_or_save(map_id)
        if reason == "apply_failed":
            store.restore_backup(self.maps_root, map_id, backup)
            store.drop_backup(backup)
            self._log(f"지도 다시 읽히기 실패, 수정 취소({map_id}): {message}")
            raise Refusal("apply_failed")
        if reason == "apply_timeout":
            self.pending_apply = map_id
        result.update(applied=applied, mission_stale=self._mission_stale())
        return True, reason, MESSAGES[done] if applied else message, result

    def retry_pending(self) -> None:
        """응답이 없어 확인 못 한 반영을 다시 겁니다(시험·단순 호출용 — 노드는 아래 둘을 나눠 부릅니다)."""
        map_id = self.retry_target()
        if map_id:
            self.finish_retry(map_id, self._apply(map_id))

    def retry_target(self) -> str:
        """지금 다시 걸 지도. 없으면 ''. 노드는 이것만 잠금 안에서 묻고, Nav2 응답은 잠금 밖에서 기다립니다"""
        map_id = self.pending_apply
        if not map_id or self.session is not None or self.lock():
            return ""
        if map_id != self._current_map_id():
            self.pending_apply = ""
            return ""
        return map_id

    def finish_retry(self, map_id: str, outcome: tuple) -> None:
        applied, reason, message = outcome
        if self.pending_apply != map_id:
            return
        if applied or reason != "apply_timeout":
            self.pending_apply = ""
            if not applied and reason != "no_nav2":
                self._log(f"지도 다시 읽히기 실패({map_id}): {message}")

    def _do_get(self, store, map_id: str, args: dict):
        store.map_paths(self.maps_root, map_id)
        lock = self.lock()
        result = {
            "lock": lock,
            "can_scan": not lock and map_id == self._current_map_id(),
            "history": store.list_history(self.maps_root, map_id),
        }
        return True, "", "", result

    def _do_erase_count(self, store, map_id: str, args: dict):
        image = store.load_map_image(self.maps_root, map_id)
        return True, "", "", store.count_erase(image, args.get("rects"))

    def _do_erase(self, store, map_id: str, args: dict):
        self._require_no_session()
        self._require_unlocked()
        image = store.load_map_image(self.maps_root, map_id)
        pixels, counts = store.apply_erase(image, args.get("rects"))
        entry = {"black": counts["black"], "gray": counts["gray"],
                 "rects": store.normalize_rects(args.get("rects"))}
        backup = store.save_backup(self.maps_root, map_id, "erase", entry, self._now())
        try:
            store.write_map_pixels(self.maps_root, map_id, pixels)
        except store.MapFixError:
            store.drop_backup(backup)
            raise
        result = {"black": counts["black"], "gray": counts["gray"]}
        return self._settle(store, map_id, backup, result, "done")

    def _do_undo(self, store, map_id: str, args: dict):
        self._require_no_session()
        self._require_unlocked()
        backup = store.latest_backup(self.maps_root, map_id)
        if backup is None:
            raise store.MapFixError("nothing_to_undo", "되돌릴 수정이 없습니다.")
        entry = store.read_entry(backup)
        current = store.snapshot(self.maps_root, map_id)
        store.restore_backup(self.maps_root, map_id, backup)
        applied, reason, message = self._apply_or_save(map_id)
        if reason == "apply_failed":
            store.write_snapshot(current)
            self._log(f"지도 다시 읽히기 실패, 되돌리기 취소({map_id}): {message}")
            raise Refusal("apply_failed")
        store.drop_backup(backup)
        if reason == "apply_timeout":
            self.pending_apply = map_id
        result = {"kind": entry["kind"], "applied": applied, "mission_stale": self._mission_stale()}
        return True, reason, MESSAGES["undone"] if applied else message, result

    def _require_scannable(self, map_id: str) -> None:
        self._require_unlocked()
        if map_id != self._current_map_id():
            raise Refusal("not_current_map")

    def _do_scan_check(self, store, map_id: str, args: dict):
        self._require_scannable(map_id)
        taken = self._grab_scan()
        if taken is None:
            raise Refusal("no_pose")
        import map_fix_scan as scan
        from vica_nav2.pose_score import build_likelihood_field

        grid = store.to_grid(store.load_map_image(self.maps_root, map_id))
        got = scan.refine_pose(
            grid, build_likelihood_field(grid), taken.ranges, taken.angle_min,
            taken.angle_increment, taken.guess, taken.sensor, guess_sigma=taken.sigma,
        )
        result = {
            "ok": got.ok, "reason": got.reason, "score": round(got.score, 1),
            "used_beams": got.used_beams, "kept_beams": got.kept_beams,
            "ambiguous": list(got.ambiguous),
            "x": round(got.x, 3), "y": round(got.y, 3), "yaw": round(got.yaw, 4),
            "centre": [round(value, 3) for value in scan.sensor_position((got.x, got.y, got.yaw), taken.sensor)],
            "rms_m": round(got.rms_m, 4), "moved_m": round(got.moved_m, 3), "moved_deg": round(got.moved_deg, 2),
            "hits": [[round(float(x), 3), round(float(y), 3)] for x, y in got.hits[:MAX_HITS]],
        }
        return True, "", "", result

    def _do_scan_start(self, store, map_id: str, args: dict):
        self._require_no_session()
        self._require_scannable(map_id)
        radius = args.get("radius_m")
        if isinstance(radius, bool) or not isinstance(radius, (int, float)):
            raise Refusal("bad_args")
        if not RADIUS_MIN_M <= float(radius) <= RADIUS_MAX_M:
            raise Refusal("bad_args")
        import map_fix_session as session

        grid = store.to_grid(store.load_map_image(self.maps_root, map_id))
        self.session = session.ScanSession(
            self._new_session_id(), map_id, grid, float(radius), self._clock())
        self._sense(True)
        return True, "", "", {"session": self.session.session_id}

    def _sense(self, on: bool) -> None:
        if on != self._sensing:
            self._sensing = on
            self._set_sensing(on)

    def _session_for(self, args: dict, map_id: str):
        run = self.session
        if run is None or run.session_id != args.get("session") or run.map_id != map_id:
            raise Refusal("no_session")
        return run

    def _do_scan_cancel(self, store, map_id: str, args: dict):
        self._session_for(args, map_id).cancel()
        return True, "", "", {}

    _do_scan_discard = _do_scan_cancel

    def _do_scan_apply(self, store, map_id: str, args: dict):
        run = self._session_for(args, map_id)
        if run.phase != "preview" or run.changes is None:
            raise Refusal("no_session")
        self._require_unlocked()
        image = store.load_map_image(self.maps_root, map_id)
        pixels = image.pixels.copy()
        height = pixels.shape[0]
        added = store.cells_to_pixels(run.changes.added, height)
        removed = store.cells_to_pixels(run.changes.removed, height)
        pixels[added[:, 0], added[:, 1]] = store.OCCUPIED
        pixels[removed[:, 0], removed[:, 1]] = store.FREE
        entry = {
            "radius_m": run.radius_m, "added": int(len(added)), "removed": int(len(removed)),
            "pose": [round(float(value), 4) for value in run.pose],
        }
        backup = store.save_backup(self.maps_root, map_id, "scan", entry, self._now())
        try:
            store.write_map_pixels(self.maps_root, map_id, pixels)
        except store.MapFixError:
            store.drop_backup(backup)
            raise
        result = {
            "added": entry["added"], "removed": entry["removed"],
            "score_before": round(run.score_before, 1), "score_after": round(run.score_after, 1),
        }
        answer = self._settle(store, map_id, backup, result, "done")
        self.session = None
        self._sense(False)
        return answer

    def feed_scan(self, taken: Optional[ScanInput]) -> None:
        if self.session is not None and taken is not None:
            self.session.on_scan(
                self._clock(), taken.ranges, taken.angle_min, taken.angle_increment,
                taken.guess, taken.sensor, taken.sigma,
            )

    def feed_motion(self, linear: float, angular: float) -> None:
        if self.session is not None:
            self.session.on_motion(linear, angular)

    def tick(self) -> Optional[dict]:
        """세션을 한 걸음 진행하고 토픽에 실을 상태를 돌려줍니다. 세션이 없으면 None."""
        run = self.session
        if run is None:
            return None
        run.on_lock(bool(self.lock()))
        run.tick(self._clock())
        state = run.state(self._clock())
        if run.phase not in ("refine", "step_back", "scanning"):
            self._sense(False)
        if run.phase in ("failed", "done"):
            self.session = None
        return state
