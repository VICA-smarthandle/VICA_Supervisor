"""지도 목록 JSON 이 '현재 지도'를 싣는지 고정한다 (2026-09-03)."""
from __future__ import annotations

import os
import struct
import sys
import zlib
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

pytest.importorskip("rclpy")
from map_list_node import (  # noqa: E402
    count_destinations,
    MAP_SUFFIXES,
    apply_display_name,
    build_map_list,
    map_file_targets,
    fix_backup_dir,
    remove_fix_backups,
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
    assert by_id["vica_map_0903_d"]["image_url"] == "/maps/vica_map_0903_d.png"


def test_rename_rejects_names_used_by_other_maps(tmp_path: Path) -> None:
    _png(tmp_path / "a.png", 1, 1)
    _png(tmp_path / "b.png", 1, 1)
    assert apply_display_name(tmp_path, "a", "병원 2층")[0]
    ok, message = apply_display_name(tmp_path, "b", "병원 2층")
    assert not ok and "이미" in message
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
    """지도를 지우면 레일 파일도 같이 지운다 (2026-09-30 사용자 요청)."""
    for suffix in ("_route.geojson", "_route.png", "_route_edit.json",
                   "_route_draft.geojson"):
        assert suffix in MAP_SUFFIXES


def test_deleting_a_map_also_deletes_its_hidden_original(tmp_path: Path) -> None:
    """정렬해서 저장한 지도의 원본(maps/.original/)도 같이 지운다(2026-10-07, B안)."""
    _png(tmp_path / "map_1007_143012.png", 1, 1)
    original = tmp_path / ".original"
    original.mkdir()
    (original / "map_1007_143012.pgm").write_bytes(b"P5")
    (original / "map_1007_143012.json").write_text("{}", encoding="utf-8")

    (original / "map_1007_143012.pgm.orphan-20261007-150000").write_bytes(b"P5")
    (original / "map_1007_1430120.pgm").write_bytes(b"P5")

    targets = map_file_targets(tmp_path, "map_1007_143012")

    assert original / "map_1007_143012.pgm.orphan-20261007-150000" in targets
    assert original / "map_1007_1430120.pgm" not in targets

    assert original / "map_1007_143012.pgm" in targets
    assert original / "map_1007_143012.json" in targets
    assert [m["map_id"] for m in build_map_list(tmp_path, "")["maps"]] == ["map_1007_143012"]


def test_each_map_says_how_ready_it_is(tmp_path: Path) -> None:
    maps = tmp_path / "maps"
    maps.mkdir()
    _png(maps / "map_a.png", 10, 10)
    _png(maps / "map_b.png", 10, 10)
    (maps / "map_a_route.geojson").write_text("{}", encoding="utf-8")
    (maps / "map_a_keepout.yaml").write_text("image: map_a_keepout.pgm\n", encoding="utf-8")
    (maps / "map_a.meta.json").write_text('{"display_name": "4층", "saved_at": "2026-11-16T20:30:26"}',
                                          encoding="utf-8")
    dest = tmp_path / "dest"
    (dest / "map_a").mkdir(parents=True)
    (dest / "map_a" / "destinations.yaml").write_text(
        "schema_version: 1\nmap_id: map_a\ndestinations:\n- id: a\n  name: 410호\n  aliases:\n  - 410호\n"
        "- id: b\n  name: 409호\n", encoding="utf-8")
    by_id = {m["map_id"]: m for m in build_map_list(maps, "map_a", dest)["maps"]}
    assert by_id["map_a"]["has_route"] and by_id["map_a"]["has_keepout"]
    assert by_id["map_a"]["destination_count"] == 2
    assert by_id["map_a"]["saved_at"] == "2026-11-16T20:30:26"
    assert not by_id["map_b"]["has_route"] and not by_id["map_b"]["has_keepout"]
    assert by_id["map_b"]["destination_count"] == 0
    assert build_map_list(maps, "")["maps"][0]["destination_count"] is None


def test_empty_destination_list_counts_zero(tmp_path: Path) -> None:
    path = tmp_path / "destinations.yaml"
    path.write_text("schema_version: 1\ndestinations: []\n", encoding="utf-8")
    assert count_destinations(path) == 0


def test_each_map_carries_an_image_version(tmp_path: Path) -> None:
    """지도 그림을 고쳐 쓰면 버전이 바뀐다(2026-11-19, 지도 수정)."""
    path = tmp_path / "map_a.png"
    _png(path, 1, 1)
    first = build_map_list(tmp_path, "")["maps"][0]["image_version"]
    assert isinstance(first, int) and first > 0

    stamp = path.stat().st_mtime_ns + 5_000_000_000
    os.utime(path, ns=(stamp, stamp))

    assert build_map_list(tmp_path, "")["maps"][0]["image_version"] == first + 5000


def test_deleting_a_map_also_deletes_its_fix_backups(tmp_path: Path) -> None:
    """지도 수정의 백업(maps/.fix_backup/<map_id>/)도 지도와 같이 지운다."""
    for map_id in ("map_a", "map_ab"):
        folder = fix_backup_dir(tmp_path, map_id) / "20261119_101500_erase"
        folder.mkdir(parents=True)
        (folder / "entry.json").write_text("{}", encoding="utf-8")

    assert remove_fix_backups(tmp_path, "map_a") == fix_backup_dir(tmp_path, "map_a")

    assert not fix_backup_dir(tmp_path, "map_a").exists()
    assert fix_backup_dir(tmp_path, "map_ab").is_dir()
    assert remove_fix_backups(tmp_path, "map_a") is None
