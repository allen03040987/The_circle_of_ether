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
signal remote_arts_received(arts: Array, character_id: String)  # 收到對方的武藝選擇 + 角色
signal remote_arena_received(arena_id: String, confirmed: bool)  # 收到對方的選場地狀態；arena_id 空字串＝對方還沒點過任何地圖，confirmed 區分「正在看」跟「已鎖定」
signal desync_detected(frame: int, fields: Array)  # 兩端 checksum 不符，fields = 分叉欄位名稱清單
signal sync_lost()                   # checksum 連續不符超過閾值 → 狀態已永久分歧，本場作廢
signal opponent_forfeited()          # 對方主動放棄或無法回滾

# ── 設定 ─────────────────────────────────────────────────────────────────────
## 本機測試時用 ws://127.0.0.1:8765，部署後換成 wss://你的伺服器
const SIGNALING_URL := "wss://the-circle-of-ether-signal.onrender.com"
const STUN_SERVERS  := [{"urls": ["stun:stun.l.google.com:19302"]}]
## 延遲幀數：4 幀 @ 60fps ≈ 67ms，可依網路狀況調整
const INPUT_DELAY          := 4
## 每個封包夾帶最近幾幀輸入（冗餘）。DataChannel 不重傳，單發封包遺失會讓
## 該幀輸入永遠無法確認 → 永久 desync；冗餘讓連續 N-1 個封包遺失都能恢復。
const INPUT_REDUNDANCY     := 10
## rollback 最多回溯幾幀（超過此距離的 mismatch 忽略，避免狀態爆炸）
const MAX_ROLLBACK_FRAMES  := 20
## checksum 連續不符幾次視為永久分歧（每 tick 比對一次 ≈ 2 秒）
const CS_FAIL_LIMIT        := 120

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
var _match_seq: int = 0   # 場次序號（0-255 循環）；封包帶著它，收到不同序號的就丟棄

# ── Checksum 驗證（確定性偵測）───────────────────────────────────────────────
## 只登記「已 settled」的幀（雙方都用確認輸入模擬過、不會再被 rollback 改寫），
## 避免拿預測狀態的過時雜湊比對而誤報 DESYNC。settled 幀由 vs_world 決定。
var _local_checksums:  Dictionary = {}  # frame → Array[int]（本機 settled 幀雜湊）
var _remote_checksums: Dictionary = {}  # frame → Array[int]（對方傳來、尚未比對）
var _cs_fail_streak:   int = 0          # 連續比對失敗次數（歸零於任一次全符合）

var _ws               := WebSocketPeer.new()
var _rtc:    Object   = null   # WebRTCPeerConnection（plugin 才有）
var _channel: Object  = null   # WebRTCDataChannel
var _room_code        := ""
var _rtc_available    := false
var _ws_ready_sent    := false
var _channel_was_open := false
var _ws_ever_opened   := false   # 本次連線是否曾達到 STATE_OPEN
var _ws_connect_timer := 0.0     # 自首次嘗試起的總等待時間（秒）
var _ws_retry_timer   := 0.0     # 離上次重試的間隔計時
var _error_emitted    := false   # 避免同一次連線重複發出錯誤
const WS_TIMEOUT      := 90.0    # 等待信令伺服器上線的最長秒數（含冷啟動）
const WS_RETRY_INTERVAL := 4.0   # 502 重試間隔（秒）

## 場次同步：兩側都已進入 vs_world 才開始跑幀 0。
## 避免一方進 vs_world 早，跑了幾百幀後另一方才進入、
## 導致對方的幀 0~N 封包因 seq 不符已全數丟棄，永遠無法確認 → 持續預測誤差。
var _waiting_for_sync:   bool = false
var _sync_tick_counter:  int  = 0   # 限制同步封包發送頻率，避免進 vs_world 瞬間 burst

# ── 初始化 ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_rtc_available = ClassDB.class_exists("WebRTCPeerConnection")
	if not _rtc_available:
		push_warning("VsNetworkManager: webrtc-native 未安裝，聯機功能停用。")

func _process(delta: float) -> void:
	_poll_ws(delta)
	_poll_rtc()

