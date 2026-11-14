#!/usr/bin/env python3
"""앱에 지도 이미지를 넘겨주는 작은 HTTP 서버입니다.

`python -m http.server` 를 그대로 쓰지 않는 이유는 **헤더 한 줄** 때문입니다.

    Access-Control-Allow-Origin: *

이 줄이 없으면 브라우저로 띄운 앱에서 지도 그림만 안 보입니다. 증상이 고약한
것은 나머지가 전부 멀쩡해 보인다는 점입니다 — ROS 연결도 되고 지도 목록
드롭다운도 뜹니다. 목록은 rosbridge(WebSocket)로 오고 그림만 이 HTTP 서버로
오는데, WebSocket 은 브라우저의 출처 검사를 받지 않기 때문입니다.

왜 브라우저가 막는가. 브라우저는 A 라는 주소에서 받은 화면이 B 라는 주소의
파일을 읽으려 하면 "B 가 허락했는가"를 먼저 확인합니다. 그 허락이 위 헤더입니다.
출처(origin)에는 **포트도 포함**되므로, 젯슨 위에서 브라우저를 띄워도
localhost:5000 과 localhost:8000 은 서로 남입니다. 즉 IP 를 아무리 맞춰도
이 헤더 없이는 웹에서 지도가 보이지 않습니다.

안드로이드 APK 와 Linux desktop 빌드는 브라우저가 아니므로 이 검사가 없습니다.
그래서 "APK 로는 되는데 크롬으로는 안 되는" 상태가 오래 남아 있었습니다.

Flutter 3.29 부터 웹은 CanvasKit 만 씁니다. 예전 HTML 렌더러는 <img> 태그로
그려서 이 검사를 피해 갔지만, 지금은 이미지 바이트를 직접 받아 디코딩하므로
검사를 받습니다.

`/maps/` 아래만 내보냅니다. 예전에는 작업공간 전체가 열려 있었는데, 위 헤더를
붙이면 "아무 웹페이지나 이 파일을 읽어도 좋다"가 되므로 내보내는 범위를 앱이
실제로 쓰는 것으로 좁힙니다.

경비(순찰) 기록(2026-11-14). `/patrol/` 은 `--patrol-directory` 폴더에서 아래 여섯 가지만
내보냅니다. 주소는 정해진 모양만 받으므로 폴더 밖(`..`)이나 `events.jsonl` 원본은 나가지 않습니다.

    /patrol/events.json                 events.jsonl 을 alarm_id 로 합친 최신순 배열(최대 200)
    /patrol/clips/<id>.mp4              영상. 없고 사진(frames/)이 있으면 그 자리에서 만들어 보냅니다
    /patrol/clips/<id>.jpg              영상 첫 장
    /patrol/clips/<id>/frames.json      mp4 를 못 만든 장면의 사진 목록(앱이 초당 5장으로 넘깁니다)
    /patrol/clips/<id>/frames/<n>.jpg   그 사진 한 장
    /patrol/photos/<이름>               불 켜짐 사진
"""

import argparse
import io
import json
import re
import shutil
import subprocess
import threading
import time
from datetime import datetime
from fractions import Fraction
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional
from urllib.parse import unquote

# 앱이 읽는 경로. map_list_node 가 image_url 을 "/maps/<이름>.png" 로 만듭니다.
PUBLIC_PREFIX = "/maps/"

# ---- 경비(순찰) 기록 (2026-11-14) ---------------------------------------------

PATROL_PREFIX = "/patrol/"
DEFAULT_PATROL_DIRECTORY = "~/workspaces/isaac_ros-dev/vica_patrol"
PATROL_EVENT_LIMIT = 200
# events.jsonl 은 지우지 않는 파일이라 요청마다 전체를 읽지 않고 끝의 이만큼만 읽습니다.
# 경보 한 건이 300바이트 안팎이라 최신 200건이 넉넉히 들어갑니다.
EVENTS_TAIL_BYTES = 256 * 1024
CLIP_FPS = 5
# meta.json 없이 마지막 사진이 이만큼 지났으면 끝난 장면으로 봅니다(감지 노드가 죽은 경우).
# 장면은 최대 60초라 그 두 배입니다.
CLIP_STALE_SEC = 120.0
CONVERT_TIMEOUT_SEC = 60.0

