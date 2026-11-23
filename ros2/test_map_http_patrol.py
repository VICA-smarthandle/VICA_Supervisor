#!/usr/bin/env python3
"""map_http_server.py 의 경비 기록(/patrol/) 시험입니다. ROS도 로봇도 필요 없습니다."""
from __future__ import annotations

import json
import os
import shutil
import sys
import threading
import time
import urllib.error
import urllib.request
from functools import partial
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import map_http_server as mhs  # noqa: E402

SAMPLE_PHOTOS = Path.home() / "vica_data" / "camera_test" / "2026-11-11" / "T1"
JPEG = b"\xff\xd8\xff\xe0" + b"0" * 64 + b"\xff\xd9"
FAKE_MP4 = b"\x00\x00\x00\x18ftypisom" + bytes(range(200))


def serve(root: Path, patrol: Path):
    """빈 포트에 서버를 띄우고 (주소, 종료함수) 를 돌려줍니다."""
    handler = partial(
        mhs.MapRequestHandler, directory=str(root), patrol_directory=str(patrol)
    )
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    host, port = server.server_address[:2]

    def stop() -> None:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    return f"http://{host}:{port}", stop


def fetch(url: str, headers: dict | None = None):
    """(상태, 헤더, 본문). 4xx·5xx 도 예외 없이 돌려줍니다."""
    request = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read()


def make_clip(patrol: Path, clip_id: str, frames: int = 3, done: bool = True) -> Path:
    clip = patrol / "clips" / clip_id
    (clip / "frames").mkdir(parents=True, exist_ok=True)
    for index in range(1, frames + 1):
        (clip / "frames" / f"{index:06d}.jpg").write_bytes(JPEG + bytes([index]))
    if done:
        (clip / "meta.json").write_text(
            json.dumps(
                {
                    "id": clip_id,
                    "alarm": "intruder",
                    "start": "2026-11-14T20:34:50",
                    "end": "2026-11-14T20:35:32",
                    "fps": 5,
                    "frames": frames,
                    "width": 640,
                    "height": 480,
                }
            ),
            encoding="utf-8",
        )
    return clip


FAKE_FPS = []


def fake_convert(frames_dir: Path, out_path: Path, first: int = 1, width: int = 6,
                 fps: float = 5.0) -> bool:
    FAKE_FPS.append(fps)
    out_path.write_bytes(FAKE_MP4)
    return True


def with_convert(replacement):
    """convert_frames 를 바꿔 끼우고 되돌리는 함수를 돌려줍니다."""
    original = mhs.convert_frames
    mhs.convert_frames = replacement

    def restore() -> None:
        mhs.convert_frames = original

    return restore


def test_기록을_alarm_id로_합쳐_최신순으로_내준다(tmp_path: Path) -> None:
    patrol = tmp_path / "patrol"
    patrol.mkdir()
    make_clip(patrol, "20261114_203455_intruder", frames=210)
    lines = [
        {"type": "alarm", "alarm_id": "20261114_005207_light", "kind": "light",
         "time": "2026-11-14T00:52:07", "place": "407호", "x": 1.0, "y": 2.0,
         "map_id": "m1", "clip_id": None, "photo": "20261114_005207.jpg", "level_db": None},
        {"type": "alarm", "alarm_id": "20261114_203455_intruder", "kind": "intruder",
         "time": "2026-11-14T20:34:55", "place": "화장실", "x": 3.0, "y": 4.0,
         "map_id": "m1", "clip_id": None, "photo": None, "level_db": None},
        "이 줄은 JSON 이 아닙니다",
        {"type": "clip", "alarm_id": "20261114_203455_intruder",
         "clip_id": "20261114_203455_intruder"},
        {"type": "clip", "alarm_id": "없는_경보", "clip_id": "x"},
    ]
    (patrol / "events.jsonl").write_text(
        "\n".join(x if isinstance(x, str) else json.dumps(x, ensure_ascii=False) for x in lines)
        + "\n",
        encoding="utf-8",
    )
    restore = with_convert(fake_convert)
    base, stop = serve(tmp_path, patrol)
    try:
        status, headers, body = fetch(
            f"{base}/patrol/events.json", {"Origin": "http://localhost:5000"}
        )
        assert status == 200
        assert headers.get("Access-Control-Allow-Origin") == "*"
        assert headers.get("Content-Type", "").startswith("application/json")
        records = json.loads(body.decode("utf-8"))
        assert [r["alarm_id"] for r in records] == [
            "20261114_203455_intruder",
            "20261114_005207_light",
        ]
        first = records[0]
        assert first["clip_id"] == "20261114_203455_intruder"
        assert first["place"] == "화장실"
        assert first["clip_state"] == "ready"
        assert first["clip_sec"] == 42.0
        assert first["clip_start"] == "2026-11-14T20:34:50"
        assert first["clip_end"] == "2026-11-14T20:35:32"
        assert first["detect_sec"] == 5.0
        assert records[1]["photo"] == "20261114_005207.jpg"
        assert records[1]["clip_state"] == "missing"
        assert "type" not in first
    finally:
        stop()
        restore()


