# 信令伺服器 — 僅負責幫兩個玩家交換連線資訊，不轉發遊戲封包
#
# 本機測試（兩台電腦在同一區域網）：
#   直接跑這個腳本，客戶端把 SIGNALING_URL 改成 ws://<本機IP>:8765
#
# 免費上線（讓世界各地的人都能連）：
#   部署到 Render.com 或 Fly.io 免費方案
#   Render: 新建 Web Service → Runtime: Python → Start Command: python signaling_server.py
#   Fly.io: fly launch → 選 Python → fly deploy
#   部署後把 VsNetworkManager.gd 裡的 SIGNALING_URL 改成 wss://<你的域名>
#
# 安裝依賴：pip install websockets
# 執行：    python signaling_server.py

import asyncio
import json
import os
import random
import string
import websockets
from websockets.server import WebSocketServerProtocol

# room_code → [ws_host, ws_client?]
rooms: dict[str, list[WebSocketServerProtocol]] = {}


def _new_code() -> str:
    chars = string.ascii_uppercase + string.digits
    while True:
        code = "".join(random.choices(chars, k=6))
        if code not in rooms:
            return code


async def handle(ws: WebSocketServerProtocol) -> None:
    room_code: str | None = None
    try:
        async for raw in ws:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue

            t = msg.get("type", "")

            if t == "create":
                room_code = _new_code()
                rooms[room_code] = [ws]
                await ws.send(json.dumps({"type": "created", "code": room_code}))
                print(f"[{room_code}] 房間建立")

            elif t == "join":
                code = msg.get("code", "").strip().upper()
                if code not in rooms or len(rooms[code]) != 1:
                    await ws.send(json.dumps({"type": "error", "msg": "room_not_found"}))
                    continue
                room_code = code
                rooms[code].append(ws)
                host_ws = rooms[code][0]
                await host_ws.send(json.dumps({"type": "peer_joined"}))
                await ws.send(json.dumps({"type": "joined"}))
                print(f"[{room_code}] 玩家加入，開始 WebRTC 握手")

            elif t in ("offer", "answer", "ice"):
                # 轉發給同房間的另一方
                code = msg.get("room", room_code)
                if not code or code not in rooms:
                    continue
                other = next((p for p in rooms[code] if p is not ws), None)
                if other:
                    await other.send(raw)

    except websockets.ConnectionClosed:
        pass
    finally:
        if room_code and room_code in rooms:
            rooms[room_code] = [p for p in rooms[room_code] if p is not ws]
            if not rooms[room_code]:
                del rooms[room_code]
                print(f"[{room_code}] 房間關閉")


async def main() -> None:
    port = int(os.environ.get("PORT", 8765))
    async with websockets.serve(handle, "0.0.0.0", port):
        print(f"Signaling server 啟動，監聽 :{port}")
        await asyncio.Future()


asyncio.run(main())
