#!/usr/bin/env python3
"""현재 VICA ROS 작업공간의 지도 목록을 Supervisor 앱에 제공하는 노드입니다.

연결 흐름:
    Flutter 앱
        -> /map_list_request
        -> MapListNode
        -> vica_ros2_ws/maps/*.png 및 같은 이름의 *.yaml 조회
        -> /map_list
        -> Flutter 앱

앱은 /map_list로 받은 image_url을 지도 HTTP 서버(app_mapserver)의 base URL과
합쳐 실제 PNG 지도를 불러옵니다. 이 노드는 지도 이미지를 직접 전송하지 않고,
지도 ID, 이미지 URL, resolution, origin, 이미지 크기 같은 메타데이터만 전송합니다.
"""

import json
import re
import shutil
from pathlib import Path
from typing import Any

import rclpy
from rclpy.node import Node
from std_msgs.msg import String

# 지도 이름 규칙. scripts/vica_map_save.sh 가 저장할 때 강제하는 것과 같아야 한다.
# 여기서는 안전장치이기도 하다 — 경로 문자를 막아 maps/ 밖을 못 건드리게 한다.
MAP_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")

# 한 지도에 딸린 파일들. pbstream 은 없을 수도 있다.
MAP_SUFFIXES = (".pgm", ".png", ".yaml", ".pbstream")


