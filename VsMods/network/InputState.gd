class_name InputState
extends RefCounted

# === 輸入欄位 ===
var move_dir: float = 0.0   # -1.0 左, 0.0 中立, 1.0 右
var is_crouch: bool = false
var jump: bool = false
var attack: bool = false    # 普攻
var skill: bool = false     # 技能
var art_1: bool = false     # 武藝 1
var art_2: bool = false     # 武藝 2
var art_3: bool = false     # 武藝 3
var dodge: bool = false     # 閃避
var guard: bool = false     # 防禦（長按）
## 非戰鬥選單確認（例如回合間重選武藝的「確認」鍵）。刻意跟其他戰鬥動作走
## 同一份 InputState/rollback 管線，不是另開一條 WS 側路——「雙方都確認了才
## 進下一回合」這件事需要兩端在同一個模擬幀達成一致，如果直接用 WS 訊息到達
## 時間去觸發回合轉場，兩端收到的真實時間點必有落差，回合重置就會在不同幀
## 發生 → checksum 分歧。走這條輸入管線就自動獲得跟其他輸入一樣的確定性
## 保證（延遲＋預測＋rollback 修正）。見 VsRoundManager._tick_arts_reselect()。
var confirm: bool = false

# === 序列化（2 bytes，傳輸用）======================================
func to_bytes() -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(2)
	var m: int = 0
	if move_dir < -0.1: m |= 1
	if move_dir > 0.1:  m |= 2
	if is_crouch:       m |= 4
	if confirm:         m |= 8
	buf[0] = m
	var a: int = 0
	if jump:   a |= 1 << 0
	if attack: a |= 1 << 1
	if skill:  a |= 1 << 2
	if art_1:  a |= 1 << 3
	if art_2:  a |= 1 << 4
	if art_3:  a |= 1 << 5
	if dodge:  a |= 1 << 6
	if guard:  a |= 1 << 7
	buf[1] = a
	return buf

static func from_bytes(buf: PackedByteArray) -> InputState:
	var s := InputState.new()
	if buf.size() < 2:
		return s
	var m := buf[0]
	var a := buf[1]
	if   m & 1: s.move_dir = -1.0
	elif m & 2: s.move_dir =  1.0
	s.is_crouch = bool(m & 4)
	s.confirm   = bool(m & 8)
	s.jump   = bool(a & (1 << 0))
	s.attack = bool(a & (1 << 1))
	s.skill  = bool(a & (1 << 2))
	s.art_1  = bool(a & (1 << 3))
	s.art_2  = bool(a & (1 << 4))
	s.art_3  = bool(a & (1 << 5))
	s.dodge  = bool(a & (1 << 6))
	s.guard  = bool(a & (1 << 7))
	return s

# === 從 Godot Input 讀取（player_id: 1 或 2）======================
static func from_input(player_id: int) -> InputState:
	var s := InputState.new()
	var p := "p1_" if player_id == 1 else "p2_"
	if Input.is_action_pressed(p + "left"):  s.move_dir -= 1.0
	if Input.is_action_pressed(p + "right"): s.move_dir += 1.0
	s.is_crouch = Input.is_action_pressed(p + "down")
	s.jump  = Input.is_action_just_pressed(p + "jump")

	if player_id == 1:
		# P1 滑鼠操作：普攻/技能/閃避/防禦 = 無修飾鍵；武藝 = E(martial_modifier) + 同一批鍵。
		# 閃避/防禦跟普攻/技能同待遇（and not martial）——這樣任何一個動作的按鍵
		# 都能被使用者重新綁定成跟某個武藝槽重疊，靠 E 消歧義。⚠ 代價：只要
		# 按著 E（哪怕沒重疊綁定任何鍵），閃避/防禦這一幀就會暫時發不出來——
		# 使用者 2026-07-20 明確接受這個取捨，見 InputState.gd 呼叫端的說明。
		# 這跟「閃避永遠是最高優先權、不能被其他規則擋掉」的全域規則不衝突：
		# 那條規則講的是閃避一旦被偵測到就能打斷任何狀態，不保證閃避「一定會
		# 被偵測到」——這裡影響的是偵測本身，不是偵測到之後的優先權。
		var martial := Input.is_action_pressed("martial_modifier")
		s.dodge  = Input.is_action_just_pressed(p + "big_dash")   and not martial
		s.guard  = Input.is_action_pressed(p + "small_dash")      and not martial
		s.attack = Input.is_action_just_pressed(p + "attack") and not martial
		s.skill  = Input.is_action_just_pressed(p + "skill")  and not martial
		s.art_1  = Input.is_action_just_pressed("art_1") and martial
		s.art_2  = Input.is_action_just_pressed("art_2") and martial
		s.art_3  = Input.is_action_just_pressed("art_3") and martial
	else:
		s.dodge  = Input.is_action_just_pressed(p + "big_dash")
		s.guard  = Input.is_action_pressed(p + "small_dash")
		s.attack = Input.is_action_just_pressed(p + "attack")
		s.skill  = Input.is_action_just_pressed(p + "skill")
		s.art_1  = Input.is_action_just_pressed(p + "special")
		s.art_2  = Input.is_action_just_pressed(p + "ultimate")
		s.art_3  = Input.is_action_just_pressed(p + "custom")

	# 選單確認：UI 按鈕點擊（不是鍵盤/滑鼠 action）沒辦法用 is_action_just_pressed
	# 偵測，改成 VsGameManager 上的一次性旗標——ArtsReselectOverlay 的確認鍵
	# 點擊時設 true，這裡讀到就消費掉（清回 false），模擬「這一幀剛按下」的
	# just_pressed 語意，讓它能正確搭上這一幀的 InputState 送出。
	if player_id == 1 and VsGameManager.pending_confirm_1:
		s.confirm = true
		VsGameManager.pending_confirm_1 = false
	elif player_id == 2 and VsGameManager.pending_confirm_2:
		s.confirm = true
		VsGameManager.pending_confirm_2 = false

	return s