def test_기록은_200건까지만_내준다(tmp_path: Path) -> None:
    patrol = tmp_path / "patrol"
    patrol.mkdir()
    with (patrol / "events.jsonl").open("w", encoding="utf-8") as file:
        for index in range(250):
            file.write(json.dumps({
                "type": "alarm", "alarm_id": f"a{index:04d}", "kind": "sound",
                "time": f"2026-11-14T00:{index // 60:02d}:{index % 60:02d}",
                "level_db": 70.5,
            }) + "\n")
    records = mhs.read_patrol_events(patrol)
    assert len(records) == 200
    assert records[0]["alarm_id"] == "a0249"
    assert records[-1]["alarm_id"] == "a0050"
    assert records[0]["level_db"] == 70.5


def test_기록_파일이_없으면_빈_배열이다(tmp_path: Path) -> None:
    patrol = tmp_path / "patrol"
    base, stop = serve(tmp_path, patrol)
    try:
        status, _, body = fetch(f"{base}/patrol/events.json")
        assert status == 200
        assert json.loads(body) == []
    finally:
        stop()


def test_정해진_주소_밖은_내보내지_않는다(tmp_path: Path) -> None:
    patrol = tmp_path / "patrol"
    (patrol / "photos").mkdir(parents=True)
    (patrol / "events.jsonl").write_text("{}\n", encoding="utf-8")
    (patrol / "photos" / "ok.jpg").write_bytes(JPEG)
    (tmp_path / "secret.txt").write_text("폴더 밖 파일", encoding="utf-8")
    (tmp_path / "secret.jpg").write_bytes(JPEG)
    os.symlink(tmp_path / "secret.jpg", patrol / "photos" / "link.jpg")
    make_clip(patrol, "c1")
    base, stop = serve(tmp_path, patrol)
    try:
        for path in (
            "/patrol/",
            "/patrol",
            "/patrol/events.jsonl",
            "/patrol/clips/",
            "/patrol/clips/c1/",
            "/patrol/clips/c1/meta.json",
            "/patrol/photos/",
            "/patrol/photos/../events.jsonl",
            "/patrol/photos/..%2Fevents.jsonl",
            "/patrol/photos/..%2F..%2Fsecret.jpg",
            "/patrol/photos/link.jpg",
            "/patrol/clips/..%2F..%2Fsecret.mp4",
            "/patrol/clips/c1/frames/..%2F..%2F..%2F..%2Fsecret.jpg",
            "/patrol/../secret.txt",
            "/patrol/photos/ok.jpg/../../events.jsonl",
        ):
            status, _, _ = fetch(f"{base}{path}")
            assert status == 404, f"{path} 가 404 가 아닙니다({status})"
        status, headers, body = fetch(f"{base}/patrol/photos/ok.jpg")
        assert status == 200 and body == JPEG
        assert headers.get("Content-Type") == "image/jpeg"
    finally:
        stop()


