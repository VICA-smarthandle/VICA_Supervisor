#!/usr/bin/env python3
"""앱에 지도 이미지를 넘겨주는 작은 HTTP 서버입니다."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PUBLIC_PREFIX = "/maps/"


class MapRequestHandler(SimpleHTTPRequestHandler):
    """지도 파일만, 출처 허락 헤더를 붙여 내보냅니다."""

    def end_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def send_head(self):
        path = self.path.split("?", 1)[0].split("#", 1)[0]
        if not path.startswith(PUBLIC_PREFIX):
            self.send_error(404, "Not Found")
            return None
        return super().send_head()


def main() -> None:
    parser = argparse.ArgumentParser(description="VICA 지도 이미지 HTTP 서버")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument(
        "--directory",
        default=str(Path(__file__).resolve().parents[2] / "vica_ros2_ws"),
        help="이 폴더를 루트로 삼습니다. 그 아래 maps/ 만 내보냅니다.",
    )
    args = parser.parse_args()

    handler = partial(MapRequestHandler, directory=args.directory)
    with ThreadingHTTPServer((args.bind, args.port), handler) as server:
        print(
            f"지도 HTTP 서버: http://{args.bind}:{args.port}{PUBLIC_PREFIX} "
            f"(루트 {args.directory})",
            flush=True,
        )
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