class MapListNode(Node):
    """지도 목록 요청을 받으면 maps_root의 PNG를 /map_list로 publish합니다.

    구독 topic:
        /map_list_request: 앱의 지도 목록 동기화 요청

    발행 topic:
        /map_list: 앱이 지도 드롭다운과 지도 캔버스에 사용할 지도 메타데이터
    """

    def __init__(self) -> None:
        super().__init__("vica_supervisor_map_list")

        workspace_root = Path(__file__).resolve().parents[2]
        default_maps_root = workspace_root / "vica_ros2_ws" / "maps"
        self.declare_parameter("maps_root", str(default_maps_root))
        self.maps_root = Path(
            str(self.get_parameter("maps_root").value)
        ).expanduser()

        # 앱이 시작되거나 동기화 버튼을 누르면 이 topic으로 빈 JSON/String 요청을 보냅니다.
        self.create_subscription(String, "/map_list_request", self.publish_maps, 10)

        # 목적지 카탈로그 위치. vica_destination_manager 와 같은 기본값을 쓴다.
        self.declare_parameter(
            "destination_storage_root", str(Path.home() / "vica_data" / "destinations")
        )
        self.destination_root = Path(
            str(self.get_parameter("destination_storage_root").value)
        ).expanduser()

        # 지도 목록 응답은 std_msgs/String JSON으로 보냅니다.
        self.publisher = self.create_publisher(String, "/map_list", 10)

        self._setup_delete_service()

    def _setup_delete_service(self) -> None:
        """지도 삭제 서비스를 엽니다.

        import 를 감싸는 이유: vica_interfaces 를 빌드하지 않은 환경에서 이 노드가
        기동 실패하면 안 됩니다. 목록 조회는 그것 없이도 되어야 합니다.
        (vica_status_app_node 의 _setup_health_source 와 같은 사정입니다.)
        """
        try:
            from vica_interfaces.srv import DeleteMap
        except ImportError as error:
            self.get_logger().warn(
                f"vica_interfaces/DeleteMap import 실패: {error}. "
                "지도 삭제 서비스를 열지 않습니다. 목록 조회는 정상입니다."
            )
            return
        self.create_service(DeleteMap, "/delete_map", self.handle_delete_map)
        self.get_logger().info("/delete_map 서비스 준비 완료")

    # ------------------------------------------------------------------
    # 삭제
    # ------------------------------------------------------------------

    def _current_map_id(self) -> str:
        """maps/CURRENT_MAP 이 가리키는 지도 이름. 없으면 빈 문자열."""
        path = self.maps_root / "CURRENT_MAP"
        try:
            return path.read_text(encoding="utf-8").strip()
        except OSError:
            return ""

    def handle_delete_map(self, request, response):
        """지도 파일 묶음을 지웁니다. 되돌릴 수 없으므로 검사를 먼저 합니다."""
        map_id = (request.map_id or "").strip()
        response.removed = []

        if not MAP_ID_PATTERN.match(map_id):
            response.accepted = False
            response.message = (
                "지도 이름이 올바르지 않습니다. 영문·숫자·밑줄(_)·붙임표(-)만 "
                "쓸 수 있고 경로는 넣을 수 없습니다."
            )
            return response

        # 지금 쓰는 지도는 지우지 않습니다. 지우면 초기 위치 스크립트와 앱이
        # 없는 지도를 가리키게 되고, 그 상태는 조용히 틀립니다.
        if map_id == self._current_map_id():
            response.accepted = False
            response.message = (
                f"'{map_id}' 는 현재 사용 중인 지도입니다. 다른 지도로 바꾼 뒤에 "
                "지워 주세요."
            )
            return response

        targets = [
            self.maps_root / f"{map_id}{suffix}" for suffix in MAP_SUFFIXES
        ]
        if not any(path.exists() for path in targets):
            response.accepted = False
            response.message = f"'{map_id}' 지도를 찾지 못했습니다."
            return response

        removed = []
        for path in targets:
            try:
                path.unlink()
                removed.append(str(path))
            except FileNotFoundError:
                continue
            except OSError as error:
                response.accepted = False
                response.message = f"{path} 를 지우지 못했습니다: {error}"
                response.removed = removed
                return response

        if request.delete_destinations:
            catalog = self.destination_root / map_id
            if catalog.is_dir():
                try:
                    shutil.rmtree(catalog)
                    removed.append(str(catalog))
                except OSError as error:
                    # 지도는 이미 지워졌다. 여기서 실패로 되돌릴 수 없으므로
                    # 사실만 알리고 성공으로 둔다.
                    self.get_logger().warn(f"{catalog} 정리 실패: {error}")

        response.accepted = True
        response.removed = removed
        response.message = f"'{map_id}' 를 지웠습니다 ({len(removed)}개)."
        self.get_logger().warn(response.message)

        # 목록을 곧바로 다시 보내 앱이 새로고침을 따로 누르지 않아도 되게 합니다.
        self.publish_maps(String())
        return response

    def publish_maps(self, _: String) -> None:
        """PNG 지도와 같은 이름의 YAML 메타데이터를 읽어 map list JSON을 구성합니다.

        처리:
            1. maps_root의 PNG를 정렬해 순회합니다.
            2. 같은 stem의 .yaml에서 resolution/origin을 읽습니다.
            3. PNG 헤더에서 width/height를 읽습니다.
            4. 앱이 이해하는 JSON 목록으로 묶어 /map_list에 publish합니다.
        """
        maps = []
        for image_path in sorted(self.maps_root.glob("*.png")):
            metadata = self._read_yaml_like_metadata(image_path.with_suffix(".yaml"))
            width, height = self._png_size(image_path)
            maps.append(
                {
                    "map_id": image_path.stem,
                    "map_name": image_path.stem,
                    "image_url": f"/maps/{image_path.name}",
                    "resolution": float(metadata.get("resolution", 0.05)),
                    "origin_x": float(metadata.get("origin_x", 0.0)),
                    "origin_y": float(metadata.get("origin_y", 0.0)),
                    "width": width,
                    "height": height,
                }
            )
        msg = String()
        msg.data = json.dumps({"maps": maps}, ensure_ascii=False)
        self.publisher.publish(msg)

    def _read_yaml_like_metadata(self, path: Path) -> dict[str, Any]:
        """외부 YAML 패키지 없이 ROS map yaml의 resolution/origin만 단순 파싱합니다.

        ROS map yaml은 보통 image, resolution, origin 등의 값을 가집니다.
        앱 좌표 변환에는 resolution과 origin x/y만 필요하므로 이 두 항목만 읽습니다.
        yaml 패키지 의존성을 추가하지 않기 위해 단순 문자열 파싱을 사용합니다.
        """
        metadata: dict[str, Any] = {}
        if not path.exists():
            # yaml이 없는 PNG도 지도 목록에는 보이게 하고 기본 resolution/origin을 씁니다.
            return metadata
        for line in path.read_text(encoding="utf-8").splitlines():
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            key = key.strip()
            value = value.strip()
            if key == "resolution":
                metadata["resolution"] = value
            elif key == "origin":
                origin = value.strip("[]").split(",")
                if len(origin) >= 2:
                    metadata["origin_x"] = origin[0].strip()
                    metadata["origin_y"] = origin[1].strip()
        return metadata

    def _png_size(self, path: Path) -> tuple[int, int]:
        """PNG IHDR 헤더에서 이미지 크기를 읽어 지도 좌표 변환에 사용합니다.

        Pillow 같은 이미지 라이브러리를 추가하지 않고 PNG 표준 헤더만 읽습니다.
        앱은 이 크기를 기준으로 ROS 좌표와 화면 픽셀 좌표를 변환합니다.
        """
        with path.open("rb") as file:
            signature = file.read(8)
            if signature != b"\x89PNG\r\n\x1a\n":
                return 1024, 1024
            file.read(8)
            width = int.from_bytes(file.read(4), "big")
            height = int.from_bytes(file.read(4), "big")
        return width, height


def main() -> None:
    """ROS2 노드를 초기화하고 지도 목록 요청 callback을 계속 대기합니다."""
    rclpy.init()
    node = MapListNode()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
