"""iOS 実機の位置情報を地図からシミュレートするローカル GUI サーバー。

前提: 別ターミナルで `sudo pymobiledevice3 remote tunneld` を起動しておく（iOS 17 以降）。
使い方: python server.py  →  http://127.0.0.1:8765 を開く
"""

import asyncio
import sys
import json
import math
import threading
import webbrowser
from contextlib import AsyncExitStack
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation
from pymobiledevice3.tunneld.api import get_tunneld_tunnels, get_tunneld_device_by_udid

HOST, PORT = "127.0.0.1", 8765
INDEX_HTML = Path(__file__).with_name("index.html")
STEP_SECONDS = 1.0  # ルート再生時に位置を送る間隔

loop = asyncio.new_event_loop()


class DeviceSession:
    """1 台の端末への DVT 接続を開いたまま保持する（閉じるとシミュレーションが解除されるため）。"""

    def __init__(self, udid: str):
        self.udid = udid
        self.stack: AsyncExitStack | None = None
        self.location: LocationSimulation | None = None

    async def _connect(self) -> None:
        await self._close()
        rsd = await get_tunneld_device_by_udid(self.udid)
        if rsd is None:
            raise RuntimeError(f"tunneld に端末 {self.udid} が見つかりません")
        stack = AsyncExitStack()
        try:
            await stack.enter_async_context(rsd)
            dvt = await stack.enter_async_context(DvtProvider(rsd))
            self.location = await stack.enter_async_context(LocationSimulation(dvt))
        except BaseException:
            await stack.aclose()
            raise
        self.stack = stack

    async def _close(self) -> None:
        if self.stack is not None:
            try:
                await self.stack.aclose()
            except Exception:
                pass
        self.stack = None
        self.location = None

    async def _call(self, fn) -> None:
        # 接続が切れていたら 1 回だけ張り直して再試行する
        for attempt in range(2):
            try:
                if self.location is None:
                    await self._connect()
                await fn(self.location)
                return
            except Exception:
                await self._close()
                if attempt == 1:
                    raise

    async def set(self, lat: float, lng: float) -> None:
        await self._call(lambda loc: loc.set(lat, lng))

    async def clear(self) -> None:
        await self._call(lambda loc: loc.clear())
        await self._close()


class State:
    def __init__(self):
        self.sessions: dict[str, DeviceSession] = {}
        self.position: dict | None = None  # {"lat", "lng"}
        self.route_task: asyncio.Task | None = None
        self.route_progress: dict | None = None  # {"index", "total", "paused"}
        self.paused = asyncio.Event()  # set = 一時停止中
        self.last_error: str | None = None

    def session(self, udid: str) -> DeviceSession:
        if udid not in self.sessions:
            self.sessions[udid] = DeviceSession(udid)
        return self.sessions[udid]


state = State()


def haversine_m(a, b) -> float:
    r = 6371000.0
    lat1, lat2 = math.radians(a[0]), math.radians(b[0])
    dlat = lat2 - lat1
    dlng = math.radians(b[1] - a[1])
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlng / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def interpolate_route(points: list[list[float]], speed_kmh: float) -> list[tuple[float, float]]:
    """ウェイポイント列を、指定速度で STEP_SECONDS ごとの座標列に展開する。"""
    step_m = max(speed_kmh, 0.1) * 1000 / 3600 * STEP_SECONDS
    out = [tuple(points[0])]
    carry = 0.0  # 前の区間で余った距離
    for a, b in zip(points, points[1:]):
        seg = haversine_m(a, b)
        d = step_m - carry
        while d <= seg:
            t = d / seg
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            d += step_m
        carry = seg - (d - step_m)
    if out[-1] != tuple(points[-1]):
        out.append(tuple(points[-1]))
    return out


async def stop_route() -> None:
    if state.route_task and not state.route_task.done():
        state.route_task.cancel()
        try:
            await state.route_task
        except (asyncio.CancelledError, Exception):
            pass
    state.route_task = None
    state.route_progress = None
    state.paused.clear()


