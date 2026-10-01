#!/usr/bin/env python3
"""레일(route graph) 스케치를 정식 레일로 다듬고 검사하는 순수 로직입니다.

ROS를 import하지 않습니다. keepout_mask.py 와 같은 구성입니다 — 노드
(route_graph_node.py)는 배선만, 판단은 여기에. 그래야 로봇 없이 시험합니다
(test_route_graph_build.py).

비유: 관리자(앱)는 **스케치**만 그립니다. 노드를 찍고 두 노드 사이를 선으로 잇는
것뿐입니다. 이 파일이 **제도사**입니다. 스케치를 받아 로봇이 실제로 따라 달릴 수
있는 레일로 다듬습니다. 규칙은 여기 한 곳에만 둡니다 — 앱을 고치지 않고 코너 규칙을
바꿀 수 있고, 앱 미리보기와 로봇이 달리는 모양이 어긋나지 않습니다.

다듬는 순서 (설계서 docs/superpowers/specs/2026-09-28-app-route-editor-design.md 2.7)
    1. 선끼리 교차하면 교차점에 노드를 넣는다. route_server 는 그림상 교차를 모르고
       "어느 노드가 어느 노드와 이어졌나"만 본다. 환승역이 없으면 갈아탈 수 없다.
    2. 갈림길(이웃 3개, 곧은 한 쌍 + 곁가지 하나)을 Y 호 두 개로 만들고, 그 호 엣지에
       penalty 0.1 을 단다. 갈림길 옆 직진이 호로 V자를 그리지 않게 한다(설계서 1부).
    3. 이웃 둘인 노드의 15~120° 코너를 반지름 1.0 → 0.75 → 0.5 m 호로 바꾼다.
    4. 1 m 넘는 엣지를 1 m 이하로 쪼갠다. route_server 가 첫 노드를 잘라낼 때 엣지가
       남아 있어야 한다(2026-09-16 run5 "zero length").
    5. 양방향 엣지로 GeoJSON 을 쓴다(엣지는 방향이 있다).

검사 — 저장을 막는다(BLOCKING_CODES, 2026-10-01 사용자 결정 "벽을 가로지르지만 않으면 통과")
    crosses_wall       선이 벽 칸을 지난다
경고 (위치를 돌려주지만 저장은 막지 않는다)
    disconnected       레일이 끊겨 섬이 있다
    too_close_to_wall  선이 벽에서 0.70 m 안으로 들어온다(외접반경 0.62 + 옆 오차 0.08)
    sharp_corner       30~120° 로 한 번에 꺾이는 곳이 남았다(호가 안 들어감)
    junction_detour    갈림길 옆 직진이 호로 돌아간다
    far_place          장소가 레일에서 2 m(BT handoff) 넘게 떨어져 있다
    junction_sharp     Y 로 만들 수 없는 갈림길(X자·다갈래)이라 뾰족한 채 둔다

자동 초안은 scripts/vica_route_graph.py(사람이 돌리던 생성기)의 길 찾기를 옮겨 왔다.
그 생성기는 레일을 **완성본**으로 만들지만, 여기서는 앱이 고칠 수 있게 **스케치**
(꺾이는 점과 선)만 만들고 다듬기는 위 공통 순서에 맡긴다.
"""
from __future__ import annotations

import heapq
import json
import math
from pathlib import Path
from typing import Any

import numpy as np
import yaml
from PIL import Image
from scipy import ndimage

import keepout_mask as km

# ---------------------------------------------------------------------------
# 규칙 값. 근거가 있는 값이라 바꿀 때는 근거를 같이 고친다.
# ---------------------------------------------------------------------------

# 엣지 상한(m). scripts/vica_route_graph.py·test_route_bt_contract.py 와 같아야 한다.
MAX_EDGE_M = 1.00
# 코너 호. v 0.5 / w 0.5 = R 1.0 이 상한이고, 안 들어가면 차례로 줄인다(2026-09-17 run20).
FILLET_RADII = (1.00, 0.75, 0.50)
FILLET_MIN_DEG = 15      # 이보다 덜 꺾이면 둥글리지 않는다
FILLET_MAX_DEG = 120     # 이보다 더 꺾이면 되돌림(U턴)이라 호가 안 된다
FILLET_STEP_DEG = 20     # 호 위 노드 간격(각도)
SHARP_MIN_DEG = 30       # 이 이상 한 번에 꺾이는 노드가 남으면 sharp_corner
STRAIGHT_MAX_DEG = 15    # 갈림길에서 이보다 덜 꺾이는 두 선은 '곧게 이어진' 큰길
# 갈림길 호 엣지 벌점. scripts/vica_route_graph.py 의 JUNCTION_PENALTY 와 같아야 한다.
JUNCTION_PENALTY = 0.1
# 벽 여유(m). 외접반경 0.620(몸 모서리가 도는 원) + 레일 옆 오차 0.08.
# scripts/vica_route_repair.py 의 --min-clear 기본값과 같다.
MIN_WALL_CLEAR_M = 0.70
# 목적지 이 거리 안이면 로봇이 레일을 내려 직접 들어간다(BT handoff_dist_to_goal).
HANDOFF_M = 2.0
# 선·벽 검사 간격(m). 지도 해상도 0.05 와 같다.
SAMPLE_M = 0.05
# 벽 칸: trinary 지도의 점유(검정). 회색(미탐색)은 벽이 아니다 — 회색까지 벽으로 세면
# 멀쩡한 레일을 "벽 0.05 m" 로 오진한다(2026-09-21, vica_route_repair.py 주석).
OCCUPIED_MAX = 50
# 저장을 막는 검사(2026-10-01 사용자 결정). 나머지 검사 — 벽 0.70 m·뾰족한 코너·갈림길 V자 —
# 는 알림(warnings)으로 보이고 저장은 된다. 지도상 어쩔 수 없이 좁은 곳이 많아 막으면 레일을
# 아예 못 깐다. 벽을 가로지르는 선(로봇이 갈 수 없는 길)만 막는다. 끊긴 섬도 알림이다 —
# 떨어진 쪽 레일은 route_server 가 못 이어 쓸 뿐 주행을 막지 않는다.
BLOCKING_CODES = frozenset({"crosses_wall"})
# 검사 결과를 이 거리 안에서는 하나로 묶는다. 같은 벽을 따라 번호가 수십 개 찍히지 않게.
ISSUE_MERGE_M = 1.0