# ── 公開 API ──────────────────────────────────────────────────────────────────
## 透過信令伺服器把武藝選擇＋角色傳給對方（WebRTC 連線建立後仍可用 WS 傳）
func send_arts(arts: Array, character_id: String) -> void:
	var msg := JSON.stringify({"type": "arts", "room": _room_code, "arts": arts, "character": character_id})
	_ws.send_text(msg)

## MapSelectScreen 每次本機點選/確認/取消場地時呼叫——不是只有確認才送，
## 點選（confirmed=false）也要送，讓對方即時看到「你正在看哪張地圖」，不用
## 乾等到確認那一刻才知道。跟 send_arts() 同一個 WS relay 管道（"arena" 已在
## 伺服器白名單，見 CLAUDE.md Signaling server 一節）。
func send_arena_choice(arena_id: String, confirmed: bool) -> void:
	var msg := JSON.stringify({"type": "arena", "room": _room_code, "arena": arena_id, "confirmed": confirmed})
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
## cs_frame / checksums：vs_world 傳入「已 settled 幀」的編號與四個獨立雜湊
## （[cs_pos, cs_vel, cs_hp, cs_state]），-1 = 本幀無可比對的 settled 雜湊。
func tick(local_input: InputState, cs_frame: int = -1, checksums: Array = []) -> Array:
	var bytes := local_input.to_bytes()

	# 同步等待期：兩側都進入 vs_world 才開始跑幀。
	# 送出 7-byte 同步封包（格式：[u8 seq][u32 frame=0][u8 in0][u8 in1]，無 checksum）
	# 讓對方知道我們已準備好，同時不推進 _game_frame / _send_frame。
	# 每 10 tick 才送一次，避免在對方剛進 vs_world 時製造 burst 而引起卡頓。
	if _waiting_for_sync and mode != Mode.OFFLINE:
		# 等待期：不帶真實輸入（frame 0..INPUT_DELAY-1 統一用預填 [0,0]，兩端完全對齊）
		_sync_tick_counter += 1
		if _sync_tick_counter % 10 == 0 and _channel and _channel.get_ready_state() == 1:
			var sync_pkt := PackedByteArray()
			sync_pkt.resize(7)
			sync_pkt[0] = _match_seq & 0xFF
			sync_pkt.encode_u32(1, 0)
			sync_pkt[5] = 0   # ← 固定 [0,0]，不送真實輸入
			sync_pkt[6] = 0
			_channel.put_packet(sync_pkt)
		return []   # 空陣列 → vs_world._physics_process 當幀提前返回，不模擬

	var exec  := _game_frame
	_local_inputs[_send_frame] = bytes
	_send_packet(_send_frame, cs_frame, checksums)
	_send_frame += 1

	var EMPTY := PackedByteArray([0, 0])
	var li:   InputState
	var ri:   InputState

	if mode == Mode.OFFLINE:
		# 離線不需輸入延遲：直接用傳入的當幀輸入，無額外 lag
		li = local_input
		ri = InputState.from_input(2 if local_player_id == 1 else 1)
	else:
		li = InputState.from_bytes(_local_inputs.get(exec, EMPTY))
		# Checksum：登記 settled 幀雜湊，若對方的已先到就比對
		if cs_frame >= 0 and not checksums.is_empty():
			_local_checksums[cs_frame] = checksums
			if _remote_checksums.has(cs_frame):
				_compare_checksums(cs_frame, checksums, _remote_checksums[cs_frame])
				_remote_checksums.erase(cs_frame)

		if exec in _remote_inputs:
			_last_remote_input = _remote_inputs[exec]
		else:
			# 預測：沿用上一幀（比空輸入合理）
			_predicted_remote[exec] = _last_remote_input
		ri = InputState.from_bytes(_last_remote_input)

	_game_frame += 1
	# 只清 checksum（記憶體有限）；_predicted_remote 不在這裡清，
	# 讓它存到 _recv_packet() 收到確認封包時才清——
	# 確保晚到封包（> MAX_ROLLBACK_FRAMES 幀）也能比對出 mismatch 並觸發 rollback/hard desync
	_local_checksums.erase(exec - 3 * MAX_ROLLBACK_FRAMES)
	_remote_checksums.erase(exec - 3 * MAX_ROLLBACK_FRAMES)

	return [li, ri] if local_player_id == 1 else [ri, li]

