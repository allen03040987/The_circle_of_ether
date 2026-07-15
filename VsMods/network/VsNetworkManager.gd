## VsNetworkManager — 延遲型 P2P 聯機管理器
##
## 使用方式：
##   本機雙人：VsNetworkManager.start_offline()
##   主機：    VsNetworkManager.host_game()         → 等 room_created 信號取得房間號
##   加入：    VsNetworkManager.join_game("ABC123") → 等 connected 信號
##
## 每個物理幀在 vs_world._physics_process 裡呼叫 tick()，
## 回傳 [] 代表等待（stall），回傳 [p1_input, p2_input] 代表可推進這幀。
##
## 需要安裝 webrtc-native GDExtension（桌面聯機）：
## https://github.com/godotengine/webrtc-native/releases
##
## 信令伺服器預設指向本機（開發用），正式上線前改 SIGNALING_URL。

extends Node

# ── 信號 ─────────────────────────────────────────────────────────────────────
signal room_created(code: String)    # HOST 建立房間成功，顯示此 code 給對方
signal connected()                    # 雙方資料通道開啟，可以開始遊戲
signal disconnected()
signal connection_error(msg: String)

# ── 設定 ─────────────────────────────────────────────────────────────────────
## 本機測試時用 ws://127.0.0.1:8765，部署後換成 wss://你的伺服器
const SIGNALING_URL := "wss://the-circle-of-ether-signal.onrender.com"
const STUN_SERVERS  := [{"urls": ["stun:stun.l.google.com:19302"]}]
## 延遲幀數：4 幀 @ 60fps ≈ 67ms，可依網路狀況調整
const INPUT_DELAY   := 4

# ── 狀態 ─────────────────────────────────────────────────────────────────────
enum Mode { OFFLINE, HOST, CLIENT }
var mode             := Mode.OFFLINE
var local_player_id  := 1   # 1 = P1（HOST）, 2 = P2（CLIENT）

var _game_frame := 0   # 目前要執行的遊戲幀
var _send_frame := 0   # 目前要收集並傳送的輸入幀（超前 INPUT_DELAY）

var _local_inputs:  Dictionary = {}  # frame → PackedByteArray(2 bytes)
var _remote_inputs: Dictionary = {}  # frame → PackedByteArray(2 bytes)

var _ws               := WebSocketPeer.new()
var _rtc:    Object   = null   # WebRTCPeerConnection（plugin 才有）
var _channel: Object  = null   # WebRTCDataChannel
var _room_code        := ""
var _rtc_available    := false
var _ws_ready_sent    := false
var _channel_was_open := false
var _ws_ever_opened   := false   # 本次連線是否曾達到 STATE_OPEN
var _ws_connect_timer := 0.0     # WS 連線等待計時（秒）
var _error_emitted    := false   # 避免同一次連線重複發出錯誤
const WS_TIMEOUT      := 90.0    # 等待信令伺服器上線的最長秒數（含冷啟動）

# ── 初始化 ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_rtc_available = ClassDB.class_exists("WebRTCPeerConnection")
	if not _rtc_available:
		push_warning("VsNetworkManager: webrtc-native 未安裝，聯機功能停用。")

func _process(delta: float) -> void:
	_poll_ws(delta)
	_poll_rtc()

# ── 公開 API ──────────────────────────────────────────────────────────────────
func start_offline() -> void:
	mode = Mode.OFFLINE
	local_player_id = 1
	_reset()

func host_game() -> void:
	if not _rtc_available:
		connection_error.emit("請先安裝 webrtc-native GDExtension")
		return
	mode = Mode.HOST
	local_player_id = 1
	_reset()
	_ws_connect()

func join_game(code: String) -> void:
	if not _rtc_available:
		connection_error.emit("請先安裝 webrtc-native GDExtension")
		return
	mode = Mode.CLIENT
	local_player_id = 2
	_room_code = code.strip_edges().to_upper()
	_reset()
	_ws_connect()

## 每個物理幀呼叫一次，傳入本地玩家輸入。
## 回傳 [] = stall（等待對方輸入），回傳 [p1:InputState, p2:InputState] = 可推進。
func tick(local_input: InputState) -> Array:
	# 收集本幀輸入並傳送（超前 INPUT_DELAY 幀）
	var bytes := local_input.to_bytes()
	_local_inputs[_send_frame] = bytes
	_send_packet(_send_frame, bytes)
	_send_frame += 1

	# 判斷是否可以執行 _game_frame
	if not _can_step():
		return []

	# 取出雙方輸入
	var exec := _game_frame
	var EMPTY := PackedByteArray([0, 0])
	var li := InputState.from_bytes(_local_inputs.get(exec, EMPTY))
	var ri: InputState
	if mode == Mode.OFFLINE:
		var other_id := 2 if local_player_id == 1 else 1
		ri = InputState.from_input(other_id)
	else:
		ri = InputState.from_bytes(_remote_inputs.get(exec, EMPTY))

	_game_frame += 1

	# 永遠回傳 [P1_input, P2_input]
	if local_player_id == 1:
		return [li, ri]
	else:
		return [ri, li]

# ── 內部：幀管理 ──────────────────────────────────────────────────────────────
func _reset() -> void:
	_game_frame = 0
	_send_frame = 0
	_local_inputs.clear()
	_remote_inputs.clear()
	_ws_ready_sent    = false
	_channel_was_open = false
	_ws_ever_opened   = false
	_ws_connect_timer = 0.0
	_error_emitted    = false
	_rtc     = null
	_channel = null
	_ws.close()
	_ws = WebSocketPeer.new()

