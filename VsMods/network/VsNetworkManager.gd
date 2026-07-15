## VsNetworkManager — Rollback P2P 聯機管理器
##
## 使用方式：
##   本機雙人：VsNetworkManager.start_offline()
##   主機：    VsNetworkManager.host_game()         → 等 room_created 信號取得房間號
##   加入：    VsNetworkManager.join_game("ABC123") → 等 connected 信號
##
## 每個物理幀在 vs_world._physics_process 裡呼叫 tick()，
## 永不 stall：對方輸入未到則預測（沿用上一幀），確認後 needs_rollback() 變 true。
## vs_world 負責執行回溯重模擬（_do_rollback）。
##
## 需要安裝 webrtc-native GDExtension（桌面聯機）：
## https://github.com/godotengine/webrtc-native/releases

extends Node

# ── 信號 ─────────────────────────────────────────────────────────────────────
signal room_created(code: String)    # HOST 建立房間成功，顯示此 code 給對方
signal connected()                    # 雙方資料通道開啟，可以開始遊戲
signal disconnected()
signal connection_error(msg: String)
signal remote_arts_received(arts: Array)  # 收到對方的武藝選擇
signal desync_detected(frame: int)   # 兩端 checksum 不符（確定性 bug）

# ── 設定 ─────────────────────────────────────────────────────────────────────
## 本機測試時用 ws://127.0.0.1:8765，部署後換成 wss://你的伺服器
const SIGNALING_URL := "wss://the-circle-of-ether-signal.onrender.com"
const STUN_SERVERS  := [{"urls": ["stun:stun.l.google.com:19302"]}]
## 延遲幀數：4 幀 @ 60fps ≈ 67ms，可依網路狀況調整
const INPUT_DELAY          := 4
## rollback 最多回溯幾幀（超過此距離的 mismatch 忽略，避免狀態爆炸）
const MAX_ROLLBACK_FRAMES  := 10

# ── 狀態 ─────────────────────────────────────────────────────────────────────
enum Mode { OFFLINE, HOST, CLIENT }
var mode             := Mode.OFFLINE
var local_player_id  := 1   # 1 = P1（HOST）, 2 = P2（CLIENT）

var _game_frame := 0   # 目前要執行的遊戲幀
var _send_frame := 0   # 目前要收集並傳送的輸入幀（超前 INPUT_DELAY）

var _local_inputs:    Dictionary = {}  # frame → PackedByteArray(2 bytes)
var _remote_inputs:   Dictionary = {}  # frame → confirmed remote input
var _predicted_remote: Dictionary = {} # frame → predicted bytes（等候確認）
var _last_remote_input: PackedByteArray = PackedByteArray([0, 0])
var _last_confirmed_remote_frame: int = -1  # 已收到確認輸入的最新幀號
var _pending_rollback_frame: int = -1  # -1 = 無需 rollback

# ── Checksum 驗證（確定性偵測）───────────────────────────────────────────────
var _local_checksums:  Dictionary = {}  # frame → int（本機算出的狀態雜湊）
var _remote_checksums: Dictionary = {}  # frame → int（對方傳來、尚未比對的雜湊）

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
## 透過信令伺服器把武藝選擇傳給對方（WebRTC 連線建立後仍可用 WS 傳）
func send_arts(arts: Array) -> void:
	var msg := JSON.stringify({"type": "arts", "room": _room_code, "arts": arts})
	_ws.send_text(msg)

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

## 每個物理幀呼叫一次，永不 stall。
## checksum：vs_world 在模擬本幀前算好的狀態雜湊，用於確定性偵測。
func tick(local_input: InputState, checksum: int = 0) -> Array:
	var exec  := _game_frame
	var bytes := local_input.to_bytes()
	_local_inputs[_send_frame] = bytes
	_send_packet(_send_frame, bytes, checksum)
	_send_frame += 1

	var EMPTY := PackedByteArray([0, 0])
	var li    := InputState.from_bytes(_local_inputs.get(exec, EMPTY))
	var ri:   InputState

	if mode == Mode.OFFLINE:
		ri = InputState.from_input(2 if local_player_id == 1 else 1)
	else:
		# Checksum：存本幀雜湊，若對方的已先到就比對
		_local_checksums[exec] = checksum
		if _remote_checksums.has(exec):
			_compare_checksums(exec, checksum, _remote_checksums[exec])
			_remote_checksums.erase(exec)

		if exec in _remote_inputs:
			_last_remote_input = _remote_inputs[exec]
		else:
			# 預測：沿用上一幀（比空輸入合理）
			_predicted_remote[exec] = _last_remote_input
		ri = InputState.from_bytes(_last_remote_input)

	_game_frame += 1
	# 清除超出 rollback 視窗的舊紀錄
	var prune := exec - MAX_ROLLBACK_FRAMES
	_predicted_remote.erase(prune)
	_local_checksums.erase(prune)

	return [li, ri] if local_player_id == 1 else [ri, li]