## Rollback 查詢 API（供 vs_world 使用）
func needs_rollback() -> bool:
	return _pending_rollback_frame >= 0

func consume_rollback_frame() -> int:
	var f := _pending_rollback_frame
	_pending_rollback_frame = -1
	# 記錄近期 rollback（診斷用）：[回溯起點, 執行當下的 game_frame]
	_recent_rollbacks.append([f, _game_frame])
	if _recent_rollbacks.size() > 8:
		_recent_rollbacks.pop_front()
	return f

var _recent_rollbacks: Array = []
func get_recent_rollbacks() -> Array:
	return _recent_rollbacks

func get_game_frame() -> int:
	return _game_frame

## 回傳目前預測深度（幀數）≈ 單向網路延遲 / 16.67ms。
## 值 = _game_frame 領先最後一個已確認遠端幀的幀數；0 = 無延遲。
func get_prediction_depth() -> int:
	if mode == Mode.OFFLINE or _last_confirmed_remote_frame < 0:
		return 0
	return maxi(0, _game_frame - _last_confirmed_remote_frame - 1)

## 回傳目前已 settled 的最新幀（雙方都用確認輸入模擬過、不會再被 rollback 改寫）
## = min(已確認遠端輸入的最新幀, 待處理 rollback 起點-1, 已模擬的最新幀)
## -1 = 尚無 settled 幀（離線模式、或開場還沒收到任何確認輸入）
func get_settled_frame() -> int:
	if mode == Mode.OFFLINE or _last_confirmed_remote_frame < 0:
		return -1
	var s := _last_confirmed_remote_frame
	if _pending_rollback_frame >= 0:
		s = mini(s, _pending_rollback_frame - 1)
	return mini(s, _game_frame - 1)

## 重模擬用：取得第 frame 幀對方的確認輸入（還沒收到則回傳 null）
func get_confirmed_remote_input(frame: int) -> InputState:
	if not frame in _remote_inputs:
		return null
	return InputState.from_bytes(_remote_inputs[frame])

# ── 內部：幀管理 ──────────────────────────────────────────────────────────────
## 每場對局開始時呼叫（保留 WebRTC/WS 連線，只清幀計數與輸入緩衝）
## _reset() 會重置整個連線狀態；此方法用於同一連線的第二場以後
func reset_for_match() -> void:
	_match_seq = (_match_seq + 1) & 0xFF  # 遞增場次序號（0-255 循環），讓舊封包失效
	_game_frame = 0
	_send_frame = INPUT_DELAY   # ← 輸入延遲：從 INPUT_DELAY 幀開始收集真實輸入
	_local_inputs.clear()
	for i in INPUT_DELAY:
		_local_inputs[i] = PackedByteArray([0, 0])  # frame 0..INPUT_DELAY-1 預填空輸入
	_remote_inputs.clear()
	_predicted_remote.clear()
	_pending_rollback_frame      = -1
	_last_remote_input           = PackedByteArray([0, 0])
	_last_confirmed_remote_frame = -1
	_local_checksums.clear()
	_remote_checksums.clear()
	_cs_fail_streak = 0
	_recent_rollbacks.clear()
	# 線上模式：等兩側都進入 vs_world 才開始跑幀（避免幀偏移永久 desync）
	_waiting_for_sync  = (mode != Mode.OFFLINE)
	_sync_tick_counter = 0

func _reset() -> void:
	_game_frame = 0
	_send_frame = INPUT_DELAY   # ← 輸入延遲：從 INPUT_DELAY 幀開始收集真實輸入
	_local_inputs.clear()
	for i in INPUT_DELAY:
		_local_inputs[i] = PackedByteArray([0, 0])  # frame 0..INPUT_DELAY-1 預填空輸入
	_remote_inputs.clear()
	_ws_ready_sent    = false
	_channel_was_open = false
	_ws_ever_opened      = false
	_ws_connect_timer    = 0.0
	_ws_retry_timer      = 0.0
	_error_emitted       = false
	_predicted_remote.clear()
	_last_remote_input           = PackedByteArray([0, 0])
	_last_confirmed_remote_frame = -1
	_pending_rollback_frame      = -1
	_local_checksums.clear()
	_remote_checksums.clear()
	_cs_fail_streak = 0
	_recent_rollbacks.clear()
	# 先正確關閉再清除，確保 GDExtension 完整清理底層資源
	if _channel and _channel.has_method("close"):
		_channel.close()
	if _rtc and _rtc.has_method("close"):
		_rtc.close()
	_rtc     = null
	_channel = null
	_ws.close()
	_ws = WebSocketPeer.new()