def test_경비_폴더를_안_주면_patrol은_404다(tmp_path: Path) -> None:
    handler = partial(mhs.MapRequestHandler, directory=str(tmp_path))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    host, port = server.server_address[:2]
    try:
        status, _, _ = fetch(f"http://{host}:{port}/patrol/events.json")
        assert status == 404
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def test_사진_목록과_사진_한_장을_내준다(tmp_path: Path) -> None:
    patrol = tmp_path / "patrol"
    make_clip(patrol, "c1", frames=4, done=False)
    base, stop = serve(tmp_path, patrol)
    try:
        status, _, body = fetch(f"{base}/patrol/clips/c1/frames.json")
        assert status == 200
        listing = json.loads(body)
        assert listing == {
            "id": "c1",
            "fps": 5,
            "count": 4,
            "frames": ["000001.jpg", "000002.jpg", "000003.jpg", "000004.jpg"],
        }
        status, headers, body = fetch(f"{base}/patrol/clips/c1/frames/000002.jpg")
        assert status == 200 and body == JPEG + bytes([2])
        assert headers.get("Content-Type") == "image/jpeg"
        status, _, body = fetch(f"{base}/patrol/clips/c1.jpg")
        assert status == 200 and body == JPEG + bytes([1])
        status, _, _ = fetch(f"{base}/patrol/clips/none/frames.json")
        assert status == 404
    finally:
        stop()


def test_mp4가_없으면_사진으로_만들고_사진은_지운다(tmp_path: Path) -> None:
    patrol = tmp_path / "patrol"
    clip = make_clip(patrol, "c1", frames=5)
    restore = with_convert(fake_convert)
    base, stop = serve(tmp_path, patrol)
    try:
        status, headers, body = fetch(f"{base}/patrol/clips/c1.mp4")
        assert status == 200 and body == FAKE_MP4
        assert headers.get("Content-Type") == "video/mp4"
        assert headers.get("Accept-Ranges") == "bytes"
        assert headers.get("Access-Control-Allow-Origin") == "*"
        assert (patrol / "clips" / "c1.mp4").read_bytes() == FAKE_MP4
        assert not (clip / "frames").exists(), "만든 뒤에는 사진을 지웁니다"
        assert (patrol / "clips" / "c1.jpg").read_bytes() == JPEG + bytes([1])
        assert (clip / "meta.json").is_file(), "meta.json 은 남깁니다"
        assert not list((patrol / "clips").glob(".*part*")), "임시 파일이 남았습니다"
        mhs.convert_frames = lambda *a, **k: (_ for _ in ()).throw(AssertionError("다시 변환"))
        status, _, body = fetch(f"{base}/patrol/clips/c1.mp4")
        assert status == 200 and body == FAKE_MP4
        status, _, _ = fetch(f"{base}/patrol/clips/c1/frames.json")
        assert status == 404
    finally:
        stop()
        restore()


