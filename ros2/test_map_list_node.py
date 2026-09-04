"""지도 목록 JSON 이 '현재 지도'를 싣는지 고정한다 (2026-09-03).

앱은 켤 때 이 표시로 젯슨이 달리는 지도를 먼저 고른다. 없으면 이름순 첫 지도를
골라 로봇과 다른 지도를 보게 된다.
"""
from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

pytest.importorskip("rclpy")  # 노드 모듈이 rclpy 를 import 한다
from map_list_node import build_map_list  # noqa: E402


def _png(path: Path, width: int, height: int) -> None:
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    chunk = b"IHDR" + ihdr
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + struct.pack(">I", len(ihdr)) + chunk + struct.pack(">I", zlib.crc32(chunk))
    )


def test_current_map_is_flagged_and_listed(tmp_path: Path) -> None:
    _png(tmp_path / "vica_map_00.png", 10, 20)
    _png(tmp_path / "vica_map_0630.png", 30, 40)
    (tmp_path / "vica_map_0630.yaml").write_text(
        "resolution: 0.05\norigin: [-6.0, 2.5, 0]\n", encoding="utf-8"
    )

    payload = build_map_list(tmp_path, "vica_map_0630")

    assert payload["current_map_id"] == "vica_map_0630"
    by_id = {m["map_id"]: m for m in payload["maps"]}
    assert by_id["vica_map_00"]["is_current"] is False
    assert by_id["vica_map_0630"]["is_current"] is True
    assert by_id["vica_map_0630"]["origin_x"] == -6.0
    assert (by_id["vica_map_0630"]["width"], by_id["vica_map_0630"]["height"]) == (30, 40)


def test_no_current_map_file_means_nothing_flagged(tmp_path: Path) -> None:
    _png(tmp_path / "a.png", 1, 1)
    payload = build_map_list(tmp_path, "")
    assert payload["current_map_id"] == ""
    assert all(m["is_current"] is False for m in payload["maps"])


def test_display_name_comes_from_meta_json(tmp_path: Path) -> None:
    # 한글 이름은 옆 파일(meta.json)에만 있고 파일 이름·URL 은 영문 id 다.
    _png(tmp_path / "map_0904_151230.png", 1, 1)
    (tmp_path / "map_0904_151230.meta.json").write_text(
        '{"map_id": "map_0904_151230", "display_name": "병원 2층"}', encoding="utf-8"
    )
    _png(tmp_path / "vica_map_00.png", 1, 1)
    (tmp_path / "vica_map_00.meta.json").write_text("{broken", encoding="utf-8")

    by_id = {m["map_id"]: m for m in build_map_list(tmp_path, "")["maps"]}
    assert by_id["map_0904_151230"]["map_name"] == "병원 2층"
    assert by_id["map_0904_151230"]["image_url"] == "/maps/map_0904_151230.png"
    assert by_id["vica_map_00"]["map_name"] == "vica_map_00"
