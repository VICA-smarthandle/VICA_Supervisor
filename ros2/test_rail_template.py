"""rail_template.py 시험입니다. ROS도 로봇도 필요 없습니다."""
from __future__ import annotations

import json
import math
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import keepout_mask as km  # noqa: E402
import rail_template as rt  # noqa: E402
import route_graph_build as rb  # noqa: E402
from test_route_graph_build import _write_map  # noqa: E402

CAP = [(1, 4.9, 0.5), (2, 0.0, 0.5), (3, 0.0, 2.74), (4, 4.9, 2.74)]
EDGES = [(1, 2), (2, 3), (3, 4)]
NODE1_AT_3_3_0 = {"id": 1, "x": 7.9, "y": 3.5}
PILLAR = [(1, 1, 5.9, 11), (6.1, 1, 19, 11), (5.8, 1, 6.2, 4.4), (5.8, 4.6, 6.2, 11)]


def _sketch_at(home):
    return {"nodes": [{"id": i, "x": x, "y": y}
                      for i, f, l in CAP for x, y in [rt.from_home_frame(f, l, home)]],
            "edges": [list(e) for e in EDGES]}


def _home_file(dest: Path, map_id: str, x: float, y: float, yaw: float) -> None:
    (dest / map_id).mkdir(parents=True, exist_ok=True)
    (dest / map_id / "home.yaml").write_text(
        f"map_id: {map_id}\npose:\n  frame_id: map\n  x: {x}\n  y: {y}\n  yaw: {yaw}\n", encoding="utf-8")


def _tpl():
    return rt.make_template(_sketch_at((0, 0, 0)), (0, 0, 0), name="t", source={})


class FakeService:
    """route_graph_node 대신. 받은 스케치를 남기고 정해 둔 답을 돌려준다."""

    def __init__(self):
        self.calls = []
        self.reply = {"accepted": True, "applied": True, "reason": "", "message": "레일을 저장했습니다."}
        self.error = None
        self.writer = None
        self.preview = None
        self.expects = []

    def __call__(self, map_id, sketch, wait_sec=None, expect=None):
        self.calls.append((map_id, sketch))
        self.expects.append(expect)
        if self.error:
            raise rt.TemplateError(self.error)
        if expect is not None and self.preview:
            rt.check_node_preview(expect, self.preview(map_id, sketch))
        if self.writer:
            self.writer(map_id, sketch)
        return dict(self.reply)


@pytest.fixture()
def roots(tmp_path: Path, monkeypatch):
    maps, dest = tmp_path / "maps", tmp_path / "dest"
    maps.mkdir()
    dest.mkdir()
    monkeypatch.setattr(rt, "TEMPLATE_DIR", tmp_path / "templates")
    fake = FakeService()
    monkeypatch.setattr(rt, "save_via_service", fake)
    return maps, dest, fake


def _summary(maps, map_id, sketch):
    return rb.process_sketch(rb.MapGrid(maps, map_id), sketch)["summary"]


def _prepare(maps, dest, src_yaw_file=270.0):
    """원본 지도 src 에 홈 (6, 9.5, 270°) 기준 ∩ 레일을 깔고 도장을 뜬다. 대상 지도 dst 는 빈 방."""
    _write_map(maps, "src", [(1, 1, 19, 11)])
    _write_map(maps, "dst", [(1, 1, 19, 11)])
    src_home = (6.0, 9.5, 270.0)
    rb.save_route(maps, "src", rb.process_sketch(rb.MapGrid(maps, "src"), _sketch_at(src_home)),
                  _sketch_at(src_home), "t")
    _home_file(dest, "src", 6.0, 9.5, src_yaw_file)
    args = ["--maps-root", str(maps), "--dest-root", str(dest)]
    assert rt.main(args + ["extract", "--map", "src"]) == 0
    return args


@pytest.mark.parametrize("yaw", [0.0, 90.0, 180.0, 270.0, 33.0])
def test_home_frame_round_trip(yaw):
    home = (3.0, -2.0, yaw)
    for f, l in [(0, 0), (4.9, 0.5), (-0.8, 3.52)]:
        x, y = rt.from_home_frame(f, l, home)
        f2, l2 = rt.to_home_frame(x, y, home)
        assert math.isclose(f, f2, abs_tol=1e-9) and math.isclose(l, l2, abs_tol=1e-9)