# ── 內部：封包 ────────────────────────────────────────────────────────────────
## 告知對方「我放棄/我要離開」，對方顯示獲勝並返回大廳
## 封包格式：[0xFF 0xFF 0xFF 0xFF]（frame 全 1，與正常封包的 10 bytes 大小不同，靠 size 區分）
func send_forfeit() -> void:
	if not _channel or _channel.get_ready_state() != 1:
		return
	_channel.put_packet(PackedByteArray([0xFF, 0xFF, 0xFF, 0xFF]))

## 封包格式（可變長，最小 28 bytes）：
## [u8 seq][u32 frame][u8 n][n×2 bytes 輸入（新→舊：frame, frame-1, ...）]
## [u32 cs_frame（0xFFFFFFFF=無）][u32 cs×4]
## 夾帶最近 n ≤ INPUT_REDUNDANCY 幀輸入冗餘 → 連續 n-1 個封包遺失仍可恢復
func _send_packet(frame: int, cs_frame: int, checksums: Array) -> void:
	if not _channel or _channel.get_ready_state() != 1:   # 1 = STATE_OPEN
		return
	var n := mini(INPUT_REDUNDANCY, frame + 1)
	var pkt := PackedByteArray()
	pkt.resize(6 + 2 * n + 20)
	pkt[0] = _match_seq & 0xFF           # 場次序號（防舊場封包污染新場）
	pkt.encode_u32(1, frame)
	pkt[5] = n
	for i in n:
		var b: PackedByteArray = _local_inputs.get(frame - i, PackedByteArray([0, 0]))
		pkt[6 + 2 * i]     = b[0]
		pkt[6 + 2 * i + 1] = b[1]
	var off := 6 + 2 * n
	pkt.encode_u32(off, cs_frame if cs_frame >= 0 else 0xFFFFFFFF)
	for i in 4:
		pkt.encode_u32(off + 4 + i * 4, checksums[i] if i < checksums.size() else 0)
	_channel.put_packet(pkt)

func _recv_packet(pkt: PackedByteArray) -> void:
	# 放棄封包（4 bytes，全 0xFF）
	if pkt.size() == 4 and pkt.decode_u32(0) == 0xFFFFFFFF:
		opponent_forfeited.emit()
		return
	# 同步封包（7 bytes）：對方確認已進入本場 vs_world
	if pkt.size() == 7:
		if pkt[0] != (_match_seq & 0xFF):
			return
		# 只作「已就緒」訊號，不儲存 input。
		# frame 0..INPUT_DELAY-1 由兩端各自預填 [0,0]，無需封包傳遞。
		if _waiting_for_sync:
			_waiting_for_sync = false   # 對方已就緒，可以開跑了
		return
	# 正常遊戲封包（可變長，最小 28 bytes）
	if pkt.size() < 28:
		return
	# 場次序號不符 → 上一場遺留的舊封包，直接丟棄
	if pkt[0] != (_match_seq & 0xFF):
		return
	# 收到有效遊戲封包也視為對方已就緒（處理同步封包丟失的邊緣情況）
	if _waiting_for_sync:
		_waiting_for_sync = false
	var frame := pkt.decode_u32(1)
	var n     := int(pkt[5])
	if n < 1 or pkt.size() < 6 + 2 * n + 20:
		return   # 格式不符（截斷或損毀）

	# 冗餘輸入：由舊到新掃描（i = n-1 → 0），確保 rollback 起點取到最早的 mismatch
	for i in range(n - 1, -1, -1):
		var f := frame - i
		if f < 0 or _remote_inputs.has(f):
			continue   # 已確認過的幀不重複處理（冗餘封包大多重疊）
		var confirmed: PackedByteArray = pkt.slice(6 + 2 * i, 8 + 2 * i)
		_remote_inputs[f] = confirmed
		# Rollback 偵測：若此幀曾用預測值模擬，且確認值不同 → 需要回溯
		if f in _predicted_remote:
			var predicted: PackedByteArray = _predicted_remote[f]
			_predicted_remote.erase(f)
			if predicted != confirmed:
				if _pending_rollback_frame < 0 or f < _pending_rollback_frame:
					_pending_rollback_frame = f

	# 更新預測基準：只往前推，舊封包不蓋掉較新的已知狀態
	if frame > _last_confirmed_remote_frame:
		_last_confirmed_remote_frame = frame
		_last_remote_input = _remote_inputs[frame]

	# Checksum：封包帶的是對方「已 settled 幀」的雜湊，附明確幀號
	var off        := 6 + 2 * n
	var cs_frame_u := pkt.decode_u32(off)
	if cs_frame_u != 0xFFFFFFFF:
		var cs_frame  := int(cs_frame_u)
		var remote_cs := [
			pkt.decode_u32(off + 4),  pkt.decode_u32(off + 8),
			pkt.decode_u32(off + 12), pkt.decode_u32(off + 16),
		]
		if _local_checksums.has(cs_frame):
			_compare_checksums(cs_frame, _local_checksums[cs_frame], remote_cs)
			_remote_checksums.erase(cs_frame)
		else:
			_remote_checksums[cs_frame] = remote_cs   # 本機還沒 settled，暫存等 tick() 比