# 자동 초안 (scripts/vica_route_graph.py 에서 옮김)
WANT_CLEAR = 1.00        # 벽에서 이만큼 떨어져 다니고 싶다
PREFER_CLEAR = 6.0       # 여유 부족에 붙는 비용 배수
SIMPLIFY_M = 0.25        # 이보다 작게 꺾이는 점은 지운다
MERGE_M = 0.60           # 이보다 가까운 노드는 하나로
SPECK_MAX_PX = 40        # 회색만으로 된 이 크기 이하 섬은 자유로 친다
STUB_M = HANDOFF_M       # 나무형 곁가지 하한 = BT 인계 거리
SKETCH_MIN_NODE_GAP_M = 0.8   # 초안 스케치 노드 최소 간격(앱에서 손으로 만지기 쉬운 간격)

ROUTE_SUFFIX = "_route"


class RouteError(km.KeepoutError):
    """앱에 그대로 돌려줄 수 있는 실패(reason 코드 + 사람 문장)."""


# ---------------------------------------------------------------------------
# 지도
# ---------------------------------------------------------------------------

class MapGrid:
    """지도 이미지 + 좌표 변환 + 벽까지 거리. 한 번 만들어 여러 번 쓴다."""

    def __init__(self, maps_root: Path, map_id: str) -> None:
        self.meta = km.read_map_meta(maps_root, map_id)
        path = maps_root / self.meta.image_name
        try:
            self.img = np.array(Image.open(str(path)).convert("L"))
        except OSError as error:
            raise RouteError("bad_map", f"지도 이미지를 읽지 못했습니다: {error}") from error
        self.res = self.meta.resolution
        self.h, self.w = self.img.shape
        self.occupied = self.img <= OCCUPIED_MAX
        # 벽(점유 칸)까지 거리(m).
        self.wall_dist = ndimage.distance_transform_edt(~self.occupied) * self.res

    def to_px(self, x: float, y: float) -> tuple[int, int]:
        r = int(round(self.h - 1 - (y - self.meta.origin_y) / self.res))
        c = int(round((x - self.meta.origin_x) / self.res))
        return r, c

    def to_world(self, r: int, c: int) -> tuple[float, float]:
        return (self.meta.origin_x + c * self.res,
                self.meta.origin_y + (self.h - 1 - r) * self.res)

    def inside(self, r: int, c: int) -> bool:
        return 0 <= r < self.h and 0 <= c < self.w

    def clearance(self, x: float, y: float) -> float:
        """벽까지 거리(m). 지도 밖은 0."""
        r, c = self.to_px(x, y)
        if not self.inside(r, c):
            return 0.0
        return float(self.wall_dist[r, c])

    def is_wall(self, x: float, y: float) -> bool:
        r, c = self.to_px(x, y)
        return (not self.inside(r, c)) or bool(self.occupied[r, c])