def test_forward_is_where_home_looks_and_left_is_its_left():
    x, y = rt.from_home_frame(1.0, 0.0, (0, 0, 270.0))
    assert math.isclose(x, 0, abs_tol=1e-9) and math.isclose(y, -1, abs_tol=1e-9)
    x, y = rt.from_home_frame(0.0, 1.0, (0, 0, 270.0))
    assert math.isclose(x, 1, abs_tol=1e-9) and math.isclose(y, 0, abs_tol=1e-9)


@pytest.mark.parametrize("raw, want", [
    (268.5, (270.0, True)), (-3.0, (0.0, True)), (359.0, (0.0, True)), (-90.5, (270.0, True)),
    (270.0, (270.0, False)), (45.0, (45.0, False)), (315.0, (315.0, False)), (280.0, (270.0, True)),
    (281.0, (281.0, False)),
])
def test_yaw_snaps_only_near_right_angles(raw, want):
    assert rt.snap_yaw(raw) == want


def test_extract_then_apply_on_rotated_home_gives_the_same_rail(roots):
    maps, dest, _ = roots
    _prepare(maps, dest)
    tpl = rt.load_template("demo_cap")
    assert [(n["forward"], n["left"]) for n in tpl["nodes"]] == [(f, l) for _, f, l in CAP]
    assert tpl["zone"] == {"forward_min": -0.8, "forward_max": 5.7, "left_min": -0.28, "left_max": 3.52}
    sketch = rt.place_sketch(tpl, (3.0, 3.0, 0.0))
    assert sketch["nodes"][0] == NODE1_AT_3_3_0
    want = dict(tpl["source"]["summary"])
    assert want.pop("corner_radii_m") == [1.0, 1.0]
    assert _summary(maps, "dst", sketch) == want


def test_extract_snaps_a_slightly_turned_source_home(roots):
    maps, dest, _ = roots
    _prepare(maps, dest, src_yaw_file=271.5)
    tpl = rt.load_template("demo_cap")
    assert [(n["forward"], n["left"]) for n in tpl["nodes"]] == [(f, l) for _, f, l in CAP]
    assert tpl["source"]["home"]["yaw_deg"] == 270.0 and tpl["source"]["home"]["yaw_deg_file"] == 271.5


def test_node_ids_keep_their_order():
    tpl = _tpl()
    assert [n["id"] for n in tpl["nodes"]] == [1, 2, 3, 4]
    assert [n["id"] for n in rt.place_sketch(tpl, (5, 5, 90))["nodes"]] == [1, 2, 3, 4]


def test_mirror_puts_the_rail_on_homes_right():
    tpl = _tpl()
    assert rt.place_sketch(tpl, (0, 0, 0))["nodes"][2]["y"] == 2.74
    assert rt.place_sketch(tpl, (0, 0, 0), mirror=True)["nodes"][2]["y"] == -2.74


def test_broken_template_is_a_clear_failure(roots, capsys):
    maps, dest, _ = roots
    rt.TEMPLATE_DIR.mkdir()
    (rt.TEMPLATE_DIR / "bad.json").write_text("{", encoding="utf-8")
    (rt.TEMPLATE_DIR / "no_left.json").write_text(json.dumps(
        {"nodes": [{"id": 1, "forward": 1.0}], "edges": [], "zone": _tpl()["zone"]}), encoding="utf-8")
    bare = {k: v for k, v in _tpl().items() if k not in ("name", "source")}
    (rt.TEMPLATE_DIR / "bare.json").write_text(json.dumps(bare), encoding="utf-8")
    _write_map(maps, "dst", [(1, 1, 19, 11)])
    _home_file(dest, "dst", 3, 3, 0)
    args = ["--maps-root", str(maps), "--dest-root", str(dest)]
    for name in ("bad", "no_left"):
        assert rt.main(args + ["apply", "--map", "dst", "--template", name]) == rt.EXIT_FAIL
        assert "도장 파일을 읽지 못했습니다" in capsys.readouterr().err
    assert rt.main(args + ["apply", "--map", "dst", "--template", "bare"]) == rt.EXIT_OK


