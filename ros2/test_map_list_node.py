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
from map_list_node import (  # noqa: E402
    MAP_SUFFIXES,
    apply_display_name,
    build_map_list,
    map_file_targets,
)


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


def test_rename_writes_meta_and_list_shows_it(tmp_path: Path) -> None:
    _png(tmp_path / "vica_map_0903_d.png", 1, 1)
    ok, message = apply_display_name(tmp_path, "vica_map_0903_d", "병원 2층")
    assert ok, message
    assert (tmp_path / "vica_map_0903_d.meta.json").is_file()
    by_id = {m["map_id"]: m for m in build_map_list(tmp_path, "")["maps"]}
    assert by_id["vica_map_0903_d"]["map_name"] == "병원 2층"
    # 파일·URL 은 그대로 id 다.
    assert by_id["vica_map_0903_d"]["image_url"] == "/maps/vica_map_0903_d.png"


def test_rename_rejects_names_used_by_other_maps(tmp_path: Path) -> None:
    _png(tmp_path / "a.png", 1, 1)
    _png(tmp_path / "b.png", 1, 1)
    assert apply_display_name(tmp_path, "a", "병원 2층")[0]
    ok, message = apply_display_name(tmp_path, "b", "병원 2층")
    assert not ok and "이미" in message
    # 이름표 없는 옛 지도의 id 와 겹쳐도 거부한다.
    (tmp_path / "old_map.yaml").write_text("resolution: 0.05\n", encoding="utf-8")
    assert not apply_display_name(tmp_path, "b", "old_map")[0]


def test_rename_to_empty_or_id_removes_meta(tmp_path: Path) -> None:
    _png(tmp_path / "a.png", 1, 1)
    apply_display_name(tmp_path, "a", "로비")
    assert apply_display_name(tmp_path, "a", "")[0]
    assert not (tmp_path / "a.meta.json").exists()


def test_rename_rejects_bad_ids_and_paths(tmp_path: Path) -> None:
    _png(tmp_path / "a.png", 1, 1)
    assert not apply_display_name(tmp_path, "../a", "로비")[0]
    assert not apply_display_name(tmp_path, "missing", "로비")[0]
    assert not apply_display_name(tmp_path, "a", "로/비")[0]
    assert not apply_display_name(tmp_path, "a", "가" * 41)[0]


def test_route_picture_is_not_listed_as_a_map(tmp_path: Path) -> None:
    """레일 확인용 그림(_route.png)이 가짜 지도로 뜨지 않는다 (2026-09-30)."""
    _png(tmp_path / "vica_map_0630.png", 30, 40)
    _png(tmp_path / "vica_map_0630_route.png", 30, 40)
    ids = [m["map_id"] for m in build_map_list(tmp_path, "")["maps"]]
    assert ids == ["vica_map_0630"]


def test_deleting_a_map_also_deletes_its_rail_files() -> None:
    """지도를 지우면 레일 파일도 같이 지운다 (2026-09-30 사용자 요청).

    남으면 같은 이름으로 새 지도를 만들 때 다른 장소의 레일이 붙는다.
    """
    for suffix in ("_route.geojson", "_route.png", "_route_edit.json",
                   "_route_draft.geojson"):
        assert suffix in MAP_SUFFIXES


def test_deleting_a_map_also_deletes_its_hidden_original(tmp_path: Path) -> None:
    """정렬해서 저장한 지도의 원본(maps/.original/)도 같이 지운다(2026-10-07, B안).

    남기면 같은 이름의 새 지도가 생겼을 때 다른 지도의 원본이 그 지도의 원본인 척한다.
    목록에는 원래부터 안 잡힌다 — 점 폴더이고 yaml·png 가 없다.
    """
    _png(tmp_path / "map_1007_143012.png", 1, 1)
    original = tmp_path / ".original"
    original.mkdir()
    (original / "map_1007_143012.pgm").write_bytes(b"P5")
    (original / "map_1007_143012.json").write_text("{}", encoding="utf-8")

    (original / "map_1007_143012.pgm.orphan-20261007-150000").write_bytes(b"P5")
    (original / "map_1007_1430120.pgm").write_bytes(b"P5")  # 다른 지도(이름 앞부분만 같음)

    targets = map_file_targets(tmp_path, "map_1007_143012")

    assert original / "map_1007_143012.pgm.orphan-20261007-150000" in targets
    assert original / "map_1007_1430120.pgm" not in targets

    assert original / "map_1007_143012.pgm" in targets
    assert original / "map_1007_143012.json" in targets
    assert [m["map_id"] for m in build_map_list(tmp_path, "")["maps"]] == ["map_1007_143012"]
