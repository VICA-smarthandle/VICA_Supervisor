#!/usr/bin/env python3
"""레일 도장 — 한 지도의 레일을 '홈 기준' 모양으로 떠 두고, 다른 지도의 홈 자리에 그대로 찍습니다.

왜(2026-10-10 사용자 요청): 시연장에서는 시간을 아껴야 한다. 시연테스트 지도
(map_1002_150946)의 ∩ 레일을, 3.8 × 6.5 m 빈 곳이 있는 어느 지도에든 홈 기준으로 바로
넣는다. 장소는 넣지 않는다(사용자 결정: 레일만, 장소는 현장에서 앱으로 찍는다).

원리: 레일은 스케치(꼭짓점 몇 개 + 선)만 있으면 된다. 코너 둥글리기·1 m 나누기·벽 검사는
route_graph_build.process_sketch 가 한다(앱 레일 저장과 같은 코드). 꼭짓점을 홈 좌표계
(앞 = 홈이 보는 방향, 왼쪽 = 홈의 왼쪽, m)로 바꿔 두면, 새 지도에서 홈만 알면 같은 레일이
나온다. 노드 번호도 그대로 둔다 — 코너는 번호 순서로 둥글려져 먼저 찍힌 코너가 R 1.0 을
가져가기 때문이다.

쓰는 법(젯슨, ROS 환경을 불러온 셸 — `humble` 별칭 또는 install/setup.bash):
    cd ~/VICA-smarthandle/VICA_Supervisor/ros2
    python3 rail_template.py apply --map <지도>            # 미리보기만. 파일을 쓰지 않는다
    python3 rail_template.py apply --map <지도> --save     # 레일 노드(/vica/route/save)로 저장·적용
    python3 rail_template.py apply --map <지도> --offline  # 레일 노드 없이 파일만 쓴다
    python3 rail_template.py extract --map map_1002_150946 --overwrite  # 연습장 레일을 바꾼 뒤 도장 다시 뜨기

크기 버전(2026-10-11 사용자 요청: 시연장 빈 곳이 더 넓으면 공간을 최대로 쓴다):
    python3 rail_template.py list                          # 있는 버전·구역 크기·레일 크기·코너
    python3 rail_template.py make --zone 4x7               # demo_cap 을 4 × 7 m 구역에 맞게 늘린 버전
    python3 rail_template.py apply --map <지도> --zone 4x7 --save   # "4×7 로 바꿔줘"
늘릴 때 홈 쪽(왼쪽 레일·위 변)은 그대로 두고 반대쪽 레일과 아래 끝만 민다 — 어느 버전이든 홈
자리가 같아서 바꿔 끼워도 홈에서 출발하는 모양이 같다.

**Nav2 보다 먼저 넣는다.** Nav2 launch 는 기동 때 레일 파일이 있어야 route_server 와 레일
트리를 띄운다(nav2_map_test.launch.py route_actions). 레일 없이 이미 띄웠으면 넣은 뒤 Nav2 를
다시 띄워야 한다 — 저장 결과가 no_route_server 면 그 뜻이다.

홈은 <destinations_root>/<지도>/home.yaml 에서 읽는다(앱에서 홈을 먼저 찍는다). 홈 방향은
뜰 때·찍을 때 모두 90° 배수에서 10° 안이면 그 배수로 맞춘다 — 3° 만 틀어져도 4.9 m 끝에서
26 cm 벗어난다. 정렬해서 저장한 지도라면 벽이 축과 나란하다.

종료 코드: 0 저장·적용 끝(또는 미리보기 통과) · 3 저장됐지만 아직 적용 안 됨 ·
           4 검사에서 멈춤 · 1 실패 · 2 명령 사용법 오류(argparse).
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import numpy as np
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))

import keepout_mask as km  # noqa: E402
import route_graph_build as rb  # noqa: E402

KST = timezone(timedelta(hours=9))
HERE = Path(__file__).resolve().parent
TEMPLATE_DIR = HERE / "rail_templates"
DEFAULT_TEMPLATE = "demo_cap"
DEFAULT_MAPS_ROOT = HERE.parents[1] / "vica_ros2_ws" / "maps"
DEFAULT_DEST_ROOT = Path.home() / "vica_data" / "destinations"

# 시연 구역: 레일 둘레에 옆 0.78 m·위아래 0.80 m(시연장 권장 배치, 2026-10-10 계산).
# 레일 2.24 × 4.90 m 이면 구역이 3.8 × 6.5 m 가 된다.
ZONE_SIDE_M = 0.78
ZONE_END_M = 0.80
# 홈에서 제자리 회전할 때 몸 모서리가 그리는 원(외접반경 0.570 + 여유). route_graph_build 의
# 벽 기준 0.70 에서 레일 옆 오차 0.08 을 뺀 값이다.
ROTATE_CLEAR_M = 0.62
YAW_SNAP_TOL_DEG = 10.0
# trinary 지도: 점유 0, 미탐색 205, 빈 곳 254.
FREE_MIN = 250
SERVICE_WAIT_SEC = 5.0

# 2 는 argparse 사용법 오류가 쓰므로 '검사에서 멈춤'은 4.
EXIT_OK, EXIT_FAIL, EXIT_NOT_APPLIED, EXIT_STOPPED = 0, 1, 3, 4

# 저장은 됐지만 적용되지 않은 이유(route_graph_node.handle_save 의 reason).
NOT_APPLIED_HINT = {
    "not_current_map": "지금 주행 지도가 아닙니다. 이 지도로 Nav2 를 띄우면 새 레일을 읽습니다.",
    "no_route_server": "route_server 가 없습니다. 레일 파일 없이 Nav2 를 띄우면 route_server 와 레일 트리를 "
                       "아예 안 띄웁니다 — Nav2 를 다시 띄워야 레일을 씁니다.",
    "busy_driving": "주행 중이라 주행이 끝나는 순간 적용합니다.",
}


class TemplateError(Exception):
    """사람에게 그대로 보여 줄 실패."""


# ---------------------------------------------------------------------------
# 홈 좌표계
# ---------------------------------------------------------------------------

def to_home_frame(x: float, y: float, home: tuple[float, float, float]) -> tuple[float, float]:
    """지도 (x, y) → 홈 기준 (앞, 왼쪽). home = (x, y, yaw_deg)."""
    hx, hy, yaw = home
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    dx, dy = x - hx, y - hy
    return dx * c + dy * s, -dx * s + dy * c


def from_home_frame(forward: float, left: float, home: tuple[float, float, float]) -> tuple[float, float]:
    """홈 기준 (앞, 왼쪽) → 지도 (x, y)."""
    hx, hy, yaw = home
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    return hx + forward * c - left * s, hy + forward * s + left * c


def snap_yaw(yaw_deg: float, tol_deg: float = YAW_SNAP_TOL_DEG) -> tuple[float, bool]:
    """90° 배수에서 tol 안이면 그 배수로. (맞춘 값, 맞췄는가)."""
    nearest = round(yaw_deg / 90.0) * 90.0
    if abs(off_axis_deg(yaw_deg)) <= tol_deg:
        return nearest % 360.0, abs(off_axis_deg(yaw_deg)) > 1e-9
    return yaw_deg % 360.0, False


def off_axis_deg(yaw_deg: float) -> float:
    """가장 가까운 90° 배수에서 벗어난 각(−45~45)."""
    return (yaw_deg - round(yaw_deg / 90.0) * 90.0 + 180.0) % 360.0 - 180.0


def load_home(dest_root: Path, map_id: str) -> tuple[float, float, float]:
    path = dest_root / map_id / "home.yaml"
    if not path.is_file():
        raise TemplateError(f"홈이 없습니다({path}). 앱에서 이 지도의 홈을 먼저 찍으세요.")
    try:
        pose = (yaml.safe_load(path.read_text(encoding="utf-8")) or {})["pose"]
        return float(pose["x"]), float(pose["y"]), float(pose["yaw"])
    except (OSError, yaml.YAMLError, KeyError, TypeError, ValueError) as error:
        raise TemplateError(f"홈 파일을 읽지 못했습니다({path}): {error}") from error


def parse_home_arg(text: str) -> tuple[float, float, float]:
    try:
        x, y, yaw = (float(v) for v in text.split(","))
    except ValueError as error:
        raise TemplateError(f"--home 은 'x,y,yaw도' 입니다: {text}") from error
    return x, y, yaw


def resolve_home(raw: tuple[float, float, float], snap: bool) -> tuple[tuple[float, float, float], bool]:
    """(쓸 홈, 방향을 맞췄는가)."""
    if not snap:
        return raw, False
    yaw, snapped = snap_yaw(raw[2])
    return (raw[0], raw[1], yaw), snapped


# ---------------------------------------------------------------------------
# 도장 뜨기
# ---------------------------------------------------------------------------

def make_template(sketch: dict[str, Any], home: tuple[float, float, float], *,
                  name: str, source: dict[str, Any]) -> dict[str, Any]:
    """지도 좌표 스케치 → 홈 기준 도장."""
    nodes, edges = rb.parse_sketch(sketch)
    out_nodes = []
    for nid in sorted(nodes):
        f, l = to_home_frame(*nodes[nid], home)
        out_nodes.append({"id": nid, "forward": round(f, 4) + 0.0, "left": round(l, 4) + 0.0})
    fs = [n["forward"] for n in out_nodes]
    ls = [n["left"] for n in out_nodes]
    return {
        "name": name,
        "anchor": "home",
        "frame": "forward = 홈이 보는 방향(m), left = 홈의 왼쪽(m)",
        "nodes": out_nodes,
        "edges": [list(e) for e in edges],
        "zone": {"forward_min": round(min(fs) - ZONE_END_M, 4), "forward_max": round(max(fs) + ZONE_END_M, 4),
                 "left_min": round(min(ls) - ZONE_SIDE_M, 4), "left_max": round(max(ls) + ZONE_SIDE_M, 4)},
        "source": source,
    }


def extract(maps_root: Path, dest_root: Path, map_id: str, name: str, snap: bool = True) -> dict[str, Any]:
    sketch = rb.load_sketch(maps_root, map_id)
    if not sketch:
        raise TemplateError(f"{map_id} 에 레일 스케치가 없습니다.")
    raw_home = load_home(dest_root, map_id)
    # 찍을 때와 같은 규칙으로 맞춘다. 원본 홈이 1.5° 틀어진 채로 뜨면 도장 자체가 기운다(검토 10-10).
    home, _ = resolve_home(raw_home, snap)
    result = rb.process_sketch(rb.MapGrid(maps_root, map_id), sketch)
    edit = rb.route_paths(maps_root, map_id)["edit"]
    updated = ""
    if edit.is_file():
        try:
            updated = json.loads(edit.read_text(encoding="utf-8")).get("updated_at", "")
        except (OSError, json.JSONDecodeError):
            updated = ""
    source = {"map_id": map_id,
              "home": {"x": round(home[0], 4), "y": round(home[1], 4), "yaw_deg": home[2],
                       "yaw_deg_file": raw_home[2]},
              "sketch_updated_at": updated,
              "extracted_at": datetime.now(KST).isoformat(timespec="seconds"),
              "source_map_summary": {**result["summary"], "corner_radii_m": corner_radii(result["graph"])}}
    tpl = make_template(sketch, home, name=name, source=source)
    # 비교 기준은 늘인 도장(make)과 같이 '빈 지도에 찍은 모양'이다. 원본 지도에서 벽 때문에 코너가
    # 작아졌으면 둘이 달라 cmd_extract 가 알린다(검토 10-11).
    tpl["source"]["summary"] = free_space_summary(tpl)
    return tpl


def template_path(name: str) -> Path:
    if "/" in name or name.startswith("."):
        raise TemplateError(f"도장 이름이 올바르지 않습니다: {name}")
    return TEMPLATE_DIR / f"{name}.json"


def load_template(name: str) -> dict[str, Any]:
    path = template_path(name)
    if not path.is_file():
        raise TemplateError(f"도장이 없습니다: {path}")
    try:
        tpl = json.loads(path.read_text(encoding="utf-8"))
        # 손으로 고친 도장도 여기서 걸러 traceback 대신 한 줄로 알린다(재검토 10-10).
        for n in tpl["nodes"]:
            int(n["id"]), float(n["forward"]), float(n["left"])
        for a, b in tpl["edges"]:
            int(a), int(b)
        for k in ("forward_min", "forward_max", "left_min", "left_max"):
            float(tpl["zone"][k])
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        raise TemplateError(f"도장 파일을 읽지 못했습니다({path}): {error!r}") from error
    tpl.setdefault("name", name)
    tpl.setdefault("source", {})
    return tpl


# ---------------------------------------------------------------------------
# 크기 버전
# ---------------------------------------------------------------------------

# 늘인 레일이 이보다 짧으면 만들지 않는다(코너 둘이 들어갈 자리도 없다).
MIN_RAIL_M = 1.0


def zone_size(tpl: dict[str, Any]) -> tuple[float, float]:
    """(폭, 길이) m. 폭 = 홈 왼쪽 방향, 길이 = 홈이 보는 방향."""
    z = tpl["zone"]
    return round(z["left_max"] - z["left_min"], 2), round(z["forward_max"] - z["forward_min"], 2)


def rail_size(tpl: dict[str, Any]) -> tuple[float, float]:
    ls = [float(n["left"]) for n in tpl["nodes"]]
    fs = [float(n["forward"]) for n in tpl["nodes"]]
    return round(max(ls) - min(ls), 2), round(max(fs) - min(fs), 2)


def parse_zone(text: str) -> tuple[float, float]:
    """'4x7'·'4.0x7.0'·'4*7'·'4×7' → (4.0, 7.0)."""
    t = text.strip().lower().replace("×", "x").replace("*", "x")
    try:
        w, l = (float(v) for v in t.split("x"))
    except ValueError as error:
        raise TemplateError(f"구역 크기는 '폭x길이'(예: 4x7, 3.8x6.5) 입니다: {text}") from error
    if w <= 0 or l <= 0:
        raise TemplateError(f"구역 크기는 0 보다 커야 합니다: {text}")
    return w, l


def list_templates() -> list[tuple[str, dict[str, Any] | None, str]]:
    """(이름, 도장 또는 None, 못 읽은 이유)."""
    out = []
    for path in sorted(TEMPLATE_DIR.glob("*.json")):
        try:
            out.append((path.stem, load_template(path.stem), ""))
        except TemplateError as error:
            out.append((path.stem, None, str(error)))
    return out


def find_by_zone(text: str) -> str:
    """구역 크기로 도장 이름을 고른다. 없거나 여럿이면 실패."""
    w, l = parse_zone(text)
    want = (round(w, 2), round(l, 2))
    found = [(name, tpl) for name, tpl, _ in list_templates() if tpl]
    hits = [name for name, tpl in found if zone_size(tpl) == want]
    if len(hits) == 1:
        return hits[0]
    have = ", ".join(f"{zone_size(t)[0]}x{zone_size(t)[1]}({n})" for n, t in found) or "없음"
    if not hits:
        raise TemplateError(f"{want[0]} × {want[1]} m 도장이 없습니다. 있는 것: {have}. "
                            f"만들려면: python3 rail_template.py make --zone {want[0]}x{want[1]}")
    raise TemplateError(f"{want[0]} × {want[1]} m 도장이 여럿입니다({', '.join(hits)}). --template 으로 고르세요.")


def stretch_template(base: dict[str, Any], width: float, length: float, *,
                     name: str, base_name: str) -> dict[str, Any]:
    """구역 폭·길이에 맞게 늘인다. 홈 쪽 레일·변은 그대로, 홈에서 먼 쪽 레일과 먼 끝만 민다.

    꼭짓점이 레일 네 모서리에 있는 ∩ 모양용이다. 가운데 줄 근처(0.05 m 안)에 꼭짓점이 있으면
    어느 쪽으로 밀지 정할 수 없어 멈춘다. 번호·선은 그대로 둔다(코너 R 순서 유지).
    """
    z = base["zone"]
    dw = width - (z["left_max"] - z["left_min"])
    dl = length - (z["forward_max"] - z["forward_min"])
    fs = [float(n["forward"]) for n in base["nodes"]]
    ls = [float(n["left"]) for n in base["nodes"]]
    f_mid, l_mid = (min(fs) + max(fs)) / 2.0, (min(ls) + max(ls)) / 2.0
    if any(abs(f - f_mid) < 0.05 or abs(l - l_mid) < 0.05 for f, l in zip(fs, ls)):
        raise TemplateError("가운데 줄에 꼭짓점이 있어 늘일 방향을 정할 수 없습니다(∩ 네 모서리 모양만 늘입니다).")
    rail_w, rail_l = max(ls) - min(ls) + dw, max(fs) - min(fs) + dl
    if rail_w < MIN_RAIL_M or rail_l < MIN_RAIL_M:
        raise TemplateError(f"레일이 {rail_w:.2f} × {rail_l:.2f} m 가 되어 너무 작습니다"
                            f"(구역은 레일보다 옆 {ZONE_SIDE_M * 2:.2f} m·길이 {ZONE_END_M * 2:.2f} m 커야 함).")
    # 축마다 홈(0)에서 먼 쪽을 민다. 레일이 홈 오른쪽(left 음수)·뒤(forward 음수)에 있으면 작은 쪽이
    # 먼 쪽이다 — '값이 큰 쪽'을 밀면 홈 쪽 변이 홈으로 다가온다(검토 10-11).
    f_far_max = abs(max(fs)) >= abs(min(fs))
    l_far_max = abs(max(ls)) >= abs(min(ls))

    def push(v: float, mid: float, far_max: bool, d: float) -> float:
        if far_max:
            return v + d if v > mid else v
        return v - d if v < mid else v

    nodes = [{"id": int(n["id"]),
              "forward": round(push(float(n["forward"]), f_mid, f_far_max, dl), 4) + 0.0,
              "left": round(push(float(n["left"]), l_mid, l_far_max, dw), 4) + 0.0}
             for n in base["nodes"]]
    zone = dict(z)
    if f_far_max:
        zone["forward_max"] = round(z["forward_max"] + dl, 4)
    else:
        zone["forward_min"] = round(z["forward_min"] - dl, 4)
    if l_far_max:
        zone["left_max"] = round(z["left_max"] + dw, 4)
    else:
        zone["left_min"] = round(z["left_min"] - dw, 4)
    tpl = {"name": name, "anchor": base.get("anchor", "home"), "frame": base.get("frame", ""),
           "nodes": nodes, "edges": [list(e) for e in base["edges"]], "zone": zone}
    tpl["source"] = {"made_from": base_name, "zone_m": [round(width, 2), round(length, 2)],
                     "base_source": base.get("source", {}),
                     "made_at": datetime.now(KST).isoformat(timespec="seconds"),
                     "summary": free_space_summary(tpl)}
    return tpl


def free_space_summary(tpl: dict[str, Any], margin_m: float = 3.0) -> dict[str, Any]:
    """벽이 멀리 있는 빈 지도에 찍었을 때의 레일 요약. 대상 지도 결과와 견줄 기준이 된다."""
    import tempfile

    from PIL import Image

    z = tpl["zone"]
    res = 0.05
    # 홈 (0, 0, 0°): 앞 = +x, 왼쪽 = +y.
    x0, y0 = z["forward_min"] - margin_m, z["left_min"] - margin_m
    w = int(math.ceil((z["forward_max"] + margin_m - x0) / res))
    h = int(math.ceil((z["left_max"] + margin_m - y0) / res))
    img = np.full((h, w), 254, dtype=np.uint8)
    img[0, :] = img[-1, :] = 0
    img[:, 0] = img[:, -1] = 0
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        Image.fromarray(img).save(root / "free_space.pgm")
        (root / "free_space.yaml").write_text(
            f"image: free_space.pgm\nresolution: {res}\norigin: [{x0}, {y0}, 0.0]\n"
            "negate: 0\noccupied_thresh: 0.65\nfree_thresh: 0.196\nmode: trinary\n", encoding="utf-8")
        result = rb.process_sketch(rb.MapGrid(root, "free_space"), place_sketch(tpl, (0.0, 0.0, 0.0)))
    summary = dict(result["summary"])
    summary["corner_radii_m"] = corner_radii(result["graph"])
    return summary


def corner_radii(graph: rb.Graph) -> list[float]:
    """한 줄짜리 레일에서 코너 호의 반지름(번호가 작은 끝부터 차례로).

    호 위 점(route_graph_build 가 arc_nodes 에 넣는 접점·안쪽 점) 세 개가 같은 간격으로 이어진 곳만
    원을 맞춘다. 같은 호는 중심이 같아 하나로 세고, 두 호를 잇는 짧은 직선(간격이 다름)은 건너뛴다 —
    가까운 두 코너가 하나로 합쳐지지 않게(검토 10-11). 갈림길·고리(끝이 둘이 아님)는 빈 목록이다.
    """
    adj = graph.adj
    ends = sorted(n for n, nb in adj.items() if len(nb) == 1)
    if len(ends) != 2 or any(len(nb) > 2 for nb in adj.values()):
        return []
    order, prev, cur = [ends[0]], None, ends[0]
    while True:
        nxt = [n for n in adj[cur] if n != prev]
        if not nxt:
            break
        prev, cur = cur, nxt[0]
        order.append(cur)

    def circle(a, b, c):
        d = 2.0 * (a[0] * (b[1] - c[1]) + b[0] * (c[1] - a[1]) + c[0] * (a[1] - b[1]))
        if abs(d) < 1e-12:
            return None
        sa, sb, sc = a[0] ** 2 + a[1] ** 2, b[0] ** 2 + b[1] ** 2, c[0] ** 2 + c[1] ** 2
        ux = (sa * (b[1] - c[1]) + sb * (c[1] - a[1]) + sc * (a[1] - b[1])) / d
        uy = (sa * (c[0] - b[0]) + sb * (a[0] - c[0]) + sc * (b[0] - a[0])) / d
        return (ux, uy), math.dist((ux, uy), a)

    radii, last_center = [], None
    for i in range(1, len(order) - 1):
        ids = order[i - 1:i + 2]
        pts = [graph.nodes[k] for k in ids]
        if not all(k in graph.arc_nodes for k in ids) or abs(math.dist(*pts[:2]) - math.dist(*pts[1:])) > 1e-3:
            last_center = None
            continue
        fit = circle(*pts)
        if fit is None:
            last_center = None
            continue
        center, r = fit
        if last_center is None or math.dist(center, last_center) > 0.01:
            radii.append(round(r, 2))
        last_center = center
    return radii


# ---------------------------------------------------------------------------
# 찍기
# ---------------------------------------------------------------------------

def place_sketch(template: dict[str, Any], home: tuple[float, float, float],
                 mirror: bool = False) -> dict[str, Any]:
    """도장 → 지도 좌표 스케치(앱 스케치 형식). mirror 면 왼쪽·오른쪽을 뒤집는다."""
    sign = -1.0 if mirror else 1.0
    nodes = []
    for n in template["nodes"]:
        x, y = from_home_frame(float(n["forward"]), sign * float(n["left"]), home)
        nodes.append({"id": int(n["id"]), "x": round(x, 4) + 0.0, "y": round(y, 4) + 0.0})
    return {"nodes": nodes, "edges": [list(e) for e in template["edges"]]}


def _in_keepout(x: float, y: float, zones) -> bool:
    return any(k["x_min"] <= x <= k["x_max"] and k["y_min"] <= y <= k["y_max"] for k in zones)


def check_zone(grid: rb.MapGrid, template: dict[str, Any], home, mirror: bool = False,
               keepout_zones=()) -> dict[str, Any]:
    """시연 구역 안의 벽·미탐색·금지구역 칸과, 홈 제자리 회전 여유를 본다."""
    z = template["zone"]
    sign = -1.0 if mirror else 1.0
    step = grid.res
    fs = np.arange(z["forward_min"], z["forward_max"] + 1e-9, step)
    ls = np.arange(z["left_min"], z["left_max"] + 1e-9, step)
    occupied, unknown, outside, keepout = [], 0, 0, 0
    for f in fs:
        for l in ls:
            x, y = from_home_frame(float(f), sign * float(l), home)
            r, c = grid.to_px(x, y)
            if not grid.inside(r, c):
                outside += 1
                continue
            if grid.occupied[r, c]:
                occupied.append((x, y))
            elif grid.img[r, c] < FREE_MIN:
                unknown += 1
            if _in_keepout(x, y, keepout_zones):
                keepout += 1
    home_clear = grid.clearance(home[0], home[1])
    return {"cells": len(fs) * len(ls), "occupied": len(occupied), "unknown": unknown, "outside": outside,
            "keepout": keepout, "occupied_spots": _clusters(occupied),
            "size_m": (round(z["left_max"] - z["left_min"], 2), round(z["forward_max"] - z["forward_min"], 2)),
            "home_clearance": round(home_clear, 2),
            "home_ok": home_clear >= ROTATE_CLEAR_M}


def rail_keepout_points(graph: rb.Graph, keepout_zones) -> list[tuple[float, float]]:
    """다듬은 레일 선 위에서 금지구역 안에 든 점. 금지구역은 global costmap 에서 벽이라
    그 위 레일은 레일 앞 검사가 늘 막힘으로 본다."""
    if not keepout_zones:
        return []
    hits = []
    for a, b in graph.edges():
        for p in rb._samples(graph.nodes[a], graph.nodes[b]):
            if _in_keepout(p[0], p[1], keepout_zones):
                hits.append(p)
    return hits


def rail_min_clearance(graph: rb.Graph, grid: rb.MapGrid) -> tuple[float, tuple[float, float]]:
    """다듬은 레일 선 위에서 벽까지 가장 가까운 거리와 그 자리. 레일 규칙은 0.70 m 이상."""
    best, where = math.inf, (0.0, 0.0)
    for a, b in graph.edges():
        for p in rb._samples(graph.nodes[a], graph.nodes[b]):
            c = grid.clearance(*p)
            if c < best:
                best, where = c, p
    return best, where


def _clusters(points, merge_m: float = 0.5, limit: int = 8) -> list[tuple[float, float, int]]:
    """막힌 칸을 0.5 m 안끼리 묶어 (x, y, 칸 수) 몇 개만."""
    groups: list[list[float]] = []
    for x, y in points:
        for g in groups:
            if math.dist((g[0] / g[2], g[1] / g[2]), (x, y)) <= merge_m:
                g[0] += x
                g[1] += y
                g[2] += 1
                break
        else:
            groups.append([x, y, 1])
    groups.sort(key=lambda g: -g[2])
    return [(round(g[0] / g[2], 2), round(g[1] / g[2], 2), int(g[2])) for g in groups[:limit]]


def zone_blocks(zone: dict[str, Any], ignore_zone: bool = False) -> list[str]:
    """--force 로 넘을 수 있는 멈춤 이유. 미탐색 칸·구역 안 금지구역 겹침은 알림만.

    ignore_zone 은 시연 구역(레일 둘레 0.78/0.80 m) 검사만 뺀다 — 연습장처럼 구역 가장자리가
    벽에 몇 cm 걸려도 레일 자체는 규칙(0.70 m)을 지킬 때 쓴다(2026-10-11). 홈 둘레는 그대로 본다.
    """
    reasons = []
    if zone["occupied"] and not ignore_zone:
        reasons.append(f"시연 구역 안에 벽·장애물 칸 {zone['occupied']}개")
    if zone["outside"] and not ignore_zone:
        reasons.append(f"시연 구역 일부({zone['outside']}칸)가 지도 밖")
    if not zone["home_ok"]:
        reasons.append(f"홈 둘레 여유 {zone['home_clearance']:.2f} m < 제자리 회전 {ROTATE_CLEAR_M:.2f} m")
    return reasons


# ---------------------------------------------------------------------------
# 저장
# ---------------------------------------------------------------------------

def save_via_service(map_id: str, sketch: dict[str, Any], wait_sec: float = SERVICE_WAIT_SEC) -> dict[str, Any]:
    """route_graph_node(/vica/route/get → /vica/route/save)로 저장·적용한다.

    못 하면 원인을 TemplateError 로 알린다. 몰래 파일을 직접 쓰지 않는다 — 노드가 떠 있는데
    파일만 바꾸면 적용도 앱 알림도 없이 끝난다(검토 10-10). 파일만 쓰려면 --offline.
    """
    try:
        import rclpy
        from vica_interfaces.srv import GetRoute, SaveRoute
    except ImportError as error:
        raise TemplateError("ROS 환경을 불러오지 않은 셸입니다(humble 별칭 또는 "
                            "source ~/VICA-smarthandle/vica_ros2_ws/install/setup.bash). "
                            f"레일 노드 없이 파일만 쓰려면 --offline. ({error})") from error
    rclpy.init()
    try:
        node = rclpy.create_node("vica_rail_template")
        try:
            save = node.create_client(SaveRoute, "/vica/route/save")
            get = node.create_client(GetRoute, "/vica/route/get")
            if not save.wait_for_service(timeout_sec=wait_sec) or not get.wait_for_service(timeout_sec=1.0):
                raise TemplateError(f"레일 노드(/vica/route/save·get)가 {wait_sec:.0f}초 안에 안 보입니다. "
                                    "앱 쪽 supervisor 가 떠 있는지 보세요. 노드 없이 파일만 쓰려면 --offline.")
            req = GetRoute.Request()
            req.map_id = map_id
            future = get.call_async(req)
            rclpy.spin_until_future_complete(node, future, timeout_sec=10.0)
            if not future.done() or future.result() is None:
                raise TemplateError("레일 조회(/vica/route/get)가 10초 안에 답하지 않아 저장하지 않았습니다.")
            # 레일이 아직 없는 지도는 found=False·version "" 이고, 노드도 판 비교를 건너뛴다.
            version = future.result().version
            req = SaveRoute.Request()
            req.map_id = map_id
            req.sketch_json = json.dumps(sketch, ensure_ascii=False)
            req.preview_only = False
            req.apply_now = True
            req.base_version = version
            req.overwrite = False
            future = save.call_async(req)
            rclpy.spin_until_future_complete(node, future, timeout_sec=20.0)
            if not future.done() or future.result() is None:
                raise TemplateError("레일 저장(/vica/route/save)이 20초 안에 답하지 않았습니다. "
                                    "앱 레일 칸에서 저장됐는지 보세요.")
            r = future.result()
            return {"accepted": r.accepted, "applied": r.applied, "reason": r.reason, "message": r.message}
        finally:
            node.destroy_node()
    finally:
        rclpy.shutdown()


def save_offline(maps_root: Path, map_id: str, result: dict[str, Any], sketch: dict[str, Any]) -> None:
    """레일 노드 없이 파일만. 노드와 같은 백업 이름·같은 한꺼번에 쓰기."""
    graph = rb.route_paths(maps_root, map_id)["graph"]
    try:
        if graph.is_file():
            folder = graph.parent / ".route_backup"
            folder.mkdir(exist_ok=True)
            stamp = datetime.now(KST).strftime("%Y%m%d_%H%M%S")
            shutil.copy2(graph, folder / f"{graph.stem}_{stamp}{graph.suffix}")
        rb.save_route(maps_root, map_id, result, sketch, datetime.now(KST).isoformat(timespec="seconds"))
    except OSError as error:
        raise TemplateError(f"레일 파일을 쓰지 못했습니다: {error}") from error


# ---------------------------------------------------------------------------
# 명령
# ---------------------------------------------------------------------------

def _describe(tpl: dict[str, Any]) -> str:
    zw, zl = zone_size(tpl)
    rw, rl = rail_size(tpl)
    s = tpl.get("source", {}).get("summary", {})
    radii = s.get("corner_radii_m")
    corners = f" · 코너 R {' · '.join(f'{r:.2f}' for r in radii)}" if radii else ""
    return (f"구역 {zw} × {zl} m · 레일 {rw} × {rl} m · {s.get('length_m', '?')} m · "
            f"노드 {s.get('node_count', '?')}개{corners}")


def _write_template(name: str, tpl: dict[str, Any], overwrite: bool) -> Path:
    path = template_path(name)
    if path.exists() and not overwrite:
        old = load_template(name)
        raise TemplateError(f"도장 '{name}' 이 이미 있습니다({_describe(old)}). 바꾸려면 --overwrite. "
                            "크기 버전을 바꿔 끼운 지도에서 뜨면 그 버전 모양이 뜹니다 — 이름을 확인하세요.")
    TEMPLATE_DIR.mkdir(exist_ok=True)
    path.write_text(json.dumps(tpl, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def cmd_list(args) -> int:
    items = list_templates()
    if not items:
        print(f"도장이 없습니다: {TEMPLATE_DIR}")
        return EXIT_FAIL
    for name, tpl, error in items:
        if tpl is None:
            print(f"  {name}: 못 읽음 — {error}")
            continue
        base = tpl["source"].get("made_from")
        origin = f" ← {base} 를 늘림" if base else f" ← {tpl['source'].get('map_id', '?')} 에서 뜸"
        mark = " (기본)" if name == DEFAULT_TEMPLATE else ""
        print(f"  {name}{mark}: {_describe(tpl)}{origin}")
    return EXIT_OK


def _size_text(v: float) -> str:
    """4.0 → '4.0', 4.25 → '4.25' (소수 둘째 자리까지 — 4.2 와 4.25 가 같은 이름이 되지 않게)."""
    t = f"{round(v, 2):.2f}".rstrip("0")
    return t + "0" if t.endswith(".") else t


def cmd_make(args) -> int:
    base = load_template(args.base)
    width, length = parse_zone(args.zone)
    name = args.name or f"{args.base}_{_size_text(width)}x{_size_text(length)}"
    want = (round(width, 2), round(length, 2))
    same = [n for n, t, _ in list_templates() if t and n != name and zone_size(t) == want]
    if same:
        raise TemplateError(f"{want[0]} × {want[1]} m 도장이 이미 있습니다({', '.join(same)}). "
                            "같은 크기를 둘 두면 --zone 으로 고를 수 없습니다.")
    tpl = stretch_template(base, width, length, name=name, base_name=args.base)
    path = _write_template(name, tpl, args.overwrite)
    print(f"도장 저장: {path}")
    print(f"  {_describe(tpl)} ← {args.base}({_describe(base)})")
    for n in tpl["nodes"]:
        print(f"  꼭짓점 {n['id']}: 앞 {n['forward']:.2f} m · 왼쪽 {n['left']:.2f} m")
    return EXIT_OK


def cmd_extract(args) -> int:
    tpl = extract(args.maps_root, args.dest_root, args.map, args.name, snap=not args.no_snap)
    path = _write_template(args.name, tpl, args.overwrite)
    src = tpl["source"]
    print(f"도장 저장: {path}")
    home = src["home"]
    turned = f" (파일 {home['yaw_deg_file']:.1f}° 를 맞춤)" if home["yaw_deg_file"] != home["yaw_deg"] else ""
    print(f"  원본 {args.map} · 홈 ({home['x']}, {home['y']}) {home['yaw_deg']:.0f}°{turned} · {_describe(tpl)}")
    if src["source_map_summary"] != src["summary"]:
        print(f"  주의: 원본 지도에서는 {src['source_map_summary']} 로 나왔습니다(빈 지도 기준과 다름 — "
              "벽 때문에 코너가 작아졌을 수 있습니다).")
    for n in tpl["nodes"]:
        print(f"  꼭짓점 {n['id']}: 앞 {n['forward']:.2f} m · 왼쪽 {n['left']:.2f} m")
    return EXIT_OK


def cmd_apply(args) -> int:
    tpl = load_template(find_by_zone(args.zone) if args.zone else (args.template or DEFAULT_TEMPLATE))
    raw_home = parse_home_arg(args.home) if args.home else load_home(args.dest_root, args.map)
    home, snapped = resolve_home(raw_home, not args.no_snap)
    sketch = place_sketch(tpl, home, args.mirror)
    grid = rb.MapGrid(args.maps_root, args.map)
    result = rb.process_sketch(grid, sketch, rb.load_places(args.dest_root, args.map))
    keepout_zones = km.load_zones(args.maps_root, args.map)
    zone = check_zone(grid, tpl, home, args.mirror, keepout_zones)
    on_keepout = rail_keepout_points(result["graph"], keepout_zones)

    want = tpl["source"].get("summary", {})
    got = result["summary"]
    print(f"도장 '{tpl['name']}' → {args.map}{' (좌우 뒤집음)' if args.mirror else ''}")
    print(f"  {_describe(tpl)}")
    note = ""
    if snapped:
        note = f" → {home[2]:.0f}° 로 맞춤"
    elif not args.no_snap and abs(off_axis_deg(raw_home[2])) > YAW_SNAP_TOL_DEG:
        note = f" (90° 배수에서 {abs(off_axis_deg(raw_home[2])):.0f}° 벗어나 그대로 씀 — 벽과 나란한지 확인)"
    print(f"  홈 ({home[0]:.3f}, {home[1]:.3f}) 방향 {raw_home[2]:.1f}°{note}")
    for n in sketch["nodes"]:
        print(f"  꼭짓점 {n['id']}: ({n['x']:.3f}, {n['y']:.3f})")
    radii = corner_radii(result["graph"])
    same = (got.get("length_m") == want.get("length_m") and got.get("node_count") == want.get("node_count")
            and radii == want.get("corner_radii_m", radii))
    corners = f" · 코너 R {' · '.join(f'{r:.2f}' for r in radii)}" if radii else ""
    print(f"  레일 {got['length_m']} m · 노드 {got['node_count']}개{corners}"
          + (" — 원본과 같음" if same else
             f" — 원본({want.get('length_m')} m · {want.get('node_count')}개 · "
             f"코너 {want.get('corner_radii_m')})과 다름: 벽이 가까워 코너가 작아졌을 수 있습니다"))
    zw, zl = zone["size_m"]
    print(f"  시연 구역 {zw} × {zl} m: 벽·장애물 {zone['occupied']}칸 · 미탐색 {zone['unknown']}칸 · "
          f"금지구역 겹침 {zone['keepout']}칸 · 지도 밖 {zone['outside']}칸")
    for x, y, n in zone["occupied_spots"]:
        print(f"    막힌 곳 ({x}, {y}) {n}칸")
    clear, (cx, cy) = rail_min_clearance(result["graph"], grid)
    print(f"  레일 벽 여유 최소 {clear:.2f} m ({cx:.2f}, {cy:.2f}) — 레일 규칙 {rb.MIN_WALL_CLEAR_M:.2f} m"
          + (" 통과" if clear >= rb.MIN_WALL_CLEAR_M else " 미달"))
    print(f"  홈 둘레 여유 {zone['home_clearance']:.2f} m (제자리 회전 {ROTATE_CLEAR_M:.2f} m 필요)")
    if rb.route_paths(args.maps_root, args.map)["graph"].is_file():
        print("  이 지도의 기존 레일을 덮어씁니다(저장 때 maps/.route_backup/ 에 백업).")
    for w in result["warnings"]:
        print(f"  알림[{w['code']}] {w.get('message', '')}")
    for e in result["errors"]:
        print(f"  오류[{e['code']}] {e.get('message', '')}")

    hard = [f"레일 선이 벽을 지남 {len(result['errors'])}건"] if result["errors"] else []
    soft = zone_blocks(zone, args.ignore_zone)
    if clear < rb.MIN_WALL_CLEAR_M:
        soft.append(f"레일 벽 여유 {clear:.2f} m < {rb.MIN_WALL_CLEAR_M:.2f} m (({cx:.2f}, {cy:.2f}))")
    if on_keepout:
        x, y = on_keepout[0]
        soft.append(f"레일이 금지구역을 지남 {len(on_keepout)}점(처음 ({x:.2f}, {y:.2f}))")
    if hard or soft:
        print("멈춤: " + " · ".join(hard + soft))
        if hard:
            print("  레일 선이 벽을 지나 저장할 수 없습니다(--force 로도 안 됨). 홈을 옮기세요.")
            return EXIT_STOPPED
        if not args.force:
            zone_only = (not args.ignore_zone and not on_keepout and zone["home_ok"]
                         and clear >= rb.MIN_WALL_CLEAR_M)
            print("  저장하지 않았습니다. 홈을 옮기거나, "
                  + ("구역 가장자리만 걸린 것이면 --ignore-zone(레일 규칙은 계속 봄), "
                     if zone_only else "")
                  + "그래도 넣으려면 --force 를 붙이세요.")
            return EXIT_STOPPED
    if not (args.save or args.offline):
        print("미리보기만 했습니다. 저장하려면 --save 를 붙이세요(Nav2 보다 먼저 넣기).")
        return EXIT_OK

    if args.offline:
        save_offline(args.maps_root, args.map, result, sketch)
        print("파일만 저장했습니다(레일 노드 안 거침). 이 지도로 Nav2 를 띄우면 읽습니다 — "
              "이미 이 지도로 떠 있으면 Nav2 를 다시 띄우세요.")
        return EXIT_NOT_APPLIED
    reply = save_via_service(args.map, sketch)
    if not reply["accepted"]:
        hint = {"conflict": " 저장 직전에 레일 판이 달라졌습니다(다른 기기에서 저장했거나 레일 파일을 못 읽음). "
                            "앱 레일 칸을 확인한 뒤 다시 실행하세요."}.get(reply["reason"], "")
        print(f"저장 안 됨[{reply['reason']}]: {reply['message']}{hint}")
        return EXIT_FAIL
    if reply["applied"]:
        print(f"저장·적용했습니다: {reply['message']}")
        return EXIT_OK
    print(f"저장은 됐고 아직 적용되지 않았습니다[{reply['reason']}]: "
          + NOT_APPLIED_HINT.get(reply["reason"], reply["message"]))
    return EXIT_NOT_APPLIED


def _join_negative_home(argv: list[str]) -> list[str]:
    """'--home -1.0,2,90' 을 '--home=-1.0,2,90' 으로 — argparse 는 '-' 로 시작하는 값을 옵션으로 본다."""
    out = list(argv)
    for i in range(len(out) - 1):
        if out[i] == "--home" and out[i + 1].startswith("-"):
            out[i:i + 2] = [f"--home={out[i + 1]}"]
            break
    return out


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="레일 도장: 홈 기준으로 레일을 떠 두고 다른 지도에 찍는다.")
    p.add_argument("--maps-root", type=Path, default=DEFAULT_MAPS_ROOT)
    p.add_argument("--dest-root", type=Path, default=DEFAULT_DEST_ROOT)
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("extract", help="지도의 지금 레일을 홈 기준 도장으로 뜬다")
    e.add_argument("--map", required=True)
    e.add_argument("--name", default=DEFAULT_TEMPLATE)
    e.add_argument("--no-snap", action="store_true", help="홈 방향을 90° 배수로 맞추지 않는다")
    e.add_argument("--overwrite", action="store_true", help="같은 이름 도장이 있으면 바꾼다")
    sub.add_parser("list", help="있는 도장과 크기를 보인다")
    m = sub.add_parser("make", help="기준 도장을 다른 구역 크기에 맞게 늘인 버전을 만든다")
    m.add_argument("--zone", required=True, help="구역 '폭x길이' m (예: 4x7, 3.8x7)")
    m.add_argument("--base", default=DEFAULT_TEMPLATE)
    m.add_argument("--name", help="기본: <base>_<폭>x<길이>")
    m.add_argument("--overwrite", action="store_true", help="같은 이름 도장이 있으면 바꾼다")
    a = sub.add_parser("apply", help="도장을 지도의 홈 자리에 찍는다(기본은 미리보기)")
    a.add_argument("--map", required=True)
    pick = a.add_mutually_exclusive_group()
    pick.add_argument("--template", help=f"도장 이름(기본 {DEFAULT_TEMPLATE})")
    pick.add_argument("--zone", help="구역 크기로 고른다 '폭x길이' (예: 4x7)")
    a.add_argument("--home", help="home.yaml 대신 'x,y,yaw도' (음수도 그대로: --home -1.0,2,90)")
    a.add_argument("--mirror", action="store_true", help="레일을 홈의 오른쪽으로 뒤집는다")
    a.add_argument("--no-snap", action="store_true", help="홈 방향을 90° 배수로 맞추지 않는다")
    mode = a.add_mutually_exclusive_group()
    mode.add_argument("--save", action="store_true", help="레일 노드(/vica/route/save)로 저장·적용")
    mode.add_argument("--offline", action="store_true", help="레일 노드 없이 파일만 쓴다")
    a.add_argument("--ignore-zone", action="store_true",
                   help="시연 구역(레일 둘레 0.78/0.80 m) 검사만 뺀다. 레일 벽 여유 0.70 m·금지구역·홈 둘레는 계속 본다")
    a.add_argument("--force", action="store_true", help="구역·레일 벽 여유·홈 여유·금지구역 멈춤을 모두 넘긴다")
    args = p.parse_args(_join_negative_home(sys.argv[1:] if argv is None else argv))
    try:
        return {"extract": cmd_extract, "list": cmd_list, "make": cmd_make, "apply": cmd_apply}[args.cmd](args)
    except (TemplateError, km.KeepoutError) as error:
        print(f"실패: {error}", file=sys.stderr)
        return EXIT_FAIL


if __name__ == "__main__":
    sys.exit(main())