func _can_step() -> bool:
	if mode == Mode.OFFLINE:
		return true
	# 暖機期（前 INPUT_DELAY 幀）直接放行，因為對方輸入還沒傳到
	if _game_frame < INPUT_DELAY:
		return true
	return (_game_frame in _local_inputs) and (_game_frame in _remote_inputs)

# ── 內部：封包 ────────────────────────────────────────────────────────────────
func _send_packet(frame: int, bytes: PackedByteArray) -> void:
	if not _channel or _channel.get_ready_state() != 1:   # 1 = STATE_OPEN
		return
	var pkt := PackedByteArray()
	pkt.resize(6)
	pkt.encode_u32(0, frame)
	pkt[4] = bytes[0]
	pkt[5] = bytes[1]
	_channel.put_packet(pkt)

func _recv_packet(pkt: PackedByteArray) -> void:
	if pkt.size() < 6:
		return
	var frame := pkt.decode_u32(0)
	_remote_inputs[frame] = pkt.slice(4, 6)

# ── 內部：WebSocket 信令 ──────────────────────────────────────────────────────
func _ws_connect() -> void:
	_ws.connect_to_url(SIGNALING_URL)

func _poll_ws(delta: float = 0.0) -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	match state:
		WebSocketPeer.STATE_CONNECTING:
			if not _ws_ever_opened and mode != Mode.OFFLINE:
				_ws_connect_timer += delta
				if _ws_connect_timer >= WS_TIMEOUT and not _error_emitted:
					_error_emitted = true
					_ws.close()
					connection_error.emit("信令伺服器連線逾時（%.0f秒）\n請確認伺服器是否正常運行" % WS_TIMEOUT)
		WebSocketPeer.STATE_OPEN:
			_ws_ever_opened = true
			_ws_connect_timer = 0.0
			if not _ws_ready_sent:
				_ws_ready_sent = true
				if mode == Mode.HOST:
					_ws.send_text(JSON.stringify({"type": "create"}))
				elif mode == Mode.CLIENT:
					_ws.send_text(JSON.stringify({"type": "join", "code": _room_code}))
			while _ws.get_available_packet_count() > 0:
				_handle_signal(JSON.parse_string(_ws.get_packet().get_string_from_utf8()))
		WebSocketPeer.STATE_CLOSED:
			if _channel_was_open:
				_channel_was_open = false
				disconnected.emit()
			elif not _ws_ever_opened and mode != Mode.OFFLINE and not _error_emitted:
				_error_emitted = true
				connection_error.emit("無法連線到信令伺服器，請確認伺服器是否正常運行")

func _handle_signal(msg) -> void:
	if not msg:
		return
	match msg.get("type", ""):
		"created":
			_room_code = msg.get("code", "")
			room_created.emit(_room_code)
			_setup_rtc()
		"peer_joined":
			# HOST 收到 CLIENT 加入，開始建立 WebRTC 連線
			_rtc.create_offer()
		"joined":
			# CLIENT 加入成功，RTCPeer 設好後等 HOST 的 offer
			_setup_rtc()
		"offer":
			_rtc.set_remote_description("offer", msg.get("sdp", ""))
		"answer":
			_rtc.set_remote_description("answer", msg.get("sdp", ""))
		"ice":
			_rtc.add_ice_candidate(
				msg.get("media", ""),
				int(msg.get("index", 0)),
				msg.get("name", "")
			)
		"error":
			connection_error.emit(msg.get("msg", "未知錯誤"))

# ── 內部：WebRTC ──────────────────────────────────────────────────────────────
func _setup_rtc() -> void:
	_rtc = WebRTCPeerConnection.new()
	_rtc.initialize({"iceServers": STUN_SERVERS})
	_rtc.session_description_created.connect(_on_sdp)
	_rtc.ice_candidate_created.connect(_on_ice)
	if mode == Mode.HOST:
		# HOST 建立資料通道（無序、不重傳 → 類 UDP 行為）
		_channel = _rtc.create_data_channel("vs_input", {
			"ordered": false, "maxRetransmits": 0
		})
		_channel.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
	else:
		_rtc.data_channel_received.connect(_on_channel_received)

func _poll_rtc() -> void:
	if _rtc:
		_rtc.poll()
	if not _channel:
		return
	_channel.poll()
	# 資料通道剛開啟時發出 connected 信號
	var is_open: bool = _channel.get_ready_state() == 1
	if is_open and not _channel_was_open:
		_channel_was_open = true
		connected.emit()
	if is_open:
		while _channel.get_available_packet_count() > 0:
			_recv_packet(_channel.get_packet())

func _on_sdp(type: String, sdp: String) -> void:
	_rtc.set_local_description(type, sdp)
	_ws.send_text(JSON.stringify({"type": type, "sdp": sdp, "room": _room_code}))

func _on_ice(media: String, index: int, name: String) -> void:
	_ws.send_text(JSON.stringify({
		"type": "ice", "media": media, "index": index, "name": name, "room": _room_code
	}))

func _on_channel_received(channel: Object) -> void:
	# CLIENT 收到 HOST 開啟的資料通道
	_channel = channel
	_channel.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