# 주소에서 받는 이름의 모양. 이 모양이 아니면 파일을 찾지도 않습니다.
_ID = r"[A-Za-z0-9_\-]{1,80}"
_RE_CLIP_MP4 = re.compile(rf"clips/({_ID})\.mp4")
_RE_CLIP_JPG = re.compile(rf"clips/({_ID})\.jpg")
_RE_CLIP_FRAMES = re.compile(rf"clips/({_ID})/frames\.json")
_RE_CLIP_FRAME = re.compile(rf"clips/({_ID})/frames/(\d{{1,9}}\.jpg)")
_RE_PHOTO = re.compile(r"photos/([A-Za-z0-9_\-][A-Za-z0-9_\-.]{0,120}\.(?:jpg|jpeg|png))")
_RE_FRAME_NAME = re.compile(r"\d{1,9}\.jpg")

# 변환은 한 번에 하나만 돌립니다. 같은 장면을 두 요청이 함께 만들지 않게도 합니다.
_CONVERT_LOCK = threading.Lock()
_BACKLOG_LOCK = threading.Lock()
_backlog_running = False


def _frame_files(frames_dir: Path) -> list:
    """frames/ 의 사진을 번호순으로 돌려줍니다. 없으면 빈 목록."""
    if not frames_dir.is_dir():
        return []
    files = [p for p in frames_dir.iterdir() if _RE_FRAME_NAME.fullmatch(p.name)]
    return sorted(files, key=lambda p: int(p.stem))


def _read_json(path: Path) -> Optional[dict]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def _to_epoch(value) -> Optional[float]:
    """meta.json 의 start·end 는 epoch 초든 ISO 글자든 받습니다."""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str) and value:
        try:
            return float(value)
        except ValueError:
            pass
        try:
            return datetime.fromisoformat(value).timestamp()
        except ValueError:
            return None
    return None


def _iso(epoch: Optional[float]) -> Optional[str]:
    if epoch is None:
        return None
    return datetime.fromtimestamp(epoch).isoformat(timespec="seconds")


def _meta_epoch(meta: dict, key: str) -> Optional[float]:
    """meta.json 의 처음·끝 시각(key 는 start·end)을 epoch 초로.

    감지 노드가 적는 `<key>_epoch`(float)를 먼저 씁니다. 감지 노드는 UTC 컨테이너에서 돌아
    글자 시각(`start`·`end`)을 이 서버(호스트 시간대)가 읽으면 9시간 어긋났습니다. epoch 값이
    없는 옛 기록만 글자를 읽습니다.
    """
    value = meta.get(f"{key}_epoch")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return _to_epoch(meta.get(key))


def _meta_fps(meta: dict) -> float:
    """meta.json 의 초당 장수(감지 노드가 실제로 잰 값). 없거나 이상하면 5."""
    fps = meta.get("fps")
    if isinstance(fps, (int, float)) and not isinstance(fps, bool) and 0.5 <= fps <= 30:
        return float(fps)
    return float(CLIP_FPS)


def _tail_lines(path: Path, max_bytes: int = EVENTS_TAIL_BYTES) -> list:
    """파일 끝 max_bytes 안의 온전한 줄들. 중간부터 읽어 잘린 첫 줄은 버립니다."""
    try:
        with path.open("rb") as file:
            size = file.seek(0, io.SEEK_END)
            # 한 바이트 앞에서 읽기 시작해 첫 줄바꿈까지 버립니다. 시작 자리가 마침 줄의
            # 처음이면 그 앞 바이트가 줄바꿈이라 온전한 줄을 잃지 않습니다.
            start = max(size - max_bytes - 1, 0)
            file.seek(start)
            data = file.read()
    except OSError:
        return []
    if start > 0:
        cut = data.find(b"\n")
        data = data[cut + 1:] if cut >= 0 else b""
    return data.decode("utf-8", errors="replace").splitlines()


def clip_finished(clip_dir: Path, now: Optional[float] = None) -> bool:
    """장면 저장이 끝났는가. 끝난 장면만 mp4 로 바꿉니다(쓰는 중인 사진을 지우지 않게)."""
    if (clip_dir / "meta.json").is_file():
        return True
    frames = _frame_files(clip_dir / "frames")
    if not frames:
        return False
    newest = max(p.stat().st_mtime for p in frames)
    return (now if now is not None else time.time()) - newest > CLIP_STALE_SEC