def test_free_zone_passes_and_obstacle_blocks(roots):
    maps, _, _ = roots
    tpl = _tpl()
    home = (3.0, 3.0, 0.0)
    _write_map(maps, "free", [(1, 1, 19, 11)])
    zone = rt.check_zone(rb.MapGrid(maps, "free"), tpl, home)
    assert zone["occupied"] == 0 and rt.zone_blocks(zone) == []
    _write_map(maps, "pillar", PILLAR)
    zone = rt.check_zone(rb.MapGrid(maps, "pillar"), tpl, home)
    assert zone["occupied"] > 0
    assert any("장애물" in r for r in rt.zone_blocks(zone))
    x, y, _ = zone["occupied_spots"][0]
    assert math.isclose(x, 6.0, abs_tol=0.15) and math.isclose(y, 4.5, abs_tol=0.15)


def test_mirrored_zone_looks_on_the_right(roots):
    maps, _, _ = roots
    tpl = _tpl()
    _write_map(maps, "pillar", PILLAR)
    home = (3.0, 7.0, 0.0)
    assert rt.check_zone(rb.MapGrid(maps, "pillar"), tpl, home)["occupied"] == 0
    assert rt.check_zone(rb.MapGrid(maps, "pillar"), tpl, home, mirror=True)["occupied"] > 0


def test_home_too_close_to_wall_blocks(roots):
    maps, _, _ = roots
    _write_map(maps, "m", [(1, 1, 19, 11)])
    zone = rt.check_zone(rb.MapGrid(maps, "m"), _tpl(), (1.4, 6.0, 0.0))
    assert not zone["home_ok"]
    assert any("홈 둘레" in r for r in rt.zone_blocks(zone))


def test_keepout_inside_zone_is_counted_but_does_not_block(roots):
    maps, _, _ = roots
    _write_map(maps, "m", [(1, 1, 19, 11)])
    keep = [{"x_min": 3.6, "y_min": 4.0, "x_max": 4.0, "y_max": 4.4}]
    zone = rt.check_zone(rb.MapGrid(maps, "m"), _tpl(), (3.0, 3.0, 0.0), keepout_zones=keep)
    assert zone["keepout"] > 0 and rt.zone_blocks(zone) == []


def test_preview_writes_nothing_and_save_goes_through_the_rail_node(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 1.5)
    assert rt.main(args + ["apply", "--map", "dst"]) == rt.EXIT_OK
    out = capsys.readouterr().out
    assert "0° 로 맞춤" in out and "원본과 같음" in out and "미리보기만" in out
    assert fake.calls == [] and not rb.route_paths(maps, "dst")["graph"].exists()

    assert rt.main(args + ["apply", "--map", "dst", "--save"]) == rt.EXIT_OK
    assert "저장·적용했습니다" in capsys.readouterr().out
    assert fake.calls[0][0] == "dst" and fake.calls[0][1]["nodes"][0] == NODE1_AT_3_3_0
    assert not rb.route_paths(maps, "dst")["graph"].exists()


@pytest.mark.parametrize("reason, words", [
    ("no_route_server", "Nav2 를 다시 띄워야"),
    ("not_current_map", "이 지도로 Nav2 를 띄우면"),
    ("busy_driving", "주행이 끝나는 순간"),
])
def test_saved_but_not_applied_says_what_to_do(roots, capsys, reason, words):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    fake.reply = {"accepted": True, "applied": False, "reason": reason, "message": "…"}
    assert rt.main(args + ["apply", "--map", "dst", "--save"]) == rt.EXIT_NOT_APPLIED
    out = capsys.readouterr().out
    assert "아직 적용되지 않았습니다" in out and words in out


