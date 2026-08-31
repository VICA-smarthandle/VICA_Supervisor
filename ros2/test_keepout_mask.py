#!/usr/bin/env python3
"""keepout_mask.py 시험입니다. ROS도 로봇도 필요 없습니다.

pytest가 있으면:      python -m pytest VICA_Supervisor/ros2/test_keepout_mask.py
pytest가 없으면:      python VICA_Supervisor/ros2/test_keepout_mask.py

작은 가짜 지도(10x8칸, 0.1 m/px)를 만들어 씁니다. 실제 지도(572x443)로 하면
어느 칸이 검게 칠해져야 하는지 손으로 셀 수 없어 시험이 시험을 검증하지
못합니다.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import keepout_mask as km  # noqa: E402

WIDTH = 10
HEIGHT = 8
RESOLUTION = 0.1
ORIGIN_X = -0.5
ORIGIN_Y = -0.4
NOW = "2026-08-31T21:00:00+09:00"


def make_map(root: Path, map_id: str = "test_map") -> Path:
    """가짜 지도 한 장을 만듭니다. 값은 전부 254(빈 칸)입니다."""
    root.mkdir(parents=True, exist_ok=True)
    header = f"P5\n{WIDTH} {HEIGHT}\n255\n".encode("ascii")
    (root / f"{map_id}.pgm").write_bytes(header + bytes([254]) * (WIDTH * HEIGHT))
    (root / f"{map_id}.yaml").write_text(
        f"image: {map_id}.pgm\n"
        "mode: trinary\n"
        f"resolution: {RESOLUTION}\n"
        f"origin: [{ORIGIN_X}, {ORIGIN_Y}, 0]\n"
        "negate: 0\n"
        "occupied_thresh: 0.65\n"
        "free_thresh: 0.25\n",
        encoding="utf-8",
    )
    return root


def read_mask_cells(path: Path) -> list[int]:
    """마스크 PGM의 픽셀 값만 뽑습니다."""
    data = path.read_bytes()
    width, height, _ = km._read_pnm_header(data)
    assert (width, height) == (WIDTH, HEIGHT), f"마스크 크기가 다릅니다: {width}x{height}"
    return list(data[len(data) - width * height :])


def black_cells(cells: list[int]) -> set[tuple[int, int]]:
    """검은 칸의 (열, 행) 집합입니다."""
    return {
        (index % WIDTH, index // WIDTH)
        for index, value in enumerate(cells)
        if value == km.BLOCK
    }


def zone(x_min: float, y_min: float, x_max: float, y_max: float, **extra) -> dict:
    return {"x_min": x_min, "y_min": y_min, "x_max": x_max, "y_max": y_max, **extra}


# ---------------------------------------------------------------------------
# 마스크 그리기
# ---------------------------------------------------------------------------


def test_빈_목록은_전부_회색이다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    km.save_zones(root, "test_map", [], NOW)

    cells = read_mask_cells(root / "test_map_keepout.pgm")
    assert set(cells) == {km.SKIP}, "사각형이 없는데 회색 아닌 칸이 있습니다"
    assert len(cells) == WIDTH * HEIGHT


def test_사각형_하나가_제자리에_칠해진다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    km.save_zones(root, "test_map", [zone(0.02, 0.02, 0.23, 0.23)], NOW)

    cells = read_mask_cells(root / "test_map_keepout.pgm")
    expected = {(col, row) for col in (5, 6, 7) for row in (1, 2, 3)}
    assert black_cells(cells) == expected


def test_반대_방향으로_끌어도_같은_사각형이다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    km.save_zones(root, "test_map", [zone(0.02, 0.02, 0.23, 0.23)], NOW)
    forward = read_mask_cells(root / "test_map_keepout.pgm")

    km.save_zones(root, "test_map", [zone(0.23, 0.23, 0.02, 0.02)], NOW)
    backward = read_mask_cells(root / "test_map_keepout.pgm")

    assert forward == backward


def test_사각형_여러_개가_모두_반영된다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    km.save_zones(
        root,
        "test_map",
        [
            zone(0.02, 0.02, 0.23, 0.23, zone_id="kz_a"),
            zone(-0.45, -0.35, -0.24, -0.14, zone_id="kz_b"),
        ],
        NOW,
    )

    # 두 번째 사각형은 지도의 왼쪽 아래입니다. ROS y가 작을수록 이미지 행 번호는
    # 커지므로 y -0.35~-0.14 는 아래쪽 행 5~7 이 됩니다.
    cells = black_cells(read_mask_cells(root / "test_map_keepout.pgm"))
    assert {(col, row) for col in (5, 6, 7) for row in (1, 2, 3)} <= cells
    assert {(col, row) for col in (0, 1, 2) for row in (5, 6, 7)} <= cells


def test_지도_밖으로_나간_부분은_잘린다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    km.save_zones(root, "test_map", [zone(0.32, 0.02, 5.0, 0.23)], NOW)

    cells = black_cells(read_mask_cells(root / "test_map_keepout.pgm"))
    assert cells == {(col, row) for col in (8, 9) for row in (1, 2, 3)}


# ---------------------------------------------------------------------------
# 거절해야 할 것
# ---------------------------------------------------------------------------


def test_너무_작은_사각형은_거절한다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    try:
        km.save_zones(root, "test_map", [zone(0.0, 0.0, 0.05, 0.05)], NOW)
    except km.KeepoutError as error:
        assert error.reason == "too_small"
    else:
        raise AssertionError("작은 사각형이 통과했습니다")


def test_지도_밖에만_있는_사각형은_거절한다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    try:
        km.save_zones(root, "test_map", [zone(5.0, 5.0, 6.0, 6.0)], NOW)
    except km.KeepoutError as error:
        assert error.reason == "out_of_map"
    else:
        raise AssertionError("지도 밖 사각형이 통과했습니다")


def test_숫자가_아닌_좌표는_거절한다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    try:
        km.save_zones(root, "test_map", [zone(float("nan"), 0.0, 0.5, 0.5)], NOW)
    except km.KeepoutError as error:
        assert error.reason == "bad_zone"
    else:
        raise AssertionError("NaN 좌표가 통과했습니다")


def test_경로를_담은_지도_이름은_거절한다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    try:
        km.save_zones(root, "../evil", [], NOW)
    except km.KeepoutError as error:
        assert error.reason == "bad_map_id"
    else:
        raise AssertionError("경로가 섞인 지도 이름이 통과했습니다")


def test_없는_지도는_no_map_으로_거절한다(tmp_path: Path) -> None:
    tmp_path.mkdir(parents=True, exist_ok=True)
    try:
        km.save_zones(tmp_path, "there_is_no_map", [], NOW)
    except km.KeepoutError as error:
        assert error.reason == "no_map"
    else:
        raise AssertionError("없는 지도가 통과했습니다")


# ---------------------------------------------------------------------------
# 원본 보호와 메타데이터
# ---------------------------------------------------------------------------


def test_원본_지도는_그대로_남는다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    before_pgm = (root / "test_map.pgm").read_bytes()
    before_yaml = (root / "test_map.yaml").read_bytes()

    km.save_zones(root, "test_map", [zone(0.02, 0.02, 0.23, 0.23)], NOW)

    assert (root / "test_map.pgm").read_bytes() == before_pgm
    assert (root / "test_map.yaml").read_bytes() == before_yaml


def test_마스크_yaml_이_원본과_같은_자리에_겹친다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    km.save_zones(root, "test_map", [], NOW)

    text = (root / "test_map_keepout.yaml").read_text(encoding="utf-8")
    assert "image: test_map_keepout.pgm" in text
    assert f"resolution: {RESOLUTION}" in text
    assert f"origin: [{ORIGIN_X}, {ORIGIN_Y}, 0]" in text
    assert "mode: trinary" in text
    # 배경 128(occ 0.498)이 '모름'으로 읽히려면 두 임계값 사이에 있어야 합니다.
    assert "occupied_thresh: 0.65" in text
    assert "free_thresh: 0.25" in text


def test_편집_원본을_다시_읽을_수_있다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    km.save_zones(
        root,
        "test_map",
        [zone(0.02, 0.02, 0.23, 0.23, zone_id="kz_계단", name="계단 앞")],
        NOW,
    )

    zones = km.load_zones(root, "test_map")
    assert len(zones) == 1
    assert zones[0]["zone_id"] == "kz_계단"
    assert zones[0]["name"] == "계단 앞"
    assert zones[0]["x_min"] == 0.02


def test_저장한_적_없으면_빈_목록이다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    assert km.load_zones(root, "test_map") == []


def test_빈_마스크는_없을_때만_만든다(tmp_path: Path) -> None:
    root = make_map(tmp_path)

    assert km.ensure_mask(root, "test_map", NOW) is True
    stamp = (root / "test_map_keepout.pgm").stat().st_mtime_ns
    body = (root / "test_map_keepout.pgm").read_bytes()

    assert km.ensure_mask(root, "test_map", NOW) is False
    assert (root / "test_map_keepout.pgm").stat().st_mtime_ns == stamp
    assert (root / "test_map_keepout.pgm").read_bytes() == body


def test_빈_마스크는_costmap_에_아무_일도_하지_않는다(tmp_path: Path) -> None:
    """회색만 있는 마스크는 KeepoutFilter가 모든 칸을 건너뜁니다."""
    root = make_map(tmp_path)
    km.ensure_mask(root, "test_map", NOW)

    cells = read_mask_cells(root / "test_map_keepout.pgm")
    assert set(cells) == {km.SKIP}


def test_구역_id_가_겹치면_거절한다(tmp_path: Path) -> None:
    root = make_map(tmp_path)
    try:
        km.save_zones(
            root,
            "test_map",
            [
                zone(0.02, 0.02, 0.23, 0.23, zone_id="kz_01"),
                zone(-0.45, -0.35, -0.24, -0.14, zone_id="kz_01"),
            ],
            NOW,
        )
    except km.KeepoutError as error:
        assert error.reason == "bad_zone"
    else:
        raise AssertionError("겹친 구역 id가 통과했습니다")


# ---------------------------------------------------------------------------
# 이미지 헤더 읽기
# ---------------------------------------------------------------------------


def test_주석이_섞인_pgm_헤더도_읽는다(tmp_path: Path) -> None:
    tmp_path.mkdir(parents=True, exist_ok=True)
    path = tmp_path / "commented.pgm"
    # bytes 리터럴에는 ASCII만 들어갑니다. 실제 map_saver 주석도 ASCII입니다.
    path.write_bytes(b"P5\n# CREATOR: map_saver\n4 3\n255\n" + bytes(12))
    assert km.read_image_size(path) == (4, 3)


def test_png_헤더도_읽는다(tmp_path: Path) -> None:
    tmp_path.mkdir(parents=True, exist_ok=True)
    path = tmp_path / "fake.png"
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + (13).to_bytes(4, "big")
        + b"IHDR"
        + (572).to_bytes(4, "big")
        + (443).to_bytes(4, "big")
    )
    assert km.read_image_size(path) == (572, 443)


# ---------------------------------------------------------------------------
# pytest 없이 돌리기
# ---------------------------------------------------------------------------


def main() -> int:
    import shutil
    import tempfile
    import traceback

    tests = [
        (name, value)
        for name, value in sorted(globals().items())
        if name.startswith("test_") and callable(value)
    ]
    failed = 0
    for name, test in tests:
        workdir = Path(tempfile.mkdtemp(prefix="keepout_test_"))
        try:
            test(workdir / "maps")
        except Exception:  # noqa: BLE001 - 시험 실행기이므로 전부 잡습니다.
            failed += 1
            print(f"  NG   {name}")
            traceback.print_exc()
        else:
            print(f"  OK   {name}")
        finally:
            shutil.rmtree(workdir, ignore_errors=True)

    print(f"\n{len(tests) - failed}/{len(tests)} 통과")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