def clip_info(patrol_dir: Path, clip_id: str, alarm_time=None) -> dict:
    """기록 한 줄에 붙일 영상 정보. clip_state 는 ready·recording·missing."""
    clips = patrol_dir / "clips"
    clip_dir = clips / clip_id
    meta = _read_json(clip_dir / "meta.json") or {}
    frames = _frame_files(clip_dir / "frames")
    if (clips / f"{clip_id}.mp4").is_file():
        state = "ready"
    elif frames:
        state = "ready" if clip_finished(clip_dir) else "recording"
    else:
        state = "missing"

    fps = _meta_fps(meta)
    count = meta.get("frames") if isinstance(meta.get("frames"), int) else len(frames)
    seconds = round(count / fps, 1) if count else None
    start = _meta_epoch(meta, "start")
    end = _meta_epoch(meta, "end")
    detect = None
    alarm = _to_epoch(alarm_time)
    if start is not None and alarm is not None and seconds is not None:
        detect = round(min(max(alarm - start, 0.0), seconds), 1)
    return {
        "clip_state": state,
        "clip_sec": seconds if state != "missing" else None,
        "clip_start": _iso(start),
        "clip_end": _iso(end),
        "detect_sec": detect,
    }


def read_patrol_events(patrol_dir: Path, limit: int = PATROL_EVENT_LIMIT) -> list:
    """events.jsonl 을 alarm_id 로 합쳐 최신순으로 돌려줍니다. 깨진 줄은 건너뜁니다.

    파일 끝 [EVENTS_TAIL_BYTES] 만 읽습니다 — 그보다 오래된 기록은 목록에 나오지 않습니다.
    """
    alarms: dict = {}
    for order, line in enumerate(_tail_lines(patrol_dir / "events.jsonl")):
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if not isinstance(item, dict):
            continue
        alarm_id = item.get("alarm_id")
        if not isinstance(alarm_id, str) or not alarm_id:
            continue
        record = alarms.setdefault(alarm_id, {"alarm_id": alarm_id, "_order": order})
        if item.get("type") == "alarm":
            # 나중에 clip 줄로 먼저 알게 된 clip_id 를 빈 값으로 덮지 않습니다.
            known_clip = record.get("clip_id")
            record.update({k: v for k, v in item.items() if k != "type"})
            if not record.get("clip_id") and known_clip:
                record["clip_id"] = known_clip
        elif item.get("type") == "clip" and item.get("clip_id"):
            record["clip_id"] = item["clip_id"]

    records = [r for r in alarms.values() if r.get("kind")]
    records.sort(key=lambda r: (str(r.get("time") or ""), r["_order"]), reverse=True)
    out = []
    for record in records[:limit]:
        record.pop("_order", None)
        for key in ("clip_id", "photo", "level_db"):
            record.setdefault(key, None)
        clip_id = record["clip_id"]
        if isinstance(clip_id, str) and re.fullmatch(_ID, clip_id):
            record.update(clip_info(patrol_dir, clip_id, record.get("time")))
        else:
            record.update(
                {"clip_state": "missing", "clip_sec": None, "clip_start": None,
                 "clip_end": None, "detect_sec": None}
            )
        out.append(record)
    return out


def clip_fps(clip_dir: Path) -> float:
    """장면의 초당 장수. 감지 노드가 meta.json 에 실제로 잰 값을 적습니다 — 없거나 이상하면 5."""
    return _meta_fps(_read_json(clip_dir / "meta.json") or {})


