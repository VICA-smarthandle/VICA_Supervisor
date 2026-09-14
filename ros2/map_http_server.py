#!/usr/bin/env python3
"""앱에 지도 이미지를 넘겨주는 작은 HTTP 서버입니다.

`python -m http.server` 를 그대로 쓰지 않는 이유는 **헤더 한 줄** 때문입니다.

    Access-Control-Allow-Origin: *

이 줄이 없으면 브라우저로 띄운 앱에서 지도 그림만 안 보입니다. 증상이 고약한
것은 나머지가 전부 멀쩡해 보인다는 점입니다 — ROS 연결도 되고 지도 목록
드롭다운도 뜹니다. 목록은 rosbridge(WebSocket)로 오고 그림만 이 HTTP 서버로
오는데, WebSocket 은 브라우저의 출처 검사를 받지 않기 때문입니다.

왜 브라우저가 막는가. 브라우저는 A 라는 주소에서 받은 화면이 B 라는 주소의
파일을 읽으려 하면 "B 가 허락했는가"를 먼저 확인합니다. 그 허락이 위 헤더입니다.
출처(origin)에는 **포트도 포함**되므로, 젯슨 위에서 브라우저를 띄워도
localhost:5000 과 localhost:8000 은 서로 남입니다. 즉 IP 를 아무리 맞춰도
이 헤더 없이는 웹에서 지도가 보이지 않습니다.

안드로이드 APK 와 Linux desktop 빌드는 브라우저가 아니므로 이 검사가 없습니다.
그래서 "APK 로는 되는데 크롬으로는 안 되는" 상태가 오래 남아 있었습니다.

Flutter 3.29 부터 웹은 CanvasKit 만 씁니다. 예전 HTML 렌더러는 <img> 태그로
그려서 이 검사를 피해 갔지만, 지금은 이미지 바이트를 직접 받아 디코딩하므로
검사를 받습니다.

`/maps/` 아래만 내보냅니다. 예전에는 작업공간 전체가 열려 있었는데, 위 헤더를
붙이면 "아무 웹페이지나 이 파일을 읽어도 좋다"가 되므로 내보내는 범위를 앱이
실제로 쓰는 것으로 좁힙니다.
"""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# 앱이 읽는 경로. map_list_node 가 image_url 을 "/maps/<이름>.png" 로 만듭니다.
PUBLIC_PREFIX = "/maps/"


class MapRequestHandler(SimpleHTTPRequestHandler):
    """지도 파일만, 출처 허락 헤더를 붙여 내보냅니다."""

    def end_headers(self) -> None:
        # 이 한 줄이 이 파일이 존재하는 이유입니다.
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def send_head(self):
        # 질의문자열(?v=1)이 붙어 와도 경로만 봅니다.
        path = self.path.split("?", 1)[0].split("#", 1)[0]
        if not path.startswith(PUBLIC_PREFIX):
            # 디렉터리 목록도 여기서 함께 막힙니다.
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
    # ThreadingHTTPServer 는 python -m http.server 가 쓰는 것과 같습니다.
    # 한 요청이 늦어져도 다음 요청이 막히지 않습니다.
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
