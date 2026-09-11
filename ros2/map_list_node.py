#!/usr/bin/env python3
"""현재 VICA ROS 작업공간의 지도 목록을 Supervisor 앱에 제공하는 노드입니다."""

import json
from pathlib import Path
from typing import Any

import rclpy
from rclpy.node import Node
from std_msgs.msg import String


class MapListNode(Node):
    """지도 목록 요청을 받으면 maps_root의 PNG를 /map_list로 publish합니다."""

    def __init__(self) -> None:
        super().__init__("vica_supervisor_map_list")

        workspace_root = Path(__file__).resolve().parents[2]
        default_maps_root = workspace_root / "vica_ros2_ws" / "maps"
        self.declare_parameter("maps_root", str(default_maps_root))
        self.maps_root = Path(
            str(self.get_parameter("maps_root").value)
        ).expanduser()

        self.create_subscription(String, "/map_list_request", self.publish_maps, 10)

        self.publisher = self.create_publisher(String, "/map_list", 10)

    def publish_maps(self, _: String) -> None:
        """PNG 지도와 같은 이름의 YAML 메타데이터를 읽어 map list JSON을 구성합니다."""
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
        """외부 YAML 패키지 없이 ROS map yaml의 resolution/origin만 단순 파싱합니다."""
        metadata: dict[str, Any] = {}
        if not path.exists():
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
        """PNG IHDR 헤더에서 이미지 크기를 읽어 지도 좌표 변환에 사용합니다."""
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