async def run_route(udid: str, coords: list[tuple[float, float]], loop_route: bool) -> None:
    sess = state.session(udid)
    try:
        while True:
            for i, (lat, lng) in enumerate(coords):
                while state.paused.is_set():
                    await asyncio.sleep(0.2)
                await sess.set(lat, lng)
                state.position = {"lat": lat, "lng": lng}
                state.route_progress = {"index": i + 1, "total": len(coords), "paused": False}
                await asyncio.sleep(STEP_SECONDS)
            if not loop_route:
                break
            coords = coords[::-1]  # 往復
    except asyncio.CancelledError:
        raise
    except Exception as e:
        state.last_error = f"ルート再生中にエラー: {e}"
    finally:
        state.route_progress = None


async def list_devices() -> list[dict]:
    tunnels = await get_tunneld_tunnels()
    devices = []
    for udid in tunnels:
        name = udid
        try:
            rsd = await get_tunneld_device_by_udid(udid)
            if rsd is not None:
                values = rsd.lockdown.all_values if rsd.lockdown else {}
                name = f"{values.get('DeviceName', rsd.product_type)} ({rsd.product_type}, iOS {rsd.product_version})"
                await rsd.close()
        except Exception:
            pass
        devices.append({"udid": udid, "name": name})
    return devices


async def handle_api(path: str, body: dict) -> dict:
    if path == "/api/devices":
        return {"devices": await list_devices()}
    if path == "/api/status":
        err, state.last_error = state.last_error, None
        return {"position": state.position, "route": state.route_progress, "error": err}
    if path == "/api/set":
        await stop_route()
        lat, lng = float(body["lat"]), float(body["lng"])
        await state.session(body["udid"]).set(lat, lng)
        state.position = {"lat": lat, "lng": lng}
        return {"ok": True}
    if path == "/api/clear":
        await stop_route()
        await state.session(body["udid"]).clear()
        state.position = None
        return {"ok": True}
    if path == "/api/route/start":
        await stop_route()
        points = body["points"]
        if len(points) < 2:
            raise ValueError("ルートには 2 点以上必要です")
        coords = interpolate_route(points, float(body.get("speed", 4.8)))
        state.route_progress = {"index": 0, "total": len(coords), "paused": False}
        state.route_task = loop.create_task(run_route(body["udid"], coords, bool(body.get("loop"))))
        return {"ok": True, "steps": len(coords)}
    if path == "/api/route/pause":
        if state.paused.is_set():
            state.paused.clear()
        else:
            state.paused.set()
        if state.route_progress:
            state.route_progress["paused"] = state.paused.is_set()
        return {"ok": True, "paused": state.paused.is_set()}
    if path == "/api/route/stop":
        await stop_route()
        return {"ok": True}
    raise KeyError(path)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code: int, payload: bytes, ctype: str = "application/json") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _api(self, body: dict) -> None:
        future = asyncio.run_coroutine_threadsafe(handle_api(self.path, body), loop)
        try:
            result = future.result(timeout=30)
            self._send(200, json.dumps(result).encode())
        except KeyError:
            self._send(404, b'{"error": "not found"}')
        except Exception as e:
            msg = str(e) or type(e).__name__
            if type(e).__name__ == "TunneldConnectionError":
                msg = "tunneld に接続できません。`sudo pymobiledevice3 remote tunneld` を起動してください"
            self._send(500, json.dumps({"error": msg}).encode())

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self._send(200, INDEX_HTML.read_bytes(), "text/html; charset=utf-8")
        elif self.path.startswith("/api/"):
            self._api({})
        else:
            self._send(404, b"not found", "text/plain")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        self._api(body)


def main() -> None:
    threading.Thread(target=loop.run_forever, daemon=True).start()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    url = f"http://{HOST}:{PORT}"
    print(f"位置シミュレータ: {url}  (Ctrl+C で終了)")
    if "--no-browser" not in sys.argv:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        # 終了時はシミュレーションを解除して実際の GPS に戻す
        async def cleanup():
            await stop_route()
            for sess in state.sessions.values():
                if sess.location is not None:
                    try:
                        await sess.clear()
                    except Exception:
                        pass
        asyncio.run_coroutine_threadsafe(cleanup(), loop).result(timeout=10)


if __name__ == "__main__":
    main()
