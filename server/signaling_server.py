import asyncio
import json
import os
import random
import string
import websockets

# room_code → [ws_host, ws_client?]
rooms: dict = {}


def _new_code() -> str:
    chars = string.ascii_uppercase + string.digits
    while True:
        code = "".join(random.choices(chars, k=1))
        if code not in rooms:
            return code


async def handle(ws) -> None:
    room_code = None
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

            elif t in ("offer", "answer", "ice", "arts", "arena"):
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


## Render 的健康檢查是一般 HTTP GET（不是 WebSocket handshake）——這個伺服器
## 純粹只講 WebSocket，沒有這個 handler 的話，健康檢查的請求會被 websockets
## 函式庫當成無效的 WS handshake直接拒絕/掛著，Render 在部署時等不到成功回應
## 就會 "Timed Out"（process 其實早就正常啟動、正常監聽，只是過不了健康檢查，
## 從 log 的 "監聽 :port" 那行有印出來就能確認）。回傳 200 給任何非 WS 的
## 一般 HTTP 請求即可。不加型別註解（跟 handle() 的既有慣例一致）——避免
## 跟著 websockets 函式庫版本（此專案不釘死版本，requirements.txt 是
## >=12.0）改變 API 而壞掉。
async def _health_check(connection, request):
    if request.path != "/favicon.ico":
        return connection.respond(200, "OK\n")
    return None


async def main() -> None:
    port = int(os.environ.get("PORT", 8765))
    async with websockets.serve(handle, "0.0.0.0", port, process_request=_health_check):
        print(f"Signaling server 啟動，監聽 :{port}")
        await asyncio.Future()


asyncio.run(main())
