#!/usr/bin/env python3
"""앱이 그린 레일(route graph)을 다듬어 저장하고 route_server 에 물리는 노드입니다."""

import json
import math
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path
from threading import Event, Lock

import rclpy
from rclpy.callback_groups import MutuallyExclusiveCallbackGroup, ReentrantCallbackGroup
from rclpy.executors import ExternalShutdownException, MultiThreadedExecutor
from rclpy.node import Node
from std_msgs.msg import String

import keepout_mask as km
import route_graph_build as rb

KST = timezone(timedelta(hours=9))


class RouteGraphNode(Node):
    """레일 초안·저장·조회 서비스와 route_server 반영을 담당합니다."""

    def __init__(self) -> None:
        super().__init__("vica_route_graph")

        workspace_root = Path(__file__).resolve().parents[2]
        self.declare_parameter("maps_root", str(workspace_root / "vica_ros2_ws" / "maps"))
        self.declare_parameter(
            "destinations_root", str(Path.home() / "vica_data" / "destinations"))
        self.declare_parameter("set_graph_service", "/route_server/set_route_graph")
        self.declare_parameter("apply_timeout_sec", 3.0)
        self.declare_parameter("robot_status_topic", "/robot_status")

        self.maps_root = Path(str(self.get_parameter("maps_root").value)).expanduser()
        self.dest_root = Path(str(self.get_parameter("destinations_root").value)).expanduser()

        self._service_group = MutuallyExclusiveCallbackGroup()
        self._io = ReentrantCallbackGroup()
        self._hold_apply = False
        self._pending_apply = ""
        self._grid_cache: dict[str, tuple[str, rb.MapGrid]] = {}
        self._lock = Lock()

        self.state_publisher = self.create_publisher(String, "/vica/route/state", 10)
        self.saved_publisher = self.create_publisher(String, "/vica/route/saved", 10)
        self.create_subscription(
            String, str(self.get_parameter("robot_status_topic").value),
            self._on_robot_status, 10, callback_group=self._io)

        self._set_graph_client = None
        self._set_graph_type = None
        self._setup_set_graph_client()
        self._setup_services()
        self.get_logger().info(f"vica_route_graph 시작: maps_root={self.maps_root}")

    def _setup_services(self) -> None:
        try:
            from vica_interfaces.srv import DraftRoute, GetRoute, SaveRoute
        except ImportError as error:
            self.get_logger().error(
                f"vica_interfaces/DraftRoute·SaveRoute·GetRoute import 실패: {error}. "
                "레일 서비스를 열지 않습니다. colcon build --packages-select vica_interfaces 가 필요합니다.")
            return
        self.create_service(DraftRoute, "/vica/route/draft", self.handle_draft,
                            callback_group=self._service_group)
        self.create_service(SaveRoute, "/vica/route/save", self.handle_save,
                            callback_group=self._service_group)
        self.create_service(GetRoute, "/vica/route/get", self.handle_get,
                            callback_group=self._service_group)
        self.get_logger().info("/vica/route/draft · save · get 준비 완료")

    def _setup_set_graph_client(self) -> None:
        try:
            from nav2_msgs.srv import SetRouteGraph
        except ImportError as error:
            self.get_logger().error(f"nav2_msgs/SetRouteGraph import 실패: {error}. 적용 없이 저장만 합니다.")
            return
        self._set_graph_type = SetRouteGraph
        self._set_graph_client = self.create_client(
            SetRouteGraph, str(self.get_parameter("set_graph_service").value),
            callback_group=self._io)

    def _on_robot_status(self, msg: String) -> None:
        try:
            payload = json.loads(msg.data)
        except (json.JSONDecodeError, TypeError):
            return
        hold = km.hold_apply(str(payload.get("status", "")), str(payload.get("current_goal", "")))
        if hold == self._hold_apply:
            return
        self._hold_apply = hold
        if not hold and self._pending_apply:
            map_id, self._pending_apply = self._pending_apply, ""
            applied, reason, message = self._apply(map_id)
            self._publish_state(map_id, applied, reason, message)

    def _publish_state(self, map_id: str, applied: bool, reason: str, message: str) -> None:
        msg = String()
        msg.data = json.dumps({"map_id": map_id, "applied": applied, "reason": reason,
                               "message": message, "at": self._now()}, ensure_ascii=False)
        self.state_publisher.publish(msg)

    def _current_map_id(self) -> str:
        try:
            return (self.maps_root / "CURRENT_MAP").read_text(encoding="utf-8").strip()
        except OSError:
            return ""

    def _grid(self, map_id: str) -> rb.MapGrid:
        """지도 격자는 이미지 판이 같으면 다시 계산하지 않는다(벽 거리 계산 0.1~0.3 s)."""
        map_id = km.validate_map_id(map_id)
        meta = km.read_map_meta(self.maps_root, map_id)
        version = rb.file_version(self.maps_root / meta.image_name)
        cached = self._grid_cache.get(map_id)
        if cached and cached[0] == version:
            return cached[1]
        grid = rb.MapGrid(self.maps_root, map_id)
        self._grid_cache[map_id] = (version, grid)
        return grid

    @staticmethod
    def _checks(result) -> str:
        return json.dumps({"errors": rb.issues_payload(result["errors"]),
                           "warnings": rb.issues_payload(result["warnings"]),
                           "places": result["places"], "summary": result["summary"]},
                          ensure_ascii=False)

    def handle_draft(self, request, response):
        response.sketch_json = response.preview_json = ""
        response.checks_json = "{}"
        response.shape = ""
        try:
            grid = self._grid(request.map_id)
            places = rb.load_places(self.dest_root, request.map_id)
            shape = (request.shape or "auto").strip() or "auto"
            if shape not in ("auto", "loop", "tree"):
                shape = "auto"
            draft = rb.auto_draft(grid, places, shape)
        except km.KeepoutError as error:
            response.accepted, response.reason, response.message = False, error.reason, error.message
            return response
        result = draft["result"]
        response.accepted = True
        response.reason = ""
        response.shape = draft["shape"]
        response.sketch_json = json.dumps(draft["sketch"], ensure_ascii=False)
        response.preview_json = json.dumps(rb.preview_json(result["graph"]), ensure_ascii=False)
        response.checks_json = self._checks(result)
        kind = "고리형" if draft["shape"] == "loop" else "나무형"
        response.message = f"{kind} 초안을 만들었습니다. 확인하고 저장하세요."
        self.get_logger().info(f"레일 초안: {request.map_id} {kind} 노드 {len(draft['sketch']['nodes'])}개")
        return response

    def handle_get(self, request, response):
        response.sketch_json = ""
        response.checks_json = "{}"
        response.version = ""
        response.status = "none"
        try:
            map_id = km.validate_map_id(request.map_id)
            paths = rb.route_paths(self.maps_root, map_id)
            sketch = rb.load_sketch(self.maps_root, map_id)
        except km.KeepoutError as error:
            response.found, response.reason, response.message = False, error.reason, error.message
            return response
        if not paths["graph"].is_file():
            response.found, response.reason, response.message = False, "", "이 지도에는 레일이 없습니다."
            return response
        try:
            doc = json.loads(paths["graph"].read_text(encoding="utf-8"))
            graph = rb.graph_from_geojson(doc)
        except (OSError, ValueError, KeyError) as error:
            response.found, response.reason, response.message = False, "bad_route", f"레일 파일을 읽지 못했습니다: {error}"
            return response
        places, _ = rb.place_report(graph, rb.load_places(self.dest_root, map_id))
        edges = graph.edges()
        summary = {"node_count": len(graph.nodes), "edge_count": 2 * len(edges),
                   "length_m": round(sum(math.dist(graph.nodes[a], graph.nodes[b]) for a, b in edges), 1),
                   "junction_count": sum(1 for nb in graph.adj.values() if len(nb) >= 3),
                   "penalty_edge_count": len(graph.penalty)}
        response.found = True
        response.reason = ""
        response.message = ""
        response.sketch_json = json.dumps(sketch or {}, ensure_ascii=False)
        response.checks_json = json.dumps({"places": places, "summary": summary}, ensure_ascii=False)
        response.version = rb.file_version(paths["graph"])
        response.status = "apply_pending" if self._pending_apply == map_id else "applied"
        return response

    def handle_save(self, request, response):
        response.applied = False
        response.preview_json = ""
        response.checks_json = "{}"
        response.version = ""
        try:
            map_id = km.validate_map_id(request.map_id)
            grid = self._grid(map_id)
            places = rb.load_places(self.dest_root, map_id)
            result = rb.process_sketch(grid, request.sketch_json, places)
        except km.KeepoutError as error:
            response.accepted, response.reason, response.message = False, error.reason, error.message
            return response
        response.preview_json = json.dumps(rb.preview_json(result["graph"]), ensure_ascii=False)
        response.checks_json = self._checks(result)

        if request.preview_only:
            response.accepted = True
            response.reason = "check_failed" if result["errors"] else ""
            response.message = ""
            return response
        if result["errors"]:
            response.accepted = False
            response.reason = "check_failed"
            response.message = f"검사에서 {len(result['errors'])}건이 걸려 저장하지 않았습니다."
            return response

        paths = rb.route_paths(self.maps_root, map_id)
        with self._lock:
            current = rb.file_version(paths["graph"])
            if current and request.base_version != current and not request.overwrite:
                response.accepted = False
                response.reason = "conflict"
                response.version = current
                response.message = "편집하는 동안 다른 곳에서 레일이 새로 저장됐습니다."
                return response
            try:
                self._backup(paths["graph"])
                rb.save_route(self.maps_root, map_id, result, request.sketch_json, self._now())
            except km.KeepoutError as error:
                response.accepted, response.reason, response.message = False, error.reason, error.message
                return response
            response.version = rb.file_version(paths["graph"])
        response.accepted = True
        summary = result["summary"]
        saved = f"레일을 저장했습니다(노드 {summary['node_count']}개 · {summary['length_m']} m)."
        if result["warnings"]:
            saved += f" 주의 {len(result['warnings'])}건은 칸 안 목록을 확인하세요."
        self.get_logger().info(f"레일 저장: {map_id} {saved}")
        notice = String()
        notice.data = json.dumps({"map_id": map_id, "version": response.version, "at": self._now()},
                                 ensure_ascii=False)
        self.saved_publisher.publish(notice)

        if not request.apply_now:
            response.reason, response.message = "", saved
            return response
        if map_id != self._current_map_id():
            response.reason = "not_current_map"
            response.message = f"{saved} 지금 주행 지도가 아니라 다음에 이 지도로 주행할 때 적용됩니다."
            return response
        if self._hold_apply:
            self._pending_apply = map_id
            response.reason = "busy_driving"
            response.message = "현재 주행 중이므로 적용이 불가합니다. 주행 완료 후 적용합니다."
            return response
        applied, reason, message = self._apply(map_id)
        response.applied = applied
        response.reason = reason
        response.message = f"{saved} 로봇에 적용했습니다." if applied else f"{saved} {message}"
        return response

    def _apply(self, map_id: str) -> tuple[bool, str, str]:
        """route_server 에 새 레일 파일을 읽힌다. Nav2 재시작이 아니다."""
        path = rb.route_paths(self.maps_root, map_id)["graph"]
        if self._set_graph_client is None or not self._set_graph_client.service_is_ready():
            return (False, "no_route_server", "route server가 실행되면 적용됩니다.")
        request = self._set_graph_type.Request()
        request.graph_filepath = str(path)
        future = self._set_graph_client.call_async(request)
        done = Event()
        future.add_done_callback(lambda _: done.set())
        timeout = float(self.get_parameter("apply_timeout_sec").value)
        if not done.wait(timeout):
            return (False, "apply_timeout",
                    f"route server가 {timeout:.0f}초 안에 응답하지 않아 적용을 확인하지 못했습니다.")
        try:
            result = future.result()
        except Exception as error:  # noqa: BLE001 - 원인을 그대로 사람에게 보입니다.
            return (False, "apply_failed", f"적용에 실패했습니다: {error}")
        if result is not None and bool(result.success):
            self.get_logger().info(f"레일 적용: {path.name}")
            return (True, "", "적용했습니다.")
        self.get_logger().error(f"레일 적용 실패: {path.name}")
        return (False, "apply_failed", "route server가 새 레일 파일을 읽지 못했습니다.")

    def _backup(self, path: Path) -> None:
        """덮어쓰기 전 옛 레일을 maps/.route_backup/ 에 남긴다. 점(.) 폴더라 지도 목록에 안 뜬다."""
        if not path.is_file():
            return
        folder = path.parent / ".route_backup"
        try:
            folder.mkdir(exist_ok=True)
            stamp = datetime.now(KST).strftime("%Y%m%d_%H%M%S")
            shutil.copy2(path, folder / f"{path.stem}_{stamp}{path.suffix}")
        except OSError as error:
            raise km.KeepoutError("io_error", f"옛 레일을 백업하지 못했습니다: {error}") from error

    @staticmethod
    def _now() -> str:
        return datetime.now(KST).isoformat(timespec="seconds")


def main() -> None:
    """서비스 안에서 route_server 응답을 기다리므로 MultiThreadedExecutor 로 돈다."""
    rclpy.init()
    node = RouteGraphNode()
    executor = MultiThreadedExecutor(num_threads=3)
    executor.add_node(node)
    try:
        executor.spin()
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        executor.remove_node(node)
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
