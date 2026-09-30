"""route_graph_build.py 시험입니다. ROS도 로봇도 필요 없습니다.

pytest가 있으면:  python -m pytest VICA_Supervisor/ros2/test_route_graph_build.py

가짜 지도(해상도 0.05 m, 벽 = 검정 0, 빈 곳 = 흰색 254)를 그려 놓고 스케치를 넣어
설계서 2.7 의 다듬기·검사가 그대로 일어나는지 봅니다.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

import route_graph_build as rb  # noqa: E402

RES = 0.05


def _write_map(root: Path, name: str, free_rects, size=(20.0, 12.0)) -> None:
    """size(m) 크기의 벽 지도에 free_rects[(x0,y0,x1,y1)] 를 빈 곳으로 판다. origin (0,0)."""
    w, h = int(size[0] / RES), int(size[1] / RES)
    img = np.zeros((h, w), dtype=np.uint8)
    for x0, y0, x1, y1 in free_rects:
        c0, c1 = int(x0 / RES), int(x1 / RES)
        r0, r1 = h - int(y1 / RES), h - int(y0 / RES)
        img[r0:r1, c0:c1] = 254
    Image.fromarray(img).save(root / f"{name}.pgm")
    (root / f"{name}.yaml").write_text(
        f"image: {name}.pgm\nresolution: {RES}\norigin: [0.0, 0.0, 0.0]\n"
        "negate: 0\noccupied_thresh: 0.65\nfree_thresh: 0.196\nmode: trinary\n",
        encoding="utf-8")


@pytest.fixture()
def t_map(tmp_path: Path):
    """가로 복도(y 4~8, x 1~19) + 가운데서 아래로 곁복도(x 8~12, y 0.5~4). 폭 4 m."""
    _write_map(tmp_path, "t", [(1, 4, 19, 8), (8, 0.5, 12, 4.01)])
    return rb.MapGrid(tmp_path, "t"), tmp_path


def _sk(nodes, edges):
    return {"nodes": [{"id": i, "x": x, "y": y} for i, (x, y) in nodes.items()],
            "edges": [list(e) for e in edges]}


def _codes(items):
    return sorted({i["code"] for i in items})


# ── 스케치 읽기 ────────────────────────────────────────────────────────────

def test_sketch_needs_two_nodes_and_one_line():
    with pytest.raises(rb.RouteError) as err:
        rb.parse_sketch(_sk({1: (2, 6)}, []))
    assert err.value.reason == "bad_sketch"


def test_sketch_rejects_line_to_missing_node():
    with pytest.raises(rb.RouteError):
        rb.parse_sketch(_sk({1: (2, 6), 2: (5, 6)}, [(1, 9)]))


# ── 다듬기 ─────────────────────────────────────────────────────────────────

def test_straight_line_is_split_to_one_metre_and_both_ways(t_map):
    grid, _ = t_map
    r = rb.process_sketch(grid, _sk({1: (3, 6), 2: (17, 6)}, [(1, 2)]))
    assert r["errors"] == []
    g = r["graph"]
    assert all(math.dist(g.nodes[a], g.nodes[b]) <= rb.MAX_EDGE_M + 1e-9 for a, b in g.edges())
    doc = rb.graph_geojson(g)
    pairs = {(f["properties"]["startid"], f["properties"]["endid"])
             for f in doc["features"] if "startid" in f["properties"]}
    assert all((b, a) in pairs for a, b in pairs), "양방향 엣지 쌍이어야 한다"


def test_corner_is_rounded(t_map):
    grid, _ = t_map
    # 가로 복도 → 곁복도로 90° 꺾는 L 자
    r = rb.process_sketch(grid, _sk({1: (3, 6), 2: (10, 6), 3: (10, 1.5)}, [(1, 2), (2, 3)]))
    assert "sharp_corner" not in _codes(r["errors"])
    g = r["graph"]
    for b, nb in g.adj.items():
        if len(nb) == 2:
            a, c = sorted(nb)
            assert rb._turn_deg(g.nodes[a], g.nodes[b], g.nodes[c]) < rb.SHARP_MIN_DEG


def test_t_junction_becomes_y_with_penalty_and_no_detour(t_map):
    grid, _ = t_map
    sk = _sk({1: (3, 6), 2: (10, 6), 3: (17, 6), 4: (10, 1.5)}, [(1, 2), (2, 3), (2, 4)])
    r = rb.process_sketch(grid, sk)
    assert r["errors"] == [], r["errors"]
    g = r["graph"]
    assert r["summary"]["penalty_edge_count"] > 0
    assert set(g.penalty.values()) == {rb.JUNCTION_PENALTY}
    assert rb.junction_detours(g) == []


def test_without_penalty_the_same_junction_detours(t_map):
    """벌점이 막고 있는 것이 실제로 있는지 — 벌점을 지우면 V자가 생겨야 한다."""
    grid, _ = t_map
    sk = _sk({1: (3, 6), 2: (10, 6), 3: (17, 6), 4: (10, 1.5)}, [(1, 2), (2, 3), (2, 4)])
    g = rb.process_sketch(grid, sk)["graph"]
    g.penalty.clear()
    assert rb.junction_detours(g), "벌점 없이도 V자가 없다면 이 시험은 아무것도 지키지 않는다"


def test_crossing_lines_get_a_shared_node(t_map):
    grid, _ = t_map
    # 가로선과, 곁복도에서 올라와 가로 복도를 건너는 세로선. 교점에 노드가 생긴다.
    sk = _sk({1: (3, 6), 2: (17, 6), 3: (10, 1.5), 4: (10, 7.2)}, [(1, 2), (3, 4)])
    r = rb.process_sketch(grid, sk)
    g = r["graph"]
    assert any(len(nb) == 4 for nb in g.adj.values()), "교점에 이웃 4개 노드가 있어야 한다"
    assert "junction_sharp" in _codes(r["warnings"]), "X자는 Y로 못 만들어 경고"


# ── 검사 ───────────────────────────────────────────────────────────────────

def test_line_through_wall_is_rejected(t_map):
    grid, _ = t_map
    # 가로 복도에서 벽을 뚫고 지도 아래 빈 곳 없는 쪽으로
    r = rb.process_sketch(grid, _sk({1: (3, 6), 2: (3, 1)}, [(1, 2)]))
    assert "crosses_wall" in _codes(r["errors"])


def test_line_near_wall_is_rejected_with_value(t_map):
    grid, _ = t_map
    r = rb.process_sketch(grid, _sk({1: (3, 4.4), 2: (17, 4.4)}, [(1, 2)]))
    near = [e for e in r["errors"] if e["code"] == "too_close_to_wall"]
    assert near and all(e["value"] < rb.MIN_WALL_CLEAR_M for e in near)
    assert len(near) <= 16, "가까운 곳끼리는 묶어서 번호가 수십 개 찍히지 않는다"


def test_disconnected_parts_are_rejected(t_map):
    grid, _ = t_map
    r = rb.process_sketch(grid, _sk({1: (3, 6), 2: (6, 6), 3: (12, 6), 4: (17, 6)}, [(1, 2), (3, 4)]))
    assert "disconnected" in _codes(r["errors"])


def test_far_place_is_a_warning_not_an_error(t_map):
    grid, _ = t_map
    places = [{"name": "학과사무실", "x": 10, "y": 1.5}, {"name": "안내소", "x": 3, "y": 6.3}]
    r = rb.process_sketch(grid, _sk({1: (3, 6), 2: (17, 6)}, [(1, 2)]), places)
    assert r["errors"] == []
    far = [w for w in r["warnings"] if w["code"] == "far_place"]
    assert [w["name"] for w in far] == ["학과사무실"]
    by_name = {p["name"]: p for p in r["places"]}
    assert by_name["학과사무실"]["far"] and not by_name["안내소"]["far"]


# ── 파일 ───────────────────────────────────────────────────────────────────

def test_save_writes_graph_and_sketch_and_reloads(t_map):
    grid, root = t_map
    sk = _sk({1: (3, 6), 2: (10, 6), 3: (17, 6), 4: (10, 1.5)}, [(1, 2), (2, 3), (2, 4)])
    r = rb.process_sketch(grid, sk)
    paths = rb.save_route(root, "t", r, sk, "2026-09-30T20:00:00+09:00")
    doc = json.loads(paths["graph"].read_text(encoding="utf-8"))
    pens = [f["properties"]["metadata"]["penalty"] for f in doc["features"]
            if "metadata" in f["properties"]]
    assert pens and set(pens) == {rb.JUNCTION_PENALTY}
    assert rb.load_sketch(root, "t")["edges"] == sk["edges"]
    assert rb.file_version(paths["graph"])


def test_generator_rail_turns_back_into_a_small_sketch(t_map):
    """앱 편집 전 레일(생성기가 만든 것)도 고칠 수 있게 스케치로 되돌린다.
    되돌린 스케치를 다시 다듬으면 원래 레일과 같은 자리를 지난다."""
    grid, root = t_map
    sk = _sk({1: (3, 6), 2: (10, 6), 3: (17, 6), 4: (10, 1.5)}, [(1, 2), (2, 3), (2, 4)])
    g1 = rb.process_sketch(grid, sk)["graph"]
    back = rb.sketch_from_geojson(rb.graph_geojson(g1))
    assert len(back["nodes"]) <= 6
    g2 = rb.process_sketch(grid, back)["graph"]
    assert max(rb._point_to_graph(g2, *xy) for xy in g1.nodes.values()) < 0.05


def test_auto_draft_connects_places(t_map):
    grid, _ = t_map
    places = [{"name": "서쪽", "x": 2.5, "y": 6}, {"name": "동쪽", "x": 17.5, "y": 6},
              {"name": "아래", "x": 10, "y": 1.2}]
    d = rb.auto_draft(grid, places)
    assert d["shape"] in ("loop", "tree")
    assert d["result"]["errors"] == [], d["result"]["errors"]
    assert not any(p["far"] for p in d["result"]["places"])


def test_auto_draft_needs_two_places(t_map):
    grid, _ = t_map
    with pytest.raises(rb.RouteError) as err:
        rb.auto_draft(grid, [{"name": "하나", "x": 3, "y": 6}])
    assert err.value.reason == "no_destinations"