## Rollback 查詢 API（供 vs_world 使用）
func needs_rollback() -> bool:
	return _pending_rollback_frame >= 0

func consume_rollback_frame() -> int:
	var f := _pending_rollback_frame
	_pending_rollback_frame = -1
	return f

func get_game_frame() -> int:
	return _game_frame

## 重模擬用：取得第 frame 幀對方的確認輸入（還沒收到則回傳 null）
func get_confirmed_remote_input(frame: int) -> InputState:
	if not frame in _remote_inputs:
		return null
	return InputState.from_bytes(_remote_inputs[frame])

# ── 內部：幀管理 ──────────────────────────────────────────────────────────────
func _reset() -> void:
	_game_frame = 0
	_send_frame = 0
	_local_inputs.clear()
	_remote_inputs.clear()
	_ws_ready_sent    = false
	_channel_was_open = false
	_ws_ever_opened      = false
	_ws_connect_timer    = 0.0
	_error_emitted       = false
	_predicted_remote.clear()
	_last_remote_input           = PackedByteArray([0, 0])
	_last_confirmed_remote_frame = -1
	_pending_rollback_frame      = -1
	_local_checksums.clear()
	_remote_checksums.clear()
	_rtc     = null
	_channel = null
	_ws.close()
	_ws = WebSocketPeer.new()

# ── 內部：封包 ────────────────────────────────────────────────────────────────
## 封包格式：[u32 frame][u8 in0][u8 in1][u32 checksum] = 10 bytes
func _send_packet(frame: int, bytes: PackedByteArray, checksum: int) -> void:
	if not _channel or _channel.get_ready_state() != 1:   # 1 = STATE_OPEN
		return
	var pkt := PackedByteArray()
	pkt.resize(10)
	pkt.encode_u32(0, frame)
	pkt[4] = bytes[0]
	pkt[5] = bytes[1]
	pkt.encode_u32(6, checksum & 0xFFFFFFFF)
	_channel.put_packet(pkt)

func _recv_packet(pkt: PackedByteArray) -> void:
	if pkt.size() < 10:
		return
	var frame      := pkt.decode_u32(0)
	var confirmed: PackedByteArray = pkt.slice(4, 6)
	var remote_cs  := pkt.decode_u32(6)

	_remote_inputs[frame] = confirmed
	# 更新預測基準：只往前推，舊封包不蓋掉較新的已知狀態
	if frame > _last_confirmed_remote_frame:
		_last_confirmed_remote_frame = frame
		_last_remote_input = confirmed
	# Checksum 比對：本機已算出才能比，否則暫存等 tick() 來比
	if _local_checksums.has(frame):
		_compare_checksums(frame, _local_checksums[frame], remote_cs)
	else:
		_remote_checksums[frame] = remote_cs
	# Rollback 偵測：若此幀曾用預測值模擬，且確認值不同 → 需要回溯
	if frame in _predicted_remote:
		var predicted: PackedByteArray = _predicted_remote[frame]
		_predicted_remote.erase(frame)
		if predicted != confirmed:
			if _pending_rollback_frame < 0 or frame < _pending_rollback_frame:
				_pending_rollback_frame = frame

func _compare_checksums(frame: int, local_cs: int, remote_cs: int) -> void:
	if local_cs != remote_cs:
		push_warning("⚠ DESYNC frame %d | local=0x%08X remote=0x%08X" % [frame, local_cs, remote_cs])
		desync_detected.emit(frame)

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
		"arts":
			var arts: Array = msg.get("arts", [])
			remote_arts_received.emit(arts)
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