const _CS_FIELDS := ["位置", "速度", "血量/能量/回合", "狀態"]

func _compare_checksums(frame: int, local_cs: Array, remote_cs: Array) -> void:
	var diffs: Array[String] = []
	for i in 4:
		if local_cs[i] != remote_cs[i]:
			diffs.append(_CS_FIELDS[i])
	if diffs.is_empty():
		_cs_fail_streak = 0
		return
	_cs_fail_streak += 1
	push_warning("⚠ DESYNC frame %d: %s（連續第 %d 次）" % [frame, ", ".join(diffs), _cs_fail_streak])
	desync_detected.emit(frame, diffs)
	# settled 幀不該分歧；連續分歧 = 狀態已永久發散，繼續打只會兩邊各玩各的
	if _cs_fail_streak == CS_FAIL_LIMIT:
		sync_lost.emit()

# ── 內部：WebSocket 信令 ──────────────────────────────────────────────────────
func _ws_connect() -> void:
	# STATE_CLOSED 後 WebSocketPeer 不可重用，每次重試都需重建
	_ws = WebSocketPeer.new()
	_ws_ready_sent = false
	_ws.connect_to_url(SIGNALING_URL)

func _poll_ws(delta: float = 0.0) -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	match state:
		WebSocketPeer.STATE_CONNECTING:
			if not _ws_ever_opened and mode != Mode.OFFLINE:
				_ws_connect_timer += delta   # 與 STATE_CLOSED 重試時共用同一個計時器
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
			# WebSocket 是信令通道；WebRTC DataChannel 才是遊戲通道。
			# 只有 DataChannel 也不在線時才算真正斷線，避免 Render.com 閒置關 WS
			# 導致 _channel_was_open 被誤設成 false → connected/disconnected 每幀輪流觸發。
			if _channel_was_open and (not _channel or _channel.get_ready_state() != 1):
				_channel_was_open = false
				disconnected.emit()
			elif not _ws_ever_opened and mode != Mode.OFFLINE and not _error_emitted:
				# 可能是 Render 冷啟動 502 → 在 WS_TIMEOUT 內定時重試
				_ws_connect_timer += delta
				if _ws_connect_timer >= WS_TIMEOUT:
					_error_emitted = true
					connection_error.emit("信令伺服器連線逾時（%.0f秒），請稍後再試" % WS_TIMEOUT)
				else:
					_ws_retry_timer += delta
					if _ws_retry_timer >= WS_RETRY_INTERVAL:
						_ws_retry_timer = 0.0
						_ws_connect()   # 重建 WebSocket 並重試握手

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
			var character_id: String = msg.get("character", VsCharacterRegistry.DEFAULT_CHARACTER)
			remote_arts_received.emit(arts, character_id)
		"arena":
			remote_arena_received.emit(msg.get("arena", ""), msg.get("confirmed", false))
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