def test_mp4는_Range_요청에_구간만_보낸다(tmp_path: Path) -> None:
    patrol = tmp_path / "patrol"
    (patrol / "clips").mkdir(parents=True)
    (patrol / "clips" / "c1.mp4").write_bytes(FAKE_MP4)
    size = len(FAKE_MP4)
    base, stop = serve(tmp_path, patrol)
    try:
        status, headers, body = fetch(f"{base}/patrol/clips/c1.mp4", {"Range": "bytes=10-19"})
        assert status == 206
        assert body == FAKE_MP4[10:20]
        assert headers.get("Content-Range") == f"bytes 10-19/{size}"
        assert headers.get("Content-Length") == "10"
        assert headers.get("Content-Type") == "video/mp4"

        status, headers, body = fetch(f"{base}/patrol/clips/c1.mp4", {"Range": "bytes=100-"})
        assert status == 206 and body == FAKE_MP4[100:]
        assert headers.get("Content-Range") == f"bytes 100-{size - 1}/{size}"

        status, _, body = fetch(f"{base}/patrol/clips/c1.mp4", {"Range": "bytes=-16"})
        assert status == 206 and body == FAKE_MP4[-16:]

        status, _, body = fetch(f"{base}/patrol/clips/c1.mp4", {"Range": "bytes=0-99999"})
        assert status == 206 and body == FAKE_MP4

        status, headers, _ = fetch(f"{base}/patrol/clips/c1.mp4", {"Range": f"bytes={size}-"})
        assert status == 416
        assert headers.get("Content-Range") == f"bytes */{size}"
    finally:
        stop()


def test_저장_중인_장면은_바꾸지_않는다(tmp_path: Path) -> None:
    patrol = tmp_path / "patrol"
    clip = make_clip(patrol, "c1", frames=3, done=False)
    restore = with_convert(fake_convert)
    base, stop = serve(tmp_path, patrol)
    try:
        status, _, _ = fetch(f"{base}/patrol/clips/c1.mp4")
        assert status == 404
        assert len(list((clip / "frames").iterdir())) == 3, "쓰는 중인 사진을 지우면 안 됩니다"
        assert mhs.clip_info(patrol, "c1")["clip_state"] == "recording"
        old = time.time() - mhs.CLIP_STALE_SEC - 5
        for frame in (clip / "frames").iterdir():
            os.utime(frame, (old, old))
        assert mhs.clip_info(patrol, "c1")["clip_state"] == "ready"
        status, _, body = fetch(f"{base}/patrol/clips/c1.mp4")
        assert status == 200 and body == FAKE_MP4
    finally:
        stop()
        restore()


def test_변환에_실패하면_사진을_그대로_둔다(tmp_path: Path) -> None:
    patrol = tmp_path / "patrol"
    clip = make_clip(patrol, "c1", frames=3)
    restore = with_convert(lambda *args, **kwargs: False)
    base, stop = serve(tmp_path, patrol)
    try:
        status, _, _ = fetch(f"{base}/patrol/clips/c1.mp4")
        assert status == 404
        assert len(list((clip / "frames").iterdir())) == 3
        assert not (patrol / "clips" / "c1.mp4").exists()
        status, _, body = fetch(f"{base}/patrol/clips/c1/frames.json")
        assert status == 200 and json.loads(body)["count"] == 3
    finally:
        stop()
        restore()


def test_기록을_내준_뒤_밀린_변환을_뒤에서_한다(tmp_path: Path) -> None:
    patrol = tmp_path / "patrol"
    make_clip(patrol, "20261114_010000_sound", frames=2)
    make_clip(patrol, "20261114_020000_intruder", frames=2)
    make_clip(patrol, "20261114_030000_intruder", frames=2, done=False)
    (patrol / "events.jsonl").write_text("", encoding="utf-8")
    restore = with_convert(fake_convert)
    base, stop = serve(tmp_path, patrol)
    try:
        status, _, _ = fetch(f"{base}/patrol/events.json")
        assert status == 200
        deadline = time.time() + 5
        clips = patrol / "clips"
        while time.time() < deadline:
            if (clips / "20261114_010000_sound.mp4").exists() and (
                clips / "20261114_020000_intruder.mp4"
            ).exists():
                break
            time.sleep(0.05)
        assert (clips / "20261114_010000_sound.mp4").exists()
        assert (clips / "20261114_020000_intruder.mp4").exists()
        assert not (clips / "20261114_030000_intruder.mp4").exists(), "저장 중인 장면"
    finally:
        stop()
        restore()


