#!/usr/bin/env python3
"""map_http_server.py 시험입니다. ROS도 로봇도 필요 없습니다.

pytest 가 있으면:  python -m pytest VICA_Supervisor/ros2/test_map_http_server.py
없으면:            python VICA_Supervisor/ros2/test_map_http_server.py

이 시험이 지키는 것은 **헤더 한 줄**입니다. 그 줄이 빠지면 브라우저로 띄운
앱에서 지도 그림만 안 보이는데, ROS 연결도 되고 목록도 떠서 고장으로 보이지
않습니다. 실제로 그 상태가 몇 주 동안 남아 있었습니다. 사람이 알아채기 어려운
것은 코드가 지키게 합니다.
"""
from __future__ import annotations

import sys
import threading
import urllib.error
import urllib.request
from functools import partial
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import map_http_server as mhs  # noqa: E402


def serve(root: Path):
    """빈 포트에 서버를 띄우고 (주소, 종료함수) 를 돌려줍니다."""
    handler = partial(mhs.MapRequestHandler, directory=str(root))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    host, port = server.server_address[:2]

    def stop() -> None:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    return f"http://{host}:{port}", stop


def make_maps(root: Path) -> Path:
    (root / "maps").mkdir(parents=True, exist_ok=True)
    (root / "maps" / "vica_map_test.png").write_bytes(b"\x89PNG\r\n\x1a\n" + b"0" * 32)
    (root / "secret.txt").write_text("작업공간의 다른 파일", encoding="utf-8")
    return root


def test_지도_이미지에_출처_허락_헤더가_붙는다(tmp_path: Path) -> None:
    base, stop = serve(make_maps(tmp_path))
    try:
        request = urllib.request.Request(
            f"{base}/maps/vica_map_test.png",
            headers={"Origin": "http://localhost:5000"},
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            assert response.status == 200
            assert response.headers.get("Access-Control-Allow-Origin") == "*", (
                "이 헤더가 없으면 브라우저로 띄운 앱에서 지도만 안 보입니다."
            )
    finally:
        stop()


def test_이미지_내용이_그대로_나간다(tmp_path: Path) -> None:
    root = make_maps(tmp_path)
    base, stop = serve(root)
    try:
        with urllib.request.urlopen(f"{base}/maps/vica_map_test.png", timeout=5) as res:
            served = res.read()
        assert served == (root / "maps" / "vica_map_test.png").read_bytes()
    finally:
        stop()


def test_maps_밖은_내보내지_않는다(tmp_path: Path) -> None:
    base, stop = serve(make_maps(tmp_path))
    try:
        for path in ("/secret.txt", "/", "/maps"):
            try:
                urllib.request.urlopen(f"{base}{path}", timeout=5)
            except urllib.error.HTTPError as error:
                assert error.code == 404, f"{path} 가 404 가 아닙니다"
            else:
                raise AssertionError(f"{path} 가 열렸습니다")
    finally:
        stop()


def test_질의문자열이_붙어도_지도는_나간다(tmp_path: Path) -> None:
    """브라우저가 캐시를 피하려고 ?v=1 을 붙여도 경로 판정이 흔들리면 안 됩니다."""
    base, stop = serve(make_maps(tmp_path))
    try:
        with urllib.request.urlopen(
            f"{base}/maps/vica_map_test.png?v=1", timeout=5
        ) as response:
            assert response.status == 200
    finally:
        stop()


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
        workdir = Path(tempfile.mkdtemp(prefix="map_http_test_"))
        try:
            test(workdir)
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
