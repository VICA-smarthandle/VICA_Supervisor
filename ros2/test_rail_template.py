"""rail_template.py 시험입니다. ROS도 로봇도 필요 없습니다.

pytest가 있으면:  python -m pytest VICA_Supervisor/ros2/test_rail_template.py

가짜 지도(해상도 0.05 m)에 홈을 찍고, 도장을 뜬 뒤 다른 지도·다른 홈 방향에 찍어
같은 레일이 나오는지, 시연 구역 안 장애물을 잡는지, 저장 결과를 바르게 알리는지 봅니다.
레일 노드(/vica/route/save)는 가짜로 바꿔 실제 노드에 닿지 않습니다.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import keepout_mask as km  # noqa: E402
import rail_template as rt  # noqa: E402
import route_graph_build as rb  # noqa: E402
from test_route_graph_build import _write_map  # noqa: E402

# 연습장 ∩ 레일을 홈 기준으로 본 모양(2026-10-10 시연테스트 지도): 홈 앞 0~4.9 m, 왼쪽 0.5~2.74 m.
CAP = [(1, 4.9, 0.5), (2, 0.0, 0.5), (3, 0.0, 2.74), (4, 4.9, 2.74)]
EDGES = [(1, 2), (2, 3), (3, 4)]
# 홈 (3, 3, 0°) 에 찍으면 꼭짓점 1 은 (7.9, 3.5).
NODE1_AT_3_3_0 = {"id": 1, "x": 7.9, "y": 3.5}
# 홈 앞 3 m·왼쪽 1.5 m 근처((6.0, 4.5))에 0.2 m 기둥 하나.
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

    def __call__(self, map_id, sketch, wait_sec=None):
        self.calls.append((map_id, sketch))
        if self.error:
            raise rt.TemplateError(self.error)
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


# ── 홈 좌표계 ──────────────────────────────────────────────────────────────

@pytest.mark.parametrize("yaw", [0.0, 90.0, 180.0, 270.0, 33.0])
def test_home_frame_round_trip(yaw):
    home = (3.0, -2.0, yaw)
    for f, l in [(0, 0), (4.9, 0.5), (-0.8, 3.52)]:
        x, y = rt.from_home_frame(f, l, home)
        f2, l2 = rt.to_home_frame(x, y, home)
        assert math.isclose(f, f2, abs_tol=1e-9) and math.isclose(l, l2, abs_tol=1e-9)


def test_forward_is_where_home_looks_and_left_is_its_left():
    # 270° = 지도 아래(-y)를 본다. 그 왼쪽은 +x.
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


# ── 뜨기 → 찍기 ────────────────────────────────────────────────────────────

def test_extract_then_apply_on_rotated_home_gives_the_same_rail(roots):
    maps, dest, _ = roots
    _prepare(maps, dest)
    tpl = rt.load_template("demo_cap")
    assert [(n["forward"], n["left"]) for n in tpl["nodes"]] == [(f, l) for _, f, l in CAP]
    assert tpl["zone"] == {"forward_min": -0.8, "forward_max": 5.7, "left_min": -0.28, "left_max": 3.52}
    sketch = rt.place_sketch(tpl, (3.0, 3.0, 0.0))     # 다른 지도, 오른쪽(+x)을 보는 홈
    assert sketch["nodes"][0] == NODE1_AT_3_3_0
    assert _summary(maps, "dst", sketch) == tpl["source"]["summary"]


def test_extract_snaps_a_slightly_turned_source_home(roots):
    # 원본 홈 파일이 271.5° 여도 찍을 때처럼 270° 로 맞춰 뜬다. 안 맞추면 꼭짓점 1 의 왼쪽이 0.37 m 가 된다.
    maps, dest, _ = roots
    _prepare(maps, dest, src_yaw_file=271.5)
    tpl = rt.load_template("demo_cap")
    assert [(n["forward"], n["left"]) for n in tpl["nodes"]] == [(f, l) for _, f, l in CAP]
    assert tpl["source"]["home"]["yaw_deg"] == 270.0 and tpl["source"]["home"]["yaw_deg_file"] == 271.5


def test_node_ids_keep_their_order():
    # 코너는 번호 순서로 둥글려진다 — 번호가 바뀌면 R 1.0 이 다른 코너로 간다.
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
    # 손으로 고치다 꼭짓점의 left 를 지운 도장, name·source 가 없는 도장.
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


# ── 시연 구역 검사 ─────────────────────────────────────────────────────────

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
    # 홈 (3, 7, 0°) 오른쪽(아래, −y) 4.5 m 쯤에 기둥. 뒤집지 않으면 안 보이고, 뒤집으면 잡는다.
    maps, _, _ = roots
    tpl = _tpl()
    _write_map(maps, "pillar", PILLAR)
    home = (3.0, 7.0, 0.0)
    assert rt.check_zone(rb.MapGrid(maps, "pillar"), tpl, home)["occupied"] == 0
    assert rt.check_zone(rb.MapGrid(maps, "pillar"), tpl, home, mirror=True)["occupied"] > 0


def test_home_too_close_to_wall_blocks(roots):
    maps, _, _ = roots
    _write_map(maps, "m", [(1, 1, 19, 11)])
    zone = rt.check_zone(rb.MapGrid(maps, "m"), _tpl(), (1.4, 6.0, 0.0))   # 왼쪽 벽 0.4 m
    assert not zone["home_ok"]
    assert any("홈 둘레" in r for r in rt.zone_blocks(zone))


def test_keepout_inside_zone_is_counted_but_does_not_block(roots):
    maps, _, _ = roots
    _write_map(maps, "m", [(1, 1, 19, 11)])
    keep = [{"x_min": 3.6, "y_min": 4.0, "x_max": 4.0, "y_max": 4.4}]     # 레일 안쪽 빈 곳
    zone = rt.check_zone(rb.MapGrid(maps, "m"), _tpl(), (3.0, 3.0, 0.0), keepout_zones=keep)
    assert zone["keepout"] > 0 and rt.zone_blocks(zone) == []


# ── 명령: 미리보기·저장·멈춤 ───────────────────────────────────────────────

def test_preview_writes_nothing_and_save_goes_through_the_rail_node(roots, capsys):
    maps, dest, fake = roots
    args = _prepare(maps, dest)
    _home_file(dest, "dst", 3.0, 3.0, 1.5)          # 1.5° 틀어진 홈 → 0° 로 맞춘다
    assert rt.main(args + ["apply", "--map", "dst"]) == rt.EXIT_OK
    out = capsys.readouterr().out
    assert "0° 로 맞춤" in out and "원본과 같음" in out and "미리보기만" in out
    assert fake.calls == [] and not rb.route_paths(maps, "dst")["graph"].exists()

    assert rt.main(args + ["apply", "--map", "dst", "--save"]) == rt.EXIT_OK
    assert "저장·적용했습니다" in capsys.readouterr().out
    assert fake.calls[0][0] == "dst" and fake.calls[0][1]["nodes"][0] == NODE1_AT_3_3_0
    # 파일은 노드가 쓴다. 도구가 몰래 직접 쓰지 않는다.
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
    # 두 번째: 기존 레일이 있다고 알리고, 덮어쓰기 전에 백업한다.
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
    # 홈 앞 2.5 m 에서 가로로 막은 벽 — 레일 긴 변 둘이 벽을 지난다.
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