def test_기존_지도_경로는_그대로다(tmp_path: Path) -> None:
    (tmp_path / "maps").mkdir()
    (tmp_path / "maps" / "m.png").write_bytes(b"\x89PNG\r\n\x1a\n" + b"0" * 8)
    (tmp_path / "secret.txt").write_text("x", encoding="utf-8")
    base, stop = serve(tmp_path, tmp_path / "patrol")
    try:
        status, headers, _ = fetch(f"{base}/maps/m.png")
        assert status == 200
        assert headers.get("Access-Control-Allow-Origin") == "*"
        assert headers.get("Cache-Control") == "no-cache"
        status, _, _ = fetch(f"{base}/secret.txt")
        assert status == 404
    finally:
        stop()


def test_실제_인코더로_75장을_mp4로_만든다(tmp_path: Path) -> None:
    """젯슨 하드웨어 인코더(없으면 ffmpeg)로 실제 사진을 바꿔 봅니다. 자료가 없으면 건너뜁니다."""
    photos = sorted(SAMPLE_PHOTOS.glob("*_color.jpg"))[:75]
    has_tool = shutil.which("gst-launch-1.0") or shutil.which("ffmpeg")
    if len(photos) < 75 or not has_tool:
        print("  (건너뜀: 시험 사진 75장 또는 인코더가 없습니다)")
        return
    patrol = tmp_path / "patrol"
    clip = patrol / "clips" / "20261111_203728_intruder"
    (clip / "frames").mkdir(parents=True)
    for index, photo in enumerate(photos, start=1):
        shutil.copyfile(photo, clip / "frames" / f"{index:06d}.jpg")
    (clip / "meta.json").write_text(
        json.dumps({"id": clip.name, "alarm": "intruder", "fps": 5, "frames": 75}),
        encoding="utf-8",
    )
    started = time.time()
    target = mhs.ensure_clip_mp4(patrol, clip.name)
    elapsed = time.time() - started
    assert target is not None, "gst-launch 와 ffmpeg 둘 다 실패했습니다"
    size = target.stat().st_size
    print(f"  75장 → {elapsed:.2f} s, {size / 1e6:.2f} MB")
    assert target.read_bytes()[4:8] == b"ftyp"
    assert 10_000 < size < 5_000_000
    assert not (clip / "frames").exists()
    assert (patrol / "clips" / f"{clip.name}.jpg").is_file()


def test_기록은_파일_끝에서_필요한_만큼만_읽는다(tmp_path: Path) -> None:
    """events.jsonl 은 지우지 않는 파일이라 끝의 256 KB 만 읽습니다(요청마다 전체를 읽지 않게)."""
    patrol = tmp_path / "patrol"
    patrol.mkdir()
    path = patrol / "events.jsonl"
    with path.open("w", encoding="utf-8") as file:
        for index in range(3000):
            file.write(json.dumps({
                "type": "alarm", "alarm_id": f"a{index:05d}", "kind": "sound",
                "time": f"2026-11-{index // 1440 + 1:02d}T{index // 60 % 24:02d}:{index % 60:02d}:00",
                "place": "긴 이름의 장소" * 4, "x": 1.0, "y": 2.0, "map_id": "m1",
                "clip_id": None, "photo": None, "level_db": 70.5,
            }, ensure_ascii=False) + "\n")
    assert path.stat().st_size > 2 * mhs.EVENTS_TAIL_BYTES

    lines = mhs._tail_lines(path)
    assert len(lines) < 3000, "파일 전체를 읽었습니다"
    assert sum(len(line.encode("utf-8")) + 1 for line in lines) <= mhs.EVENTS_TAIL_BYTES + 1
    assert all(json.loads(line)["alarm_id"] for line in lines)

    records = mhs.read_patrol_events(patrol)
    assert len(records) == 200
    assert records[0]["alarm_id"] == "a02999"
    assert records[-1]["alarm_id"] == "a02800"

    small = tmp_path / "small.jsonl"
    small.write_bytes(b"aaa\nbbb\nccc\n")
    assert mhs._tail_lines(small, 4) == ["ccc"]
    assert mhs._tail_lines(small, 5) == ["ccc"]
    assert mhs._tail_lines(small, 8) == ["bbb", "ccc"]
    assert mhs._tail_lines(small, 100) == ["aaa", "bbb", "ccc"]
    assert mhs._tail_lines(tmp_path / "없는_파일") == []