def _samples(a: tuple[float, float], b: tuple[float, float], step: float = SAMPLE_M):
    n = max(1, int(math.ceil(math.dist(a, b) / step)))
    for i in range(n + 1):
        t = i / n
        yield (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def segment_crosses_wall(grid: MapGrid, a, b) -> tuple[float, float] | None:
    """선분이 벽 칸을 지나면 처음 닿는 점, 아니면 None."""
    for p in _samples(a, b):
        if grid.is_wall(*p):
            return p
    return None


# ---------------------------------------------------------------------------
# 스케치
# ---------------------------------------------------------------------------

def parse_sketch(raw: Any) -> tuple[dict[int, tuple[float, float]], list[tuple[int, int]]]:
    """앱 스케치 JSON → (노드, 무방향 엣지).

    {"nodes":[{"id":1,"x":..,"y":..}], "edges":[[1,2], ...]}   좌표는 map(m)
    """
    if isinstance(raw, (str, bytes)):
        try:
            raw = json.loads(raw)
        except json.JSONDecodeError as error:
            raise RouteError("bad_sketch", f"스케치를 읽지 못했습니다: {error}") from error
    if not isinstance(raw, dict):
        raise RouteError("bad_sketch", "스케치 형식이 올바르지 않습니다.")
    nodes: dict[int, tuple[float, float]] = {}
    for item in raw.get("nodes") or []:
        try:
            nid, x, y = int(item["id"]), float(item["x"]), float(item["y"])
        except (KeyError, TypeError, ValueError):
            raise RouteError("bad_sketch", "노드에 id·x·y 가 없습니다.") from None
        if not (math.isfinite(x) and math.isfinite(y)):
            raise RouteError("bad_sketch", f"노드 {nid} 좌표가 숫자가 아닙니다.")
        if nid in nodes:
            raise RouteError("bad_sketch", f"노드 id 가 겹칩니다: {nid}")
        nodes[nid] = (x, y)
    edges: set[tuple[int, int]] = set()
    for item in raw.get("edges") or []:
        try:
            a, b = int(item[0]), int(item[1])
        except (IndexError, TypeError, ValueError):
            raise RouteError("bad_sketch", "선 형식이 올바르지 않습니다.") from None
        if a not in nodes or b not in nodes:
            raise RouteError("bad_sketch", f"없는 노드를 잇는 선이 있습니다: {a}-{b}")
        if a != b:
            edges.add((min(a, b), max(a, b)))
    if len(nodes) < 2 or not edges:
        raise RouteError("bad_sketch", "노드 2개 이상과 선 1개 이상이 필요합니다.")
    used = {n for e in edges for n in e}
    nodes = {k: v for k, v in nodes.items() if k in used}   # 선이 없는 노드는 버린다
    return nodes, sorted(edges)


def sketch_json(nodes: dict[int, tuple[float, float]], edges) -> dict[str, Any]:
    return {
        "nodes": [{"id": k, "x": round(v[0], 3), "y": round(v[1], 3)}
                  for k, v in sorted(nodes.items())],
        "edges": [[a, b] for a, b in sorted(edges)],
    }


# ---------------------------------------------------------------------------
# 그래프 (다듬는 동안 쓰는 모양)
# ---------------------------------------------------------------------------

class Graph:
    """무방향 그래프. 엣지 벌점은 frozenset({a,b}) 키."""

    def __init__(self, nodes: dict[int, tuple[float, float]], edges) -> None:
        self.nodes = dict(nodes)
        self.adj: dict[int, set[int]] = {k: set() for k in self.nodes}
        self.penalty: dict[frozenset, float] = {}
        # 호로 만든 노드. 코너 둥글리기가 호 위 점(20° 씩 꺾임)을 또 둥글리지 않게 한다.
        self.arc_nodes: set[int] = set()
        for a, b in edges:
            self.add_edge(a, b)
        self._next = max(self.nodes, default=0) + 1

    def new_node(self, xy) -> int:
        nid = self._next
        self._next += 1
        self.nodes[nid] = (float(xy[0]), float(xy[1]))
        self.adj[nid] = set()
        return nid

    def add_edge(self, a: int, b: int, penalty: float = 0.0) -> None:
        if a == b:
            return
        self.adj[a].add(b)
        self.adj[b].add(a)
        if penalty:
            self.penalty[frozenset((a, b))] = penalty

    def remove_edge(self, a: int, b: int) -> float:
        self.adj[a].discard(b)
        self.adj[b].discard(a)
        return self.penalty.pop(frozenset((a, b)), 0.0)

    def remove_node(self, n: int) -> None:
        for m in list(self.adj[n]):
            self.remove_edge(n, m)
        del self.adj[n]
        del self.nodes[n]

    def edges(self) -> list[tuple[int, int]]:
        return sorted({(min(a, b), max(a, b)) for a in self.adj for b in self.adj[a]})

    def chain(self, points, a: int, b: int, penalty: float = 0.0, arc: bool = False) -> None:
        """a → points... → b 로 새 노드를 이어 붙인다."""
        prev = a
        for p in points:
            nid = self.new_node(p)
            if arc:
                self.arc_nodes.add(nid)
            self.add_edge(prev, nid, penalty)
            prev = nid
        self.add_edge(prev, b, penalty)


def _turn_deg(a, b, c) -> float:
    """a→b→c 로 갈 때 진행 방향이 꺾이는 각(0 = 곧게)."""
    v1 = (b[0] - a[0], b[1] - a[1])
    v2 = (c[0] - b[0], c[1] - b[1])
    return abs(math.degrees(math.atan2(v1[0] * v2[1] - v1[1] * v2[0],
                                       v1[0] * v2[0] + v1[1] * v2[1])))


def _seg_intersection(p1, p2, p3, p4):
    """두 선분이 끝점이 아닌 곳에서 만나면 교점, 아니면 None."""
    d = (p2[0] - p1[0]) * (p4[1] - p3[1]) - (p2[1] - p1[1]) * (p4[0] - p3[0])
    if abs(d) < 1e-12:
        return None
    t = ((p3[0] - p1[0]) * (p4[1] - p3[1]) - (p3[1] - p1[1]) * (p4[0] - p3[0])) / d
    u = ((p3[0] - p1[0]) * (p2[1] - p1[1]) - (p3[1] - p1[1]) * (p2[0] - p1[0])) / d
    eps = 1e-6
    if eps < t < 1 - eps and eps < u < 1 - eps:
        return (p1[0] + t * (p2[0] - p1[0]), p1[1] + t * (p2[1] - p1[1]))
    return None


def split_intersections(g: Graph) -> int:
    """교차하는 두 선을 교점에서 나누고 교점에 노드를 넣는다. 넣은 수."""
    added = 0
    changed = True
    while changed:
        changed = False
        edges = g.edges()
        for i in range(len(edges)):
            a, b = edges[i]
            for j in range(i + 1, len(edges)):
                c, d = edges[j]
                if {a, b} & {c, d}:
                    continue
                x = _seg_intersection(g.nodes[a], g.nodes[b], g.nodes[c], g.nodes[d])
                if x is None:
                    continue
                n = g.new_node(x)
                for p, q in ((a, b), (c, d)):
                    pen = g.remove_edge(p, q)
                    g.add_edge(p, n, pen)
                    g.add_edge(n, q, pen)
                added += 1
                changed = True
                break
            if changed:
                break
    return added


def _arc_points(a, b, c, t: float):
    """코너 b(a→b→c)를 접점 거리 t 의 호로. (접점1, 호 사이 점들, 접점2, R) 또는 None."""
    va = (a[0] - b[0], a[1] - b[1])
    vc = (c[0] - b[0], c[1] - b[1])
    la, lc = math.hypot(*va), math.hypot(*vc)
    if la < 1e-6 or lc < 1e-6:
        return None
    cosphi = max(-1.0, min(1.0, (va[0] * vc[0] + va[1] * vc[1]) / (la * lc)))
    phi = math.acos(cosphi)                      # b 에서 본 내각
    tan_half = math.tan(phi / 2.0)
    if tan_half < 1e-6:
        return None
    R = t * tan_half
    ua = (va[0] / la, va[1] / la)
    uc = (vc[0] / lc, vc[1] / lc)
    p1 = (b[0] + ua[0] * t, b[1] + ua[1] * t)
    p2 = (b[0] + uc[0] * t, b[1] + uc[1] * t)
    bis = (ua[0] + uc[0], ua[1] + uc[1])
    lb = math.hypot(*bis)
    if lb < 1e-6:
        return None
    dc = R / math.sin(phi / 2.0)
    o = (b[0] + bis[0] / lb * dc, b[1] + bis[1] / lb * dc)
    a1 = math.atan2(p1[1] - o[1], p1[0] - o[0])
    a2 = math.atan2(p2[1] - o[1], p2[0] - o[0])
    sweep = (a2 - a1 + math.pi) % (2 * math.pi) - math.pi
    steps = max(2, int(math.ceil(abs(sweep) / math.radians(FILLET_STEP_DEG))))
    inner = [(o[0] + R * math.cos(a1 + sweep * k / steps),
              o[1] + R * math.sin(a1 + sweep * k / steps)) for k in range(1, steps)]
    return p1, inner, p2, R


def _clear_path(grid: MapGrid, pts) -> bool:
    return all(grid.clearance(*p) >= MIN_WALL_CLEAR_M
               for a, b in zip(pts, pts[1:]) for p in _samples(a, b))


def fillet_junctions(g: Graph, grid: MapGrid) -> list[dict[str, Any]]:
    """Y 갈림길: 곧은 한 쌍(a-J-c) + 곁가지 s. 호 두 개가 s 위 한 점 S' 에서 만난다.

        큰길  … a ── W' ── J ── E' ── c …
                      ╲         ╱
                       호     호          ← 벌점 엣지
                         ╲   ╱
                          S'
                          │  곁가지
                          s …
    만들 수 없는 갈림길은 경고만 남기고 뾰족하게 둔다.
    """
    warnings = []
    for j in [n for n in list(g.nodes) if len(g.adj.get(n, ())) >= 3]:
        nb = sorted(g.adj[j])
        J = g.nodes[j]
        pairs = [(a, c) for i, a in enumerate(nb) for c in nb[i + 1:]
                 if _turn_deg(g.nodes[a], J, g.nodes[c]) < STRAIGHT_MAX_DEG]
        spurs = [s for s in nb if not pairs or s not in pairs[0]]
        if len(nb) != 3 or len(pairs) != 1 or len(spurs) != 1:
            warnings.append({"code": "junction_sharp", "x": J[0], "y": J[1],
                             "message": "Y자로 만들 수 없는 갈림길이라 뾰족한 채 둡니다."})
            continue
        (a, c), s = pairs[0], spurs[0]
        A, C, S = g.nodes[a], g.nodes[c], g.nodes[s]
        turns = [_turn_deg(A, J, S), _turn_deg(C, J, S)]
        if not all(FILLET_MIN_DEG <= t <= FILLET_MAX_DEG for t in turns):
            warnings.append({"code": "junction_sharp", "x": J[0], "y": J[1],
                             "message": "갈림길 각도가 호를 놓을 수 없는 각이라 뾰족한 채 둡니다."})
            continue
        placed = False
        for R in FILLET_RADII:
            # 두 호의 접점 거리를 같게(t) 해야 S' 한 점에서 만난다.
            ts = []
            for P, turn in ((A, turns[0]), (C, turns[1])):
                phi = math.radians(180 - turn)
                ts.append(R / math.tan(phi / 2.0))
            t = min(ts + [0.45 * math.dist(J, A), 0.45 * math.dist(J, C),
                          0.45 * math.dist(J, S)])
            arc_w = _arc_points(A, J, S, t)
            arc_e = _arc_points(C, J, S, t)
            if not arc_w or not arc_e or min(arc_w[3], arc_e[3]) < 0.15:
                continue
            if not (_clear_path(grid, [arc_w[0], *arc_w[1], arc_w[2]])
                    and _clear_path(grid, [arc_e[0], *arc_e[1], arc_e[2]])):
                continue
            pen_a = g.remove_edge(a, j)
            pen_c = g.remove_edge(j, c)
            pen_s = g.remove_edge(j, s)
            w_id = g.new_node(arc_w[0])
            e_id = g.new_node(arc_e[0])
            s_id = g.new_node(arc_w[2])
            g.add_edge(a, w_id, pen_a)
            g.add_edge(w_id, j, pen_a)
            g.add_edge(j, e_id, pen_c)
            g.add_edge(e_id, c, pen_c)
            g.add_edge(s_id, s, pen_s)
            g.chain(arc_w[1], w_id, s_id, JUNCTION_PENALTY, arc=True)
            g.chain(arc_e[1], e_id, s_id, JUNCTION_PENALTY, arc=True)
            g.arc_nodes.update((w_id, e_id, s_id))
            placed = True
            break
        if not placed:
            warnings.append({"code": "junction_sharp", "x": J[0], "y": J[1],
                             "message": "갈림길 호가 벽에 가까워 들어가지 않아 뾰족한 채 둡니다."})
    return warnings


def fillet_corners(g: Graph, grid: MapGrid) -> None:
    """이웃 둘인 노드의 15~120° 코너를 호로. 안 들어가면 그대로(검사가 잡는다)."""
    for b in [n for n in list(g.nodes) if len(g.adj.get(n, ())) == 2]:
        if b not in g.nodes or len(g.adj[b]) != 2 or b in g.arc_nodes:
            continue
        a, c = sorted(g.adj[b])
        A, B, C = g.nodes[a], g.nodes[b], g.nodes[c]
        turn = _turn_deg(A, B, C)
        if not (FILLET_MIN_DEG <= turn <= FILLET_MAX_DEG):
            continue
        phi = math.radians(180 - turn)
        for R in FILLET_RADII:
            t = min(R / math.tan(phi / 2.0), 0.45 * math.dist(A, B), 0.45 * math.dist(B, C))
            arc = _arc_points(A, B, C, t)
            if not arc or arc[3] < 0.15:
                continue
            pts = [arc[0], *arc[1], arc[2]]
            if not _clear_path(grid, pts):
                continue
            pen_a = g.remove_edge(a, b)
            pen_c = g.remove_edge(b, c)
            g.remove_node(b)
            first = g.new_node(arc[0])
            g.add_edge(a, first, pen_a)
            last = g.new_node(arc[2])
            g.arc_nodes.update((first, last))
            g.chain(arc[1], first, last, pen_a if pen_a == pen_c else 0.0, arc=True)
            g.add_edge(last, c, pen_c)
            break


def split_long_edges(g: Graph) -> None:
    for a, b in g.edges():
        L = math.dist(g.nodes[a], g.nodes[b])
        if L <= MAX_EDGE_M + 1e-9:
            continue
        k = int(math.ceil(L / MAX_EDGE_M))
        A, B = g.nodes[a], g.nodes[b]
        pts = [(A[0] + (B[0] - A[0]) * i / k, A[1] + (B[1] - A[1]) * i / k) for i in range(1, k)]
        pen = g.remove_edge(a, b)
        g.chain(pts, a, b, pen)


# ---------------------------------------------------------------------------
# route_server 흉내 (V자 검사). test_route_bt_contract.py 와 같은 규칙이다.
# ---------------------------------------------------------------------------

def _route_like_server(g: Graph, start_xy, goal_xy):
    nodes = g.nodes
    s = min(nodes, key=lambda n: math.dist(nodes[n], start_xy))
    t = min(nodes, key=lambda n: math.dist(nodes[n], goal_xy))
    dist, prev, q = {s: 0.0}, {}, [(0.0, s)]
    while q:
        c, u = heapq.heappop(q)
        if u == t:
            break
        if c > dist[u]:
            continue
        for v in g.adj[u]:
            nc = c + math.dist(nodes[u], nodes[v]) + g.penalty.get(frozenset((u, v)), 0.0)
            if nc < dist.get(v, 1e18):
                dist[v], prev[v] = nc, u
                heapq.heappush(q, (nc, v))
    if t not in dist:
        return None
    path = [t]
    while path[-1] != s:
        path.append(prev[path[-1]])
    path.reverse()
    if len(path) > 1:     # goal_intent_extractor.cpp pruneStartandGoal (dot>0, 0.10 m)
        a, b = nodes[path[0]], nodes[path[1]]
        vr = (b[0] - a[0], b[1] - a[1])
        vp = (start_xy[0] - a[0], start_xy[1] - a[1])
        nr, npp = math.hypot(*vr), math.hypot(*vp)
        if npp > 0.10 and nr > 0 and (vr[0] * vp[0] + vr[1] * vp[1]) / (nr * npp) > 1e-4:
            path = path[1:]
    return path


def junction_detours(g: Graph) -> list[tuple[float, float]]:
    """갈림길 옆 직진이 큰길에서 0.3 m 넘게 벗어났다 돌아오는 자리."""
    nodes = g.nodes
    goals = [n for n, nb in g.adj.items() if len(nb) != 2]
    bad = []
    for j, nb in g.adj.items():
        if len(nb) < 3:
            continue
        nbl = sorted(nb)
        pairs = [(a, c) for i, a in enumerate(nbl) for c in nbl[i + 1:]
                 if _turn_deg(nodes[a], nodes[j], nodes[c]) < STRAIGHT_MAX_DEG]
        for a, c in pairs:
            A, C = nodes[a], nodes[c]
            dx, dy = C[0] - A[0], C[1] - A[1]
            norm = math.hypot(dx, dy)

            def off(xy):
                return abs(dx * (xy[1] - A[1]) - dy * (xy[0] - A[0])) / norm

            for p, q in ((a, j), (j, c)):
                for x, y in _samples(nodes[p], nodes[q], 0.1):
                    for goal in goals:
                        path = _route_like_server(g, (x, y), nodes[goal])
                        if not path:
                            continue
                        d = [off(nodes[n]) for n in path[:15]]
                        left = next((k for k, v in enumerate(d) if v > 0.3), None)
                        if left is not None and any(v < 0.1 for v in d[left:]):
                            bad.append((x, y))
                            break
    return bad


# ---------------------------------------------------------------------------
# 검사
# ---------------------------------------------------------------------------

def _merge_issues(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """같은 코드끼리 가까운 것을 하나로(가장 나쁜 값을 남긴다)."""
    out: list[dict[str, Any]] = []
    for it in sorted(items, key=lambda i: i.get("value", 0.0)):
        if any(o["code"] == it["code"] and math.dist((o["x"], o["y"]), (it["x"], it["y"])) < ISSUE_MERGE_M
               for o in out):
            continue
        out.append(it)
    return out


def check_graph(g: Graph, grid: MapGrid, sketch_walls) -> list[dict[str, Any]]:
    errors: list[dict[str, Any]] = []
    for (x, y) in sketch_walls:
        errors.append({"code": "crosses_wall", "x": x, "y": y,
                       "message": "선이 벽을 가로지릅니다. 노드를 옮기거나 선을 지워 주세요."})
    near = []
    for a, b in g.edges():
        for p in _samples(g.nodes[a], g.nodes[b]):
            c = grid.clearance(*p)
            if c < MIN_WALL_CLEAR_M:
                near.append({"code": "too_close_to_wall", "x": p[0], "y": p[1], "value": round(c, 2),
                             "message": f"선이 벽에 {c:.2f} m까지 붙습니다. "
                                        f"{MIN_WALL_CLEAR_M:.2f} m 이상 떨어져야 합니다. "
                                        "노드를 복도 가운데로 옮겨주세요."})
    errors += near
    # 끊김
    seen, stack = set(), [next(iter(g.nodes))]
    while stack:
        n = stack.pop()
        if n in seen:
            continue
        seen.add(n)
        stack.extend(g.adj[n])
    if seen != set(g.nodes):
        lost = next(n for n in g.nodes if n not in seen)
        x, y = g.nodes[lost]
        errors.append({"code": "disconnected", "x": x, "y": y,
                       "message": "레일이 끊겨 따로 떨어진 부분이 있습니다. 선으로 이어 주세요."})
    # 뾰족한 코너
    for b, nb in g.adj.items():
        if len(nb) != 2:
            continue
        a, c = sorted(nb)
        turn = _turn_deg(g.nodes[a], g.nodes[b], g.nodes[c])
        if SHARP_MIN_DEG <= turn <= FILLET_MAX_DEG:
            x, y = g.nodes[b]
            errors.append({"code": "sharp_corner", "x": x, "y": y, "value": round(turn),
                           "message": f"{round(turn)}° 로 급하게 꺾이는데 둥글릴 자리가 없습니다. "
                                      "노드를 벽에서 떼거나 선을 길게 해 주세요."})
    # V자
    for x, y in junction_detours(g):
        errors.append({"code": "junction_detour", "x": x, "y": y,
                       "message": "갈림길 옆을 곧게 지나갈 때 곁가지로 돌아가는 길이 생깁니다. "
                                  "갈림길을 큰길 한가운데 두어 주세요."})
    return _merge_issues(errors)


def load_places(dest_root: Path, map_id: str) -> list[dict[str, Any]]:
    doc = dest_root / map_id / "destinations.yaml"
    if not doc.is_file():
        return []
    try:
        data = yaml.safe_load(doc.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        return []
    out = []
    for d in data.get("destinations") or []:
        pose = d.get("pose") or {}
        try:
            out.append({"name": str(d.get("name") or d.get("id") or ""),
                        "x": float(pose["x"]), "y": float(pose["y"])})
        except (KeyError, TypeError, ValueError):
            continue
    return out


def _point_to_graph(g: Graph, x: float, y: float) -> float:
    best = min((math.dist(v, (x, y)) for v in g.nodes.values()), default=math.inf)
    for a, b in g.edges():
        A, B = g.nodes[a], g.nodes[b]
        dx, dy = B[0] - A[0], B[1] - A[1]
        L2 = dx * dx + dy * dy
        if L2 == 0:
            continue
        t = max(0.0, min(1.0, ((x - A[0]) * dx + (y - A[1]) * dy) / L2))
        best = min(best, math.dist((A[0] + t * dx, A[1] + t * dy), (x, y)))
    return best


def place_report(g: Graph, places) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    report, warnings = [], []
    for p in places:
        d = _point_to_graph(g, p["x"], p["y"])
        far = d > HANDOFF_M
        report.append({"name": p["name"], "distance": round(d, 2), "far": far})
        if far:
            warnings.append({"code": "far_place", "x": p["x"], "y": p["y"], "value": round(d, 1),
                             "name": p["name"],
                             "message": f"장소 '{p['name']}'이(가) 레일에서 {d:.1f} m 떨어져 있습니다. "
                                        "레일 없이 자유주행함을 주의하세요."})
    return report, warnings


# ---------------------------------------------------------------------------
# 한 번에: 스케치 → 레일
# ---------------------------------------------------------------------------

def process_sketch(grid: MapGrid, raw_sketch, places=()) -> dict[str, Any]:
    """스케치를 다듬고 검사한다. 파일은 쓰지 않는다(미리보기도 이것을 쓴다)."""
    nodes, edges = parse_sketch(raw_sketch)
    sketch_walls = []
    for a, b in edges:
        hit = segment_crosses_wall(grid, nodes[a], nodes[b])
        if hit:
            sketch_walls.append(hit)
    g = Graph(nodes, edges)
    split_intersections(g)
    warnings = fillet_junctions(g, grid)
    fillet_corners(g, grid)
    split_long_edges(g)
    issues = check_graph(g, grid, sketch_walls)
    errors = [i for i in issues if i["code"] in BLOCKING_CODES]
    # 막지 않는 검사는 알림 맨 앞에(가장 손볼 만한 것). 먼 장소·Y 불가 갈림길이 그 뒤.
    warnings = [i for i in issues if i["code"] not in BLOCKING_CODES] + warnings
    report, far = place_report(g, places)
    warnings += far
    edges_out = g.edges()
    length = sum(math.dist(g.nodes[a], g.nodes[b]) for a, b in edges_out)
    return {
        "graph": g,
        "errors": errors,
        "warnings": warnings,
        "places": report,
        "summary": {
            "node_count": len(g.nodes),
            "edge_count": 2 * len(edges_out),
            "length_m": round(length, 1),
            "junction_count": sum(1 for nb in g.adj.values() if len(nb) >= 3),
            "penalty_edge_count": len(g.penalty),
        },
    }


def graph_geojson(g: Graph) -> dict[str, Any]:
    """nav2_route GeoJsonGraphFileLoader 형식. id 는 1부터 다시 매긴다."""
    order = sorted(g.nodes)
    new_id = {old: i + 1 for i, old in enumerate(order)}
    feats = []
    for old in order:
        x, y = g.nodes[old]
        feats.append({"type": "Feature",
                      "properties": {"id": new_id[old], "frame": "map"},
                      "geometry": {"type": "Point", "coordinates": [round(x, 4), round(y, 4)]}})
    eid = 1000
    for a, b in g.edges():
        pen = g.penalty.get(frozenset((a, b)), 0.0)
        for p, q in ((a, b), (b, a)):
            eid += 1
            props: dict[str, Any] = {"id": eid, "startid": new_id[p], "endid": new_id[q]}
            if pen:
                props["metadata"] = {"penalty": pen}
            P, Q = g.nodes[p], g.nodes[q]
            feats.append({"type": "Feature", "properties": props,
                          "geometry": {"type": "MultiLineString",
                                       "coordinates": [[[round(P[0], 4), round(P[1], 4)],
                                                        [round(Q[0], 4), round(Q[1], 4)]]]}})
    return {"type": "FeatureCollection", "name": "vica_route_graph",
            "crs": {"type": "name", "properties": {"name": "urn:ogc:def:crs:EPSG::3857"}},
            "features": feats}


def preview_json(g: Graph) -> dict[str, Any]:
    """앱 미리보기용(무방향, 벌점 표시)."""
    return {"nodes": [{"id": k, "x": round(v[0], 3), "y": round(v[1], 3)} for k, v in sorted(g.nodes.items())],
            "edges": [[a, b, g.penalty.get(frozenset((a, b)), 0.0)] for a, b in g.edges()]}


def route_paths(maps_root: Path, map_id: str) -> dict[str, Path]:
    return {
        "graph": maps_root / f"{map_id}{ROUTE_SUFFIX}.geojson",
        "edit": maps_root / f"{map_id}{ROUTE_SUFFIX}_edit.json",
        "draft": maps_root / f"{map_id}{ROUTE_SUFFIX}_draft.geojson",
    }


def file_version(path: Path) -> str:
    """레일 파일의 판 표시. 다른 곳에서 먼저 저장했는지(팝업 F) 가르는 데 쓴다."""
    try:
        st = path.stat()
    except OSError:
        return ""
    return f"{st.st_mtime_ns}:{st.st_size}"


def save_route(maps_root: Path, map_id: str, result: dict[str, Any], sketch, updated_at: str) -> dict[str, Path]:
    """검사를 통과한 결과를 파일로. 레일과 스케치를 한꺼번에 바꾼다(반쯤 쓴 파일 없음)."""
    paths = route_paths(maps_root, map_id)
    nodes, edges = parse_sketch(sketch)
    edit = {"map_id": map_id, "updated_at": updated_at, "sketch": sketch_json(nodes, edges)}
    km.write_all_atomic([
        (paths["graph"], json.dumps(graph_geojson(result["graph"]), ensure_ascii=False, indent=2).encode("utf-8")),
        (paths["edit"], json.dumps(edit, ensure_ascii=False, indent=2).encode("utf-8")),
    ])
    return paths


def load_sketch(maps_root: Path, map_id: str) -> dict[str, Any] | None:
    """저장된 스케치. 없으면(앱에서 그린 적 없는 레일) 레일 파일에서 스케치를 만든다."""
    paths = route_paths(maps_root, map_id)
    if paths["edit"].is_file():
        try:
            return json.loads(paths["edit"].read_text(encoding="utf-8"))["sketch"]
        except (OSError, json.JSONDecodeError, KeyError):
            pass
    if paths["graph"].is_file():
        try:
            return sketch_from_geojson(json.loads(paths["graph"].read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError):
            return None
    return None


def graph_from_geojson(doc: dict[str, Any]) -> Graph:
    """nav2_route GeoJSON(양방향 엣지) → 무방향 Graph(벌점 포함)."""
    nodes: dict[int, tuple[float, float]] = {}
    edges = set()
    pen: dict[tuple[int, int], float] = {}
    for f in doc.get("features", []):
        pr = f.get("properties", {})
        if f.get("geometry", {}).get("type") == "Point":
            nodes[int(pr["id"])] = tuple(float(v) for v in f["geometry"]["coordinates"][:2])
        elif "startid" in pr:
            a, b = int(pr["startid"]), int(pr["endid"])
            key = (min(a, b), max(a, b))
            edges.add(key)
            value = float((pr.get("metadata") or {}).get("penalty", 0.0) or 0.0)
            if value:
                pen[key] = value
    g = Graph(nodes, [e for e in edges if e[0] in nodes and e[1] in nodes])
    for (a, b), value in pen.items():
        if a in nodes and b in nodes:
            g.penalty[frozenset((a, b))] = value
    return g


def sketch_from_geojson(doc: dict[str, Any]) -> dict[str, Any]:
    """완성 레일(생성기가 만든 것)을 손으로 고칠 수 있는 스케치로 되돌린다.

    1 m 사이 노드와 호 위 노드를 지우고, 끝·갈림길·꺾이는 점만 남긴다. 호는 저장할 때
    다시 둥글려진다. 갈림길 호는 곁가지 한 줄로 되돌린다(S' → 갈림길 J).
    """
    g = graph_from_geojson(doc)
    pen = {tuple(sorted(k)) for k in g.penalty}
    # 갈림길 호 걷어내기: 벌점 엣지를 지우고, 호가 모이던 점(S')을 두 호 시작점(W'·E')
    # 사이 큰길 노드(J)에 곧게 잇는다.
    if pen:
        touched = {n for e in pen for n in e}
        for a, b in pen:
            g.remove_edge(a, b)
        tips = [n for n in touched if n in g.adj and len(g.adj[n]) == 1 and
                all(frozenset((n, m)) not in g.penalty for m in g.adj[n])]
        for n in [n for n in touched if n in g.adj and not g.adj[n]]:
            g.remove_node(n)
        # S' = 곁가지로 이어지는 쪽(이웃 1, 큰길 노드가 아닌 쪽)
        spine = [n for n in touched if n in g.adj and len(g.adj[n]) == 2]
        for s in [n for n in tips if n in g.adj and len(g.adj[n]) == 1]:
            if spine:
                j = min(spine, key=lambda n: math.dist(g.nodes[n], g.nodes[s]))
                # W'·E' 사이 큰길 가운데 노드(이웃 둘이 모두 spine)
                mids = [m for m in g.adj if len(g.adj[m]) == 2 and all(k in spine for k in g.adj[m])]
                if mids:
                    j = min(mids, key=lambda n: math.dist(g.nodes[n], g.nodes[s]))
                g.add_edge(j, s)
    # 곧게 이어지는 중간 노드 걷어내기(이웃 둘, 꺾임 < 10°, 만나는 두 선 합이 짧지 않을 때까지)
    changed = True
    while changed:
        changed = False
        for b in list(g.nodes):
            if b not in g.adj or len(g.adj[b]) != 2:
                continue
            a, c = sorted(g.adj[b])
            if _turn_deg(g.nodes[a], g.nodes[b], g.nodes[c]) < 10:
                g.remove_edge(a, b)
                g.remove_edge(b, c)
                g.remove_node(b)
                g.add_edge(a, c)
                changed = True
    # 호 위 점 걷어내기: 이웃 둘이고 가까운(< MERGE_M) 점이 연달아 있으면 가운데로 모은다.
    changed = True
    while changed:
        changed = False
        for b in list(g.nodes):
            if b not in g.adj or len(g.adj[b]) != 2:
                continue
            a, c = sorted(g.adj[b])
            if math.dist(g.nodes[a], g.nodes[b]) < MERGE_M and len(g.adj[a]) == 2:
                g.remove_edge(a, b)
                g.remove_edge(b, c)
                g.remove_node(b)
                g.add_edge(a, c)
                changed = True
    ids = {old: i + 1 for i, old in enumerate(sorted(g.nodes))}
    return sketch_json({ids[k]: v for k, v in g.nodes.items()},
                       [(ids[a], ids[b]) for a, b in g.edges()])


# ---------------------------------------------------------------------------
# 자동 초안 (scripts/vica_route_graph.py 에서 옮김 — 스케치까지만 만든다)
# ---------------------------------------------------------------------------

def _free_mask(img):
    free = img > 250
    lab, n = ndimage.label(~free)
    if n == 0:
        return free
    idx = range(1, n + 1)
    sizes = ndimage.sum(np.ones(img.shape, dtype=np.int32), lab, idx)
    blacks = ndimage.sum(img < 200, lab, idx)
    specks = [k + 1 for k in range(n) if sizes[k] <= SPECK_MAX_PX and blacks[k] == 0]
    if specks:
        free = free | np.isin(lab, specks)
    return free


def _dijkstra(mask, clearance, start, goal, res):
    h, w = mask.shape
    dist = np.full((h, w), math.inf)
    prev = {}
    dist[start] = 0.0
    pq = [(0.0, start)]
    nb = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0),
          (-1, -1, 1.4142), (-1, 1, 1.4142), (1, -1, 1.4142), (1, 1, 1.4142)]
    hit = (lambda rc: rc == goal) if isinstance(goal, tuple) else (lambda rc: bool(goal[rc]))
    found = None
    while pq:
        d, (r, c) = heapq.heappop(pq)
        if d > dist[r, c]:
            continue
        if hit((r, c)):
            found = (r, c)
            break
        for dr, dc, step in nb:
            nr, nc = r + dr, c + dc
            if not (0 <= nr < h and 0 <= nc < w) or not mask[nr, nc]:
                continue
            short = max(0.0, WANT_CLEAR - clearance[nr, nc])
            nd = d + step * res * (1.0 + PREFER_CLEAR * short)
            if nd < dist[nr, nc]:
                dist[nr, nc] = nd
                prev[(nr, nc)] = (r, c)
                heapq.heappush(pq, (nd, (nr, nc)))
    if found is None:
        return None
    path, cur = [found], found
    while cur != start:
        cur = prev[cur]
        path.append(cur)
    return path[::-1]


def _simplify(points, tol):
    """Douglas-Peucker (반복형 — 재귀 한계에 안 걸린다)."""
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    pts = np.array(points, float)
    while stack:
        i0, i1 = stack.pop()
        if i1 - i0 < 2:
            continue
        a, b = pts[i0], pts[i1]
        ab = b - a
        n = np.hypot(*ab)
        seg = pts[i0 + 1:i1]
        if n < 1e-9:
            d = np.hypot(*(seg - a).T)
        else:
            d = np.abs(ab[0] * (seg[:, 1] - a[1]) - ab[1] * (seg[:, 0] - a[0])) / n
        k = int(np.argmax(d))
        if d[k] > tol:
            m = i0 + 1 + k
            keep[m] = True
            stack += [(i0, m), (m, i1)]
    return [p for p, k in zip(points, keep) if k]


def _nearest_true(mask, r, c):
    if mask[r, c]:
        return (r, c)
    idx = ndimage.distance_transform_edt(~mask, return_distances=False, return_indices=True)
    return int(idx[0][r, c]), int(idx[1][r, c])


class _SketchBuilder:
    def __init__(self, grid: MapGrid) -> None:
        self.grid = grid
        self.nodes: dict[int, tuple[float, float]] = {}
        self.edges: set[tuple[int, int]] = set()

    def node(self, xy) -> int:
        for k, v in self.nodes.items():
            if math.dist(v, xy) < SKETCH_MIN_NODE_GAP_M:
                return k
        k = len(self.nodes) + 1
        self.nodes[k] = (float(xy[0]), float(xy[1]))
        return k

    def polyline(self, cells) -> list[int]:
        pts = _simplify(cells, SIMPLIFY_M / self.grid.res)
        ids: list[int] = []
        for rc in pts:
            k = self.node(self.grid.to_world(*rc))
            if not ids or ids[-1] != k:
                ids.append(k)
        for a, b in zip(ids, ids[1:]):
            if a != b:
                self.edges.add((min(a, b), max(a, b)))
        return ids


def auto_draft(grid: MapGrid, places, shape: str = "auto") -> dict[str, Any]:
    """장소들을 잇는 초안 스케치. shape: 'loop' | 'tree' | 'auto'(둘 다 만들어 나은 쪽).

    나은 쪽 = 검사 오류가 적은 쪽, 같으면 레일이 짧은 쪽.
    """
    if len(places) < 2:
        raise RouteError("no_destinations", "장소가 2개 이상 있어야 초안을 만들 수 있습니다.")
    free = _free_mask(grid.img)
    clearance_free = ndimage.distance_transform_edt(free) * grid.res
    drivable = free & (clearance_free >= 0.25)
    lab, n = ndimage.label(drivable)
    if n > 1:
        big = 1 + int(np.argmax(np.bincount(lab.ravel())[1:]))
        drivable = lab == big
    entries = []
    for p in places:
        r, c = grid.to_px(p["x"], p["y"])
        r = min(max(r, 0), grid.h - 1)
        c = min(max(c, 0), grid.w - 1)
        entries.append({"name": p["name"], "px": _nearest_true(drivable, r, c)})

    shapes = ["loop", "tree"] if shape == "auto" else [shape]
    best = None
    for kind in shapes:
        sb = _SketchBuilder(grid)
        if kind == "loop":
            cy = float(np.mean([e["px"][0] for e in entries]))
            cx = float(np.mean([e["px"][1] for e in entries]))
            order = sorted(entries, key=lambda e: math.atan2(cy - e["px"][0], e["px"][1] - cx))
            for i in range(len(order)):
                a, b = order[i], order[(i + 1) % len(order)]
                path = _dijkstra(drivable, clearance_free, a["px"], b["px"], grid.res)
                if path:
                    sb.polyline(path)
        else:
            a, b = max(((p, q) for p in entries for q in entries),
                       key=lambda pq: math.dist(pq[0]["px"], pq[1]["px"]))
            spine = _dijkstra(drivable, clearance_free, a["px"], b["px"], grid.res)
            if not spine:
                continue
            rail = np.zeros_like(drivable)
            rail[tuple(np.array(spine).T)] = True
            spine_ids = sb.polyline(spine)
            for e in entries:
                if e is a or e is b:
                    continue
                path = _dijkstra(drivable, clearance_free, e["px"], rail, grid.res)
                if not path or len(path) * grid.res < STUB_M:
                    continue
                # 곁가지를 등뼈 위 가장 가까운 선분에 붙인다(그 자리에 노드를 넣는다).
                jxy = grid.to_world(*path[-1])
                best_seg = min(zip(spine_ids, spine_ids[1:]),
                               key=lambda ab: _seg_point_dist(sb.nodes[ab[0]], sb.nodes[ab[1]], jxy))
                j = sb.node(_project(sb.nodes[best_seg[0]], sb.nodes[best_seg[1]], jxy))
                if j not in best_seg:
                    sb.edges.discard((min(best_seg), max(best_seg)))
                    sb.edges.add((min(best_seg[0], j), max(best_seg[0], j)))
                    sb.edges.add((min(j, best_seg[1]), max(j, best_seg[1])))
                spur_ids = sb.polyline(path[::-1])
                if spur_ids and spur_ids[0] != j:
                    sb.edges.add((min(j, spur_ids[0]), max(j, spur_ids[0])))
        if not sb.edges:
            continue
        sketch = sketch_json(sb.nodes, sb.edges)
        try:
            result = process_sketch(grid, sketch, places)
        except RouteError:
            continue
        key = (len(result["errors"]), result["summary"]["length_m"])
        if best is None or key < best[0]:
            best = (key, kind, sketch, result)
    if best is None:
        raise RouteError("build_failed", "장소 사이에 로봇이 다닐 길을 찾지 못했습니다.")
    _, kind, sketch, result = best
    return {"shape": kind, "sketch": sketch, "result": result}


def _project(a, b, p):
    dx, dy = b[0] - a[0], b[1] - a[1]
    L2 = dx * dx + dy * dy
    if L2 == 0:
        return a
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L2))
    return (a[0] + t * dx, a[1] + t * dy)


def _seg_point_dist(a, b, p) -> float:
    return math.dist(_project(a, b, p), p)


def issues_payload(items) -> list[dict[str, Any]]:
    """앱에 보내는 모양(번호는 앱이 매긴다)."""
    out = []
    for it in items:
        d = {"code": it["code"], "x": round(float(it["x"]), 3), "y": round(float(it["y"]), 3),
             "message": it["message"]}
        if "value" in it:
            d["value"] = it["value"]
        if "name" in it:
            d["name"] = it["name"]
        out.append(d)
    return out