def convert_frames(frames_dir: Path, out_path: Path, first: int = 1, width: int = 6,
                   fps: float = CLIP_FPS) -> bool:
    """frames/ 의 사진을 H.264 mp4 로 만듭니다(초당 장수 fps — 실제 속도로 재생되게). 성공하면 True.

    먼저 젯슨 하드웨어 인코더(75장 0.7초·0.9 MB, 2026-11-11 실측)로 하고, 실패하면 ffmpeg(libx264)로
    합니다. 시험은 이 함수를 바꿔 끼워 인코더 없이 돕니다.
    """
    pattern = str(frames_dir / f"%0{width}d.jpg")
    rate = Fraction(fps).limit_denominator(100)   # gst 는 분수로 받습니다(3.41 → 341/100)
    commands = [
        [
            "gst-launch-1.0", "-q",
            "multifilesrc", f"location={pattern}", f"index={first}",
            f"caps=image/jpeg,framerate={rate.numerator}/{rate.denominator}",
            "!", "jpegdec", "!", "videoconvert", "!", "video/x-raw,format=I420",
            "!", "nvvidconv", "!", "video/x-raw(memory:NVMM),format=NV12",
            "!", "nvv4l2h264enc", "bitrate=400000", "!", "h264parse",
            "!", "mp4mux", "!", "filesink", f"location={out_path}",
        ],
        [
            "ffmpeg", "-y", "-framerate", f"{float(rate):.2f}", "-start_number", str(first),
            "-i", pattern, "-c:v", "libx264", "-preset", "veryfast", "-crf", "26",
            "-pix_fmt", "yuv420p", "-f", "mp4", str(out_path),
        ],
    ]
    for command in commands:
        try:
            done = subprocess.run(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=CONVERT_TIMEOUT_SEC,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            done = None
        if done is not None and done.returncode == 0 and _looks_like_mp4(out_path):
            return True
        out_path.unlink(missing_ok=True)
    return False


def _looks_like_mp4(path: Path) -> bool:
    try:
        with path.open("rb") as file:
            head = file.read(12)
    except OSError:
        return False
    return len(head) == 12 and head[4:8] == b"ftyp"


def ensure_clip_mp4(patrol_dir: Path, clip_id: str) -> Optional[Path]:
    """<id>.mp4 를 돌려줍니다. 없고 끝난 장면의 사진이 있으면 만들고, 못 만들면 None.

    성공하면 frames/ 를 지우고 첫 장만 <id>.jpg 로 남깁니다. 실패하면 사진을 그대로 둡니다 —
    앱이 frames.json 으로 사진을 넘겨 보여 줍니다.
    """
    clips = patrol_dir / "clips"
    target = clips / f"{clip_id}.mp4"
    if target.is_file():
        return target
    clip_dir = clips / clip_id
    frames_dir = clip_dir / "frames"
    with _CONVERT_LOCK:
        if target.is_file():
            return target
        frames = _frame_files(frames_dir)
        if not frames or not clip_finished(clip_dir):
            return None
        # 확장자는 .mp4 로 둡니다 — ffmpeg·mp4mux 가 이름으로 형식을 고릅니다.
        partial_path = clips / f".{clip_id}.part.mp4"
        partial_path.unlink(missing_ok=True)
        first = frames[0]
        ok = convert_frames(
            frames_dir, partial_path, first=int(first.stem), width=len(first.stem),
            fps=clip_fps(clip_dir),
        )
        if not ok:
            partial_path.unlink(missing_ok=True)
            return None
        try:
            shutil.copyfile(first, clips / f"{clip_id}.jpg")
            partial_path.replace(target)
        except OSError:
            partial_path.unlink(missing_ok=True)
            return None
        shutil.rmtree(frames_dir, ignore_errors=True)
        return target


def convert_backlog(patrol_dir: Path) -> int:
    """끝났는데 아직 mp4 가 없는 장면을 최신 것부터 바꿉니다. 바꾼 개수를 돌려줍니다."""
    clips = patrol_dir / "clips"
    if not clips.is_dir():
        return 0
    pending = [
        d for d in clips.iterdir()
        if d.is_dir() and re.fullmatch(_ID, d.name)
        and not (clips / f"{d.name}.mp4").is_file()
        and (d / "frames").is_dir()
    ]
    done = 0
    for clip_dir in sorted(pending, key=lambda d: d.name, reverse=True):
        if ensure_clip_mp4(patrol_dir, clip_dir.name) is not None:
            done += 1
    return done


def start_backlog(patrol_dir: Path) -> bool:
    """밀린 변환을 뒤에서 시작합니다. 이미 돌고 있으면 새로 띄우지 않습니다."""
    global _backlog_running
    with _BACKLOG_LOCK:
        if _backlog_running:
            return False
        _backlog_running = True

    def work() -> None:
        global _backlog_running
        try:
            convert_backlog(patrol_dir)
        finally:
            with _BACKLOG_LOCK:
                _backlog_running = False

    threading.Thread(target=work, name="patrol-backlog", daemon=True).start()
    return True


class _RangeReader:
    """파일의 한 구간만 읽게 하는 껍데기. do_GET 의 copyfile 이 read() 만 부릅니다."""

    def __init__(self, file, length: int) -> None:
        self._file = file
        self._left = length

    def read(self, size: int = -1) -> bytes:
        if self._left <= 0:
            return b""
        if size is None or size < 0 or size > self._left:
            size = self._left
        data = self._file.read(size)
        self._left -= len(data)
        return data

    def close(self) -> None:
        self._file.close()


def parse_range(header: str, size: int):
    """`Range: bytes=a-b` 를 (시작, 끝) 으로. 없거나 모르는 모양이면 None, 범위 밖이면 False."""
    match = re.fullmatch(r"\s*bytes=(\d*)-(\d*)\s*", header or "")
    if not match or (not match.group(1) and not match.group(2)):
        return None
    if not match.group(1):
        # bytes=-N : 뒤에서 N 바이트.
        length = int(match.group(2))
        if length == 0:
            return False
        return max(size - length, 0), size - 1
    start = int(match.group(1))
    end = int(match.group(2)) if match.group(2) else size - 1
    if start >= size or end < start:
        return False
    return start, min(end, size - 1)


class MapRequestHandler(SimpleHTTPRequestHandler):
    """지도 파일과 경비 기록만, 출처 허락 헤더를 붙여 내보냅니다."""

    def __init__(self, *args, patrol_directory=None, **kwargs) -> None:
        # 부모의 __init__ 이 곧바로 요청을 처리하므로 그 앞에 적어 둡니다.
        self.patrol_directory = (
            Path(patrol_directory).expanduser() if patrol_directory else None
        )
        self._after_response = None
        super().__init__(*args, **kwargs)

    def end_headers(self) -> None:
        # 이 한 줄이 이 파일이 존재하는 이유입니다.
        self.send_header("Access-Control-Allow-Origin", "*")
        # 매번 바뀌었는지 물어보게 합니다(2026-10-08). 이 줄이 없으면 브라우저가
        # Last-Modified 만 보고 한동안 옛 파일을 그대로 다시 씁니다 — 레일을 고쳐
        # 저장해도 앱 지도에는 옛 레일이 남았습니다(run69 뒤 사용자 보고). 안 바뀐
        # 파일은 304(본문 없음)로 끝나 지도 그림을 다시 받지는 않습니다.
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def send_head(self):
        # 질의문자열(?v=1)이 붙어 와도 경로만 봅니다.
        path = self.path.split("?", 1)[0].split("#", 1)[0]
        if path.startswith(PATROL_PREFIX):
            return self._send_patrol_head(unquote(path[len(PATROL_PREFIX):]))
        if not path.startswith(PUBLIC_PREFIX):
            # 디렉터리 목록도 여기서 함께 막힙니다.
            self.send_error(404, "Not Found")
            return None
        return super().send_head()

    def do_GET(self) -> None:
        self._after_response = None
        super().do_GET()
        after, self._after_response = self._after_response, None
        if after is not None:
            after()

    # ---- 경비 기록 ---------------------------------------------------------

    def _send_patrol_head(self, rest: str):
        root = self.patrol_directory
        if root is None:
            self.send_error(404, "Not Found")
            return None
        if rest == "events.json":
            body = json.dumps(read_patrol_events(root), ensure_ascii=False)
            # 응답을 다 보낸 뒤 밀린 변환을 시작합니다(do_GET).
            self._after_response = partial(start_backlog, root)
            return self._send_bytes(body.encode("utf-8"), "application/json; charset=utf-8")

        match = _RE_CLIP_MP4.fullmatch(rest)
        if match:
            target = ensure_clip_mp4(root, match.group(1))
            return self._send_patrol_file(target, "video/mp4")
        match = _RE_CLIP_JPG.fullmatch(rest)
        if match:
            clip_id = match.group(1)
            target = root / "clips" / f"{clip_id}.jpg"
            if not target.is_file():
                # 아직 mp4 로 바꾸기 전이면 첫 사진이 첫 장입니다.
                frames = _frame_files(root / "clips" / clip_id / "frames")
                target = frames[0] if frames else None
            return self._send_patrol_file(target, "image/jpeg")
        match = _RE_CLIP_FRAMES.fullmatch(rest)
        if match:
            clip_id = match.group(1)
            frames = _frame_files(root / "clips" / clip_id / "frames")
            if not frames:
                self.send_error(404, "Not Found")
                return None
            body = json.dumps(
                {
                    "id": clip_id,
                    "fps": clip_fps(root / "clips" / clip_id),
                    "count": len(frames),
                    "frames": [p.name for p in frames],
                }
            )
            return self._send_bytes(body.encode("utf-8"), "application/json; charset=utf-8")
        match = _RE_CLIP_FRAME.fullmatch(rest)
        if match:
            target = root / "clips" / match.group(1) / "frames" / match.group(2)
            return self._send_patrol_file(target, "image/jpeg")
        match = _RE_PHOTO.fullmatch(rest)
        if match and ".." not in match.group(1):
            name = match.group(1)
            kind = "image/png" if name.lower().endswith(".png") else "image/jpeg"
            return self._send_patrol_file(root / "photos" / name, kind)

        self.send_error(404, "Not Found")
        return None

    def _send_bytes(self, body: bytes, content_type: str):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        return io.BytesIO(body)

    def _send_patrol_file(self, target: Optional[Path], content_type: str):
        """파일 하나를 보냅니다. Range 요청이면 그 구간만(웹 영상 재생이 씁니다)."""
        root = self.patrol_directory
        try:
            if target is None or root is None:
                raise FileNotFoundError
            # 링크로 폴더 밖을 가리키는 파일은 내보내지 않습니다.
            resolved = target.resolve(strict=True)
            resolved.relative_to(root.resolve())
            file = resolved.open("rb")
        except (OSError, ValueError):
            self.send_error(404, "Not Found")
            return None
        handed_over = False
        try:
            size = resolved.stat().st_size
            span = parse_range(self.headers.get("Range", ""), size)
            if span is False:
                self.send_response(416, "Requested Range Not Satisfiable")
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return None
            start, end = span if span else (0, size - 1)
            length = max(end - start + 1, 0)
            self.send_response(206 if span else 200)
            self.send_header("Content-Type", content_type)
            self.send_header("Accept-Ranges", "bytes")
            if span:
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.send_header("Content-Length", str(length))
            self.end_headers()
            file.seek(start)
            handed_over = True
            return _RangeReader(file, length)
        finally:
            # 넘겨준 파일은 do_GET 이 닫습니다. 그 전에 끝났으면 여기서 닫습니다.
            if not handed_over:
                file.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="VICA 지도 이미지 HTTP 서버")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument(
        "--directory",
        default=str(Path(__file__).resolve().parents[2] / "vica_ros2_ws"),
        help="이 폴더를 루트로 삼습니다. 그 아래 maps/ 만 내보냅니다.",
    )
    parser.add_argument(
        "--patrol-directory",
        default=DEFAULT_PATROL_DIRECTORY,
        help="경비 기록 폴더(events.jsonl·clips/·photos/). /patrol/ 로 내보냅니다.",
    )
    args = parser.parse_args()

    handler = partial(
        MapRequestHandler,
        directory=args.directory,
        patrol_directory=args.patrol_directory,
    )
    # ThreadingHTTPServer 는 python -m http.server 가 쓰는 것과 같습니다.
    # 한 요청이 늦어져도 다음 요청이 막히지 않습니다.
    with ThreadingHTTPServer((args.bind, args.port), handler) as server:
        print(
            f"지도 HTTP 서버: http://{args.bind}:{args.port}{PUBLIC_PREFIX} "
            f"(루트 {args.directory})",
            flush=True,
        )
        print(
            f"경비 기록: http://{args.bind}:{args.port}{PATROL_PREFIX} "
            f"(폴더 {Path(args.patrol_directory).expanduser()})",
            flush=True,
        )
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