def test_장면_시각은_epoch_값을_먼저_쓴다(tmp_path: Path) -> None:
    """감지 노드는 UTC 컨테이너에서 돌아 글자 시각이 어긋납니다. start_epoch·end_epoch 가 있으면 그것을 씁니다."""
    from datetime import datetime

    patrol = tmp_path / "patrol"
    clip = make_clip(patrol, "c1", frames=210)
    start = datetime(2026, 11, 14, 20, 34, 50).timestamp()
    meta = {
        "id": "c1", "alarm": "intruder", "fps": 5, "frames": 210,
        "start": "2026-11-14T11:34:50", "end": "2026-11-14T11:35:32",
        "start_epoch": start, "end_epoch": start + 42.0,
    }
    (clip / "meta.json").write_text(json.dumps(meta), encoding="utf-8")
    info = mhs.clip_info(patrol, "c1", "2026-11-14T20:34:55")
    assert info["clip_start"] == "2026-11-14T20:34:50"
    assert info["clip_end"] == "2026-11-14T20:35:32"
    assert info["detect_sec"] == 5.0

    del meta["start_epoch"], meta["end_epoch"]
    (clip / "meta.json").write_text(json.dumps(meta), encoding="utf-8")
    info = mhs.clip_info(patrol, "c1", "2026-11-14T11:34:55")
    assert info["clip_start"] == "2026-11-14T11:34:50"
    assert info["detect_sec"] == 5.0

    meta["start_epoch"] = True
    (clip / "meta.json").write_text(json.dumps(meta), encoding="utf-8")
    assert mhs.clip_info(patrol, "c1")["clip_start"] == "2026-11-14T11:34:50"


def main() -> int:
    import tempfile
    import traceback

    tests = [
        (name, value)
        for name, value in sorted(globals().items())
        if name.startswith("test_") and callable(value)
    ]
    failed = 0
    for name, test in tests:
        workdir = Path(tempfile.mkdtemp(prefix="map_http_patrol_test_"))
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


def test_변환은_장면_기록의_초당_장수를_쓴다(tmp_path):
    """감지 노드가 meta.json 에 적은 실제 초당 장수로 만들어야 영상이 실제 속도로 재생된다."""
    clip = tmp_path / "clips" / "20261114_203455_intruder"
    assert mhs.clip_fps(clip) == 5.0
    clip.mkdir(parents=True)
    (clip / "meta.json").write_text('{"fps": 3.41, "frames": 63}', encoding="utf-8")
    assert mhs.clip_fps(clip) == 3.41
    (clip / "meta.json").write_text('{"fps": 0}', encoding="utf-8")
    assert mhs.clip_fps(clip) == 5.0
    (clip / "meta.json").write_text('{"fps": true}', encoding="utf-8")
    assert mhs.clip_fps(clip) == 5.0


if __name__ == "__main__":
    raise SystemExit(main())


def test_browser_brief_names_the_browser_and_system():
    chrome = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36")
    edge = chrome + " Edg/131.0.0.0"
    safari = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 "
              "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1")
    firefox = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
    assert mhs.browser_brief(chrome) == "Chrome 142 Windows"
    assert mhs.browser_brief(edge) == "Edge 131 Windows"
    assert mhs.browser_brief(safari) == "Safari 17 iOS"
    assert mhs.browser_brief(firefox) == "Firefox 128 Linux"
    assert mhs.browser_brief("Dart/3.5 (dart:io)") == "Dart"
    assert mhs.browser_brief("") == "-"
