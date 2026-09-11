#!/usr/bin/env python3
"""폐기된 locations.json 저장 노드의 보호용 진입점."""
import sys


def main() -> int:
    print(
        "location_storage_node.py는 더 이상 사용하지 않습니다. "
        "`ros2 launch vica_destination_manager destination_manager.launch.py`를 "
        "실행하세요.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
