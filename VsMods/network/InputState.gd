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

# === 序列化（2 bytes，傳輸用）======================================
func to_bytes() -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(2)
	var m: int = 0
	if move_dir < -0.1: m |= 1
	if move_dir > 0.1:  m |= 2
	if is_crouch:       m |= 4
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
	s.dodge = Input.is_action_just_pressed(p + "big_dash")
	s.guard = Input.is_action_pressed(p + "small_dash")

	if player_id == 1:
		# P1 滑鼠操作：普攻/技能 = 無修飾左/右鍵；武藝 = E(martial_modifier) + 左/右/中鍵
		var martial := Input.is_action_pressed("martial_modifier")
		s.attack = Input.is_action_just_pressed(p + "attack") and not martial
		s.skill  = Input.is_action_just_pressed(p + "skill")  and not martial
		s.art_1  = Input.is_action_just_pressed("art_1") and martial
		s.art_2  = Input.is_action_just_pressed("art_2") and martial
		s.art_3  = Input.is_action_just_pressed("art_3") and martial
	else:
		s.attack = Input.is_action_just_pressed(p + "attack")
		s.skill  = Input.is_action_just_pressed(p + "skill")
		s.art_1  = Input.is_action_just_pressed(p + "special")
		s.art_2  = Input.is_action_just_pressed(p + "ultimate")
		s.art_3  = Input.is_action_just_pressed(p + "custom")

	return s