def test_conflict_is_reported_as_failure(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    fake.reply = {"accepted": False, "applied": False, "reason": "conflict", "message": "다른 곳에서 저장"}
    assert rt.main(args + ["apply", "--map", "dst", "--save"]) == rt.EXIT_FAIL
    assert "저장 안 됨[conflict]" in capsys.readouterr().out


def test_missing_rail_node_fails_instead_of_writing_files(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    fake.error = "레일 노드(/vica/route/save·get)가 5초 안에 안 보입니다."
    assert rt.main(args + ["apply", "--map", "dst", "--save"]) == rt.EXIT_FAIL
    assert "안 보입니다" in capsys.readouterr().err
    assert not rb.route_paths(maps, "dst")["graph"].exists()


def test_offline_writes_files_and_backs_up_the_old_rail(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    assert rt.main(args + ["apply", "--map", "dst", "--offline"]) == rt.EXIT_NOT_APPLIED
    saved = json.loads(rb.route_paths(maps, "dst")["edit"].read_text(encoding="utf-8"))["sketch"]
    assert saved["nodes"][0] == NODE1_AT_3_3_0 and fake.calls == []
    capsys.readouterr()
    assert rt.main(args + ["apply", "--map", "dst", "--offline"]) == rt.EXIT_NOT_APPLIED
    assert "기존 레일을 덮어씁니다" in capsys.readouterr().out
    assert len(list((maps / ".route_backup").glob("dst_route_*.geojson"))) == 1


def test_save_and_offline_are_exclusive_and_usage_errors_differ_from_stops(roots):
    maps, dest, _ = roots
    args = _prepare(maps, dest)
    with pytest.raises(SystemExit) as stop:
        rt.main(args + ["apply", "--map", "dst", "--save", "--offline"])
    assert stop.value.code == 2 and rt.EXIT_STOPPED != 2


def test_blocked_zone_stops_unless_forced(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    _write_map(maps, "dst", PILLAR)
    assert rt.main(args + ["apply", "--map", "dst", "--save"]) == rt.EXIT_STOPPED
    assert "--force 를 붙이세요" in capsys.readouterr().out
    assert fake.calls == []
    assert rt.main(args + ["apply", "--map", "dst", "--save", "--force"]) == rt.EXIT_OK
    assert len(fake.calls) == 1


def test_rail_through_wall_cannot_be_forced(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    _write_map(maps, "dst", [(1, 1, 5.4, 11), (5.6, 1, 19, 11)])
    assert rt.main(args + ["apply", "--map", "dst", "--save", "--force"]) == rt.EXIT_STOPPED
    out = capsys.readouterr().out
    assert "--force 로도 안 됨" in out and "--force 를 붙이세요" not in out
    assert fake.calls == []


def test_rail_through_keepout_stops(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    km.save_zones(maps, "dst", [{"x_min": 5.0, "y_min": 3.3, "x_max": 5.5, "y_max": 3.7}], "t")
    assert rt.main(args + ["apply", "--map", "dst", "--save"]) == rt.EXIT_STOPPED
    assert "레일이 금지구역을 지남" in capsys.readouterr().out
    assert fake.calls == []


def test_missing_home_is_a_clear_failure(roots, capsys):
    maps, dest, _ = roots
    args = _prepare(maps, dest)
    assert rt.main(args + ["apply", "--map", "dst"]) == rt.EXIT_FAIL
    assert "앱에서 이 지도의 홈을 먼저" in capsys.readouterr().err


@pytest.mark.parametrize("home_args", [["--home", "3,3,0"], ["--home=3,3,0"]])
def test_home_argument_replaces_home_file(roots, capsys, home_args):
    maps, dest, _ = roots
    args = _prepare(maps, dest)
    assert rt.main(args + ["apply", "--map", "dst"] + home_args) == rt.EXIT_OK
    assert "(7.900, 3.500)" in capsys.readouterr().out


def test_negative_home_x_is_read_as_a_value():
    assert rt._join_negative_home(["apply", "--home", "-1.0,2,90"]) == ["apply", "--home=-1.0,2,90"]
    assert rt._join_negative_home(["apply", "--home", "1,2,90"]) == ["apply", "--home", "1,2,90"]


@pytest.mark.parametrize("text, want", [
    ("4x7", (4.0, 7.0)), ("3.8x6.5", (3.8, 6.5)), ("4*7", (4.0, 7.0)), ("4×7", (4.0, 7.0)), (" 4.0X7.0 ", (4.0, 7.0)),
])
def test_parse_zone(text, want):
    assert rt.parse_zone(text) == want


@pytest.mark.parametrize("text", ["4", "4x", "x7", "4x7x2", "0x7", "-4x7"])
def test_parse_zone_rejects(text):
    with pytest.raises(rt.TemplateError):
        rt.parse_zone(text)


def test_stretch_moves_only_the_far_rail_and_the_far_end():
    base = _tpl()
    assert rt.zone_size(base) == (3.8, 6.5)
    tpl = rt.stretch_template(base, 4.0, 7.0, name="t47", base_name="t")
    assert rt.zone_size(tpl) == (4.0, 7.0) and rt.rail_size(tpl) == (2.44, 5.4)
    got = {n["id"]: (n["forward"], n["left"]) for n in tpl["nodes"]}
    assert got == {1: (5.4, 0.5), 2: (0.0, 0.5), 3: (0.0, 2.94), 4: (5.4, 2.94)}
    assert tpl["edges"] == base["edges"]
    assert (tpl["zone"]["left_min"], tpl["zone"]["forward_min"]) == (base["zone"]["left_min"], base["zone"]["forward_min"])
    assert tpl["source"]["summary"]["corner_radii_m"] == [1.0, 1.0]


def test_stretch_refuses_shapes_it_cannot_read():
    base = _tpl()
    with pytest.raises(rt.TemplateError):
        rt.stretch_template(base, 2.5, 6.5, name="x", base_name="t")
    mid = dict(base)
    mid["nodes"] = base["nodes"] + [{"id": 5, "forward": 2.45, "left": 0.5}]
    with pytest.raises(rt.TemplateError):
        rt.stretch_template(mid, 4.0, 7.0, name="x", base_name="t")


def test_extract_keeps_the_free_space_shape_as_the_basis(roots):
    maps, dest, _ = roots
    _prepare(maps, dest)
    tpl = rt.load_template("demo_cap")
    assert tpl["source"]["summary"] == rt.free_space_summary(tpl) == tpl["source"]["source_map_summary"]


def test_make_list_and_pick_by_zone(roots, capsys):
    maps, dest, _ = roots
    args = _prepare(maps, dest)
    assert rt.main(args + ["make", "--zone", "4x7"]) == rt.EXIT_OK
    assert (rt.TEMPLATE_DIR / "demo_cap_4.0x7.0.json").is_file()
    capsys.readouterr()
    assert rt.main(args + ["make", "--zone", "4x7"]) == rt.EXIT_FAIL
    assert "--overwrite" in capsys.readouterr().err
    assert rt.main(args + ["make", "--zone", "4x7", "--overwrite"]) == rt.EXIT_OK
    capsys.readouterr()
    assert rt.main(args + ["list"]) == rt.EXIT_OK
    out = capsys.readouterr().out
    assert "demo_cap (기본): 구역 3.8 × 6.5 m" in out
    assert "demo_cap_4.0x7.0: 구역 4.0 × 7.0 m · 레일 2.44 × 5.4 m" in out
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    assert rt.main(args + ["apply", "--map", "dst", "--zone", "4×7"]) == rt.EXIT_OK
    out = capsys.readouterr().out
    assert "도장 'demo_cap_4.0x7.0'" in out and "원본과 같음" in out and "(8.400, 3.500)" in out


def test_zone_not_found_or_ambiguous(roots, capsys):
    maps, dest, _ = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    assert rt.main(args + ["apply", "--map", "dst", "--zone", "5x9"]) == rt.EXIT_FAIL
    err = capsys.readouterr().err
    assert "5.0 × 9.0 m 도장이 없습니다" in err and "3.8x6.5(demo_cap)" in err and "make --zone 5.0x9.0" in err
    shutil.copy(rt.TEMPLATE_DIR / "demo_cap.json", rt.TEMPLATE_DIR / "copy.json")
    assert rt.main(args + ["apply", "--map", "dst", "--zone", "3.8x6.5"]) == rt.EXIT_FAIL
    assert "여럿입니다" in capsys.readouterr().err


def test_template_and_zone_are_exclusive(roots):
    maps, dest, _ = roots
    args = _prepare(maps, dest)
    with pytest.raises(SystemExit):
        rt.main(args + ["apply", "--map", "dst", "--template", "demo_cap", "--zone", "4x7"])


def test_extract_does_not_overwrite_without_flag(roots, capsys):
    maps, dest, _ = roots
    args = _prepare(maps, dest)
    assert rt.main(args + ["extract", "--map", "src"]) == rt.EXIT_FAIL
    assert "--overwrite" in capsys.readouterr().err
    assert rt.main(args + ["extract", "--map", "src", "--overwrite"]) == rt.EXIT_OK


def test_ignore_zone_skips_only_the_zone_margin(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    _write_map(maps, "dst", [(1, 1, 19, 6.52)])
    assert rt.main(args + ["apply", "--map", "dst", "--save"]) == rt.EXIT_STOPPED
    assert "--ignore-zone" in capsys.readouterr().out
    assert rt.main(args + ["apply", "--map", "dst", "--save", "--ignore-zone"]) == rt.EXIT_OK
    assert len(fake.calls) == 1


def test_ignore_zone_still_stops_a_rail_too_close_to_a_wall(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    _write_map(maps, "dst", [(1, 1, 19, 6.32)])
    assert rt.main(args + ["apply", "--map", "dst", "--save", "--ignore-zone"]) == rt.EXIT_STOPPED
    out = capsys.readouterr().out
    assert "미달" in out and "레일 벽 여유 0.5" in out and fake.calls == []


def test_corner_radii_of_a_straight_line_is_empty(roots):
    maps, _, _ = roots
    _write_map(maps, "m", [(1, 1, 19, 11)])
    r = rb.process_sketch(rb.MapGrid(maps, "m"), {"nodes": [{"id": 1, "x": 3, "y": 6}, {"id": 2, "x": 15, "y": 6}],
                                                  "edges": [[1, 2]]})
    assert rt.corner_radii(r["graph"]) == []


def _template_from(cap, edges=EDGES):
    nodes = [{"id": i, "forward": f, "left": l} for i, f, l in cap]
    fs, ls = [f for _, f, _ in cap], [l for _, _, l in cap]
    return {"name": "t", "nodes": nodes, "edges": [list(e) for e in edges], "source": {},
            "zone": {"forward_min": round(min(fs) - rt.ZONE_END_M, 4), "forward_max": round(max(fs) + rt.ZONE_END_M, 4),
                     "left_min": round(min(ls) - rt.ZONE_SIDE_M, 4), "left_max": round(max(ls) + rt.ZONE_SIDE_M, 4)}}


def test_stretch_pushes_the_side_far_from_home_when_the_rail_is_on_homes_right():
    right = _template_from([(i, f, -l) for i, f, l in CAP])
    tpl = rt.stretch_template(right, 4.0, 7.0, name="r", base_name="t")
    got = {n["id"]: (n["forward"], n["left"]) for n in tpl["nodes"]}
    assert got == {1: (5.4, -0.5), 2: (0.0, -0.5), 3: (0.0, -2.94), 4: (5.4, -2.94)}
    assert rt.zone_size(tpl) == (4.0, 7.0) and tpl["zone"]["left_max"] == right["zone"]["left_max"]


def test_stretch_pushes_the_far_end_when_the_rail_is_behind_home():
    behind = _template_from([(i, -f, l) for i, f, l in CAP])
    tpl = rt.stretch_template(behind, 4.0, 7.0, name="b", base_name="t")
    got = {n["id"]: (n["forward"], n["left"]) for n in tpl["nodes"]}
    assert got == {1: (-5.4, 0.5), 2: (0.0, 0.5), 3: (0.0, 2.94), 4: (-5.4, 2.94)}
    assert rt.zone_size(tpl) == (4.0, 7.0) and tpl["zone"]["forward_max"] == behind["zone"]["forward_max"]


def test_make_refuses_a_second_template_of_the_same_size_and_keeps_two_decimals(roots, capsys):
    maps, dest, _ = roots
    args = _prepare(maps, dest)
    assert rt.main(args + ["make", "--zone", "3.8x6.5"]) == rt.EXIT_FAIL
    assert "도장이 이미 있습니다(demo_cap)" in capsys.readouterr().err
    assert rt.main(args + ["make", "--zone", "4.25x7"]) == rt.EXIT_OK
    assert rt.main(args + ["make", "--zone", "4.2x7"]) == rt.EXIT_OK
    names = sorted(p.stem for p in rt.TEMPLATE_DIR.glob("*.json"))
    assert names == ["demo_cap", "demo_cap_4.25x7.0", "demo_cap_4.2x7.0"]
    for name, zone in (("demo_cap_4.25x7.0", (4.25, 7.0)), ("demo_cap_4.2x7.0", (4.2, 7.0))):
        assert rt.zone_size(rt.load_template(name)) == zone


@pytest.mark.parametrize("width, want", [(2.24, [1.0, 1.0]), (2.44, [1.0, 1.0]), (1.2, [0.54, 0.54])])
def test_corner_radii_are_the_real_fillets(roots, width, want):
    maps, _, _ = roots
    _write_map(maps, "m", [(1, 1, 19, 11)])
    cap = [(1, 4.9, 0.5), (2, 0.0, 0.5), (3, 0.0, 0.5 + width), (4, 4.9, 0.5 + width)]
    sketch = rt.place_sketch(_template_from(cap), (3.0, 3.0, 0.0))
    r = rb.process_sketch(rb.MapGrid(maps, "m"), sketch)
    assert rt.corner_radii(r["graph"]) == want


def test_stretched_template_with_mirror(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    assert rt.main(args + ["make", "--zone", "4x7"]) == rt.EXIT_OK
    _home_file(dest, "dst", 3.0, 9.0, 0.0)
    capsys.readouterr()
    assert rt.main(args + ["apply", "--map", "dst", "--zone", "4x7", "--mirror", "--save"]) == rt.EXIT_OK
    out = capsys.readouterr().out
    assert "원본과 같음" in out and "(8.400, 8.500)" in out
    nodes = {n["id"]: (n["x"], n["y"]) for n in fake.calls[0][1]["nodes"]}
    assert nodes[3] == (3.0, 6.06)


REAL_TEMPLATES = sorted(p.stem for p in rt.TEMPLATE_DIR.glob("*.json")
                        if p.stem == rt.DEFAULT_TEMPLATE
                        or json.loads(p.read_text(encoding="utf-8")).get("source", {}).get("made_from") == rt.DEFAULT_TEMPLATE)


@pytest.mark.parametrize("name", REAL_TEMPLATES)
def test_real_templates_follow_the_home_standard(tmp_path, name):
    tpl = rt.load_template(name)
    nodes = {n["id"]: (n["forward"], n["left"]) for n in tpl["nodes"]}
    assert nodes[2] == pytest.approx((-0.30, 0.30), abs=1e-3)
    fs, ls = [f for f, _ in nodes.values()], [l for _, l in nodes.values()]
    assert tpl["zone"] == pytest.approx({"forward_min": min(fs) - rt.ZONE_END_M, "forward_max": max(fs) + rt.ZONE_END_M,
                                         "left_min": min(ls) - rt.ZONE_SIDE_M, "left_max": max(ls) + rt.ZONE_SIDE_M},
                                        abs=1e-3)
    assert tpl["source"]["summary"] == rt.free_space_summary(tpl)
    assert tpl["source"]["summary"]["corner_radii_m"] == [1.0, 1.0]
    _write_map(tmp_path, "room", [(1, 1, 19, 11)])
    home = (6.0, 4.0, 0.0)
    g = rb.process_sketch(rb.MapGrid(tmp_path, "room"), rt.place_sketch(tpl, home))["graph"]
    near = min(math.dist(p, home[:2]) for a, b in g.edges() for p in rb._samples(g.nodes[a], g.nodes[b]))
    assert 0.45 < near < 0.55


def _real_node_writer(maps, shift=0.0):
    """레일 노드처럼 받은 스케치를 다듬어 파일로 쓴다. shift 는 다른 코드로 다듬은 셈 치는 차이."""
    def write(map_id, sketch):
        sk = json.loads(json.dumps(sketch))
        sk["nodes"][0]["x"] += shift
        rb.save_route(maps, map_id, rb.process_sketch(rb.MapGrid(maps, map_id), sk), sk, "t")
    return write


def test_save_checks_what_the_rail_node_wrote(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    fake.writer = _real_node_writer(maps)
    assert rt.main(args + ["apply", "--map", "dst", "--save"]) == rt.EXIT_OK
    assert "저장·적용했습니다" in capsys.readouterr().out
    fake.writer = _real_node_writer(maps, shift=0.3)
    assert rt.main(args + ["apply", "--map", "dst", "--save"]) == rt.EXIT_FAIL
    out = capsys.readouterr().out
    assert "미리보기와 다른 레일을 저장했습니다" in out and "supervisor 를 다시 켠 뒤" in out


def _node_preview(maps, shift=0.0):
    """레일 노드처럼 받은 스케치를 다듬어 preview_json 을 돌려준다(노드와 같은 rb.preview_json)."""
    def preview(map_id, sketch):
        sk = json.loads(json.dumps(sketch))
        sk["nodes"][0]["x"] += shift
        g = rb.process_sketch(rb.MapGrid(maps, map_id), sk)["graph"]
        return json.dumps(rb.preview_json(g))
    return preview


def test_save_stops_before_saving_when_the_rail_node_would_make_another_rail(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 0.0)
    fake.writer = _real_node_writer(maps)
    fake.preview = _node_preview(maps, shift=0.3)
    assert rt.main(args + ["apply", "--map", "dst", "--save"]) == rt.EXIT_FAIL
    assert "다른 레일을 만듭니다" in capsys.readouterr().err
    assert not rb.route_paths(maps, "dst")["graph"].exists()
    fake.preview = _node_preview(maps)
    assert rt.main(args + ["apply", "--map", "dst", "--save"]) == rt.EXIT_OK
    assert rb.route_paths(maps, "dst")["graph"].exists()
    assert fake.expects[-1] and len(fake.expects[-1]) == len(json.loads(fake.preview("dst", fake.calls[-1][1]))["nodes"])


def test_node_preview_check(tmp_path):
    _write_map(tmp_path, "m", [(1, 1, 19, 11)])
    g = rb.process_sketch(rb.MapGrid(tmp_path, "m"), _sketch_at((3.0, 3.0, 0.0)))["graph"]
    good = json.dumps(rb.preview_json(g))
    rt.check_node_preview(list(g.nodes.values()), good)
    rt.check_node_preview(list(g.nodes.values()), "")
    moved = [(x + 0.01, y) for x, y in g.nodes.values()]
    with pytest.raises(rt.TemplateError):
        rt.check_node_preview(moved, good)
    with pytest.raises(rt.TemplateError):
        rt.check_node_preview(list(g.nodes.values()), "{broken")


def test_extract_does_not_overwrite_the_home_standard_original(roots, capsys):
    maps, dest, _ = roots
    args = _prepare(maps, dest)
    tpl = rt.load_template("demo_cap")
    tpl["source"]["home_standard"] = {"since": "2026-10-12"}
    rt._write_template("demo_cap", tpl, overwrite=True)
    assert rt.main(args + ["make", "--zone", "4x7"]) == rt.EXIT_OK
    capsys.readouterr()
    for name in ("demo_cap", "demo_cap_4.0x7.0"):
        assert rt.main(args + ["extract", "--map", "src", "--name", name, "--overwrite"]) == rt.EXIT_FAIL
        assert "extract 로 덮지 않습니다" in capsys.readouterr().err
    assert rt.main(args + ["extract", "--map", "src", "--name", "other"]) == rt.EXIT_OK
    (rt.TEMPLATE_DIR / "broken.json").write_text("{", encoding="utf-8")
    assert rt.main(args + ["extract", "--map", "src", "--name", "broken", "--overwrite"]) == rt.EXIT_OK
