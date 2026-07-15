class_name VsPlayer
extends CharacterBody2D

# ── 設定 ─────────────────────────────────────────────────────────────────────
@export var player_id:         int   = 1
@export var max_hp:            float = 1000.0
@export var max_energy:        float = 100.0
@export var energy_regen_rate: float = 10.0    # 每秒回復量（apply_arts_bonus 會疊加）

# ── 武藝槽（由 vs_world 從 VsGameManager 注入）──────────────────────────────
var art_slots: Array[String] = ["", "", ""]

# ── 數值 ─────────────────────────────────────────────────────────────────────
var hp:         float
var energy:     float
var facing_dir: int = 1    # 1 = 右, -1 = 左

# ── 戰鬥 ─────────────────────────────────────────────────────────────────────
var invincible_time_left: float    = 0.0   # 剩餘無敵秒數（以 delta 遞減）
var pending_hit:          Dictionary = {}  # 本幀設定，下幀處理（空 = 無）
var queued_hitstun:       float    = 0.4   # VsHurt.enter() 讀取的硬直時長
var last_input:           InputState       # 當幀輸入備份（供 enter() 讀取方向）

# ── 節點 ─────────────────────────────────────────────────────────────────────
@onready var state_machine:       VsStateMachine  = $VsStateMachine
@onready var anim_player:         AnimationPlayer = $AnimationPlayer
@onready var graphics:            Node2D          = $Graphics
@onready var hurtbox:             VsHurtbox       = $Graphics/VsHurtbox
@onready var out_of_combat_timer: Timer           = $OutOfCombatTimer
var hitbox: VsHitbox  # 由 _ready() 程式碼建立

# ── 初始化 ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	hp     = max_hp
	energy = max_energy
	_build_hitbox()
	_register_attack_state()
	state_machine.init(self, &"vsidle")
	hurtbox.hurt.connect(_on_hurtbox_hurt)

func _build_hitbox() -> void:
	var hb := VsHitbox.new()
	hb.name = "VsHitbox"
	hb.position = Vector2(30, -20)
	hb.collision_layer = 1024
	hb.collision_mask  = 512
	hb.monitoring      = false
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size    = Vector2(30, 24)
	cs.shape   = rs
	hb.add_child(cs)
	graphics.add_child(hb)
	hitbox = hb

func _register_attack_state() -> void:
	var va := VsAttack.new()
	va.name = "VsAttack"
	state_machine.add_child(va)
	state_machine.states[&"vsattack"] = va

# ── 主更新（由 vs_world 每幀呼叫）────────────────────────────────────────────
func apply_input(delta: float, input: InputState) -> void:
	last_input = input
	_update_energy_regen(delta)
	_tick_invincibility(delta)
	_apply_pending_hit()
	state_machine.physics_update(delta, input)
	move_and_slide()
	graphics.scale.x = facing_dir

# ── 能量 ─────────────────────────────────────────────────────────────────────
func use_energy(amount: float) -> bool:
	if energy < amount:
		return false
	energy -= amount
	out_of_combat_timer.start()
	return true

func mark_in_combat() -> void:
	out_of_combat_timer.start()

func _update_energy_regen(delta: float) -> void:
	if out_of_combat_timer.is_stopped():
		energy = minf(energy + energy_regen_rate * delta, max_energy)

# ── 無敵 ─────────────────────────────────────────────────────────────────────
func _tick_invincibility(delta: float) -> void:
	if invincible_time_left > 0.0:
		invincible_time_left = maxf(invincible_time_left - delta, 0.0)

func is_invincible() -> bool:
	return invincible_time_left > 0.0

# ── 受傷信號（Area 重疊時由 VsHurtbox 觸發）─────────────────────────────────
func _on_hurtbox_hurt(hitbox: VsHitbox) -> void:
	var cur := state_machine.current_state

	# 完美閃避：判定窗（VsDodge 前 PERFECT_WINDOW 秒，同時 invincible_time_left > 0）
	if cur is VsDodge and invincible_time_left > 0.0:
		(cur as VsDodge).trigger_perfect_dodge()
		return  # 無敵期間不受傷

	if is_invincible(): return

	# 防禦：交由 VsGuard 處理碎片 / 破防
	if cur is VsGuard:
		(cur as VsGuard).on_guard_hit(hitbox)
		return

	# 一般受傷：計算擊退方向並排隊（下幀 _apply_pending_hit 處理）
	var src_pos := hitbox.global_position
	if is_instance_valid(hitbox.owner):
		src_pos = hitbox.owner.global_position
	var dir_x := int(sign(src_pos.x - global_position.x))
	if dir_x == 0: dir_x = -facing_dir

	pending_hit = {
		"damage":          hitbox.damage,
		"hitstun_time":    hitbox.hitstun_time,
		"knockback":       Vector2(hitbox.knockback.x * dir_x, hitbox.knockback.y),
		"causes_knockdown": hitbox.causes_knockdown,
	}

func _apply_pending_hit() -> void:
	if pending_hit.is_empty(): return
	var hit  := pending_hit
	pending_hit = {}

	hp            = maxf(hp - hit["damage"], 0.0)
	velocity      = hit["knockback"]
	queued_hitstun = hit["hitstun_time"]
	mark_in_combat()

	var cur := state_machine.current_state
	if hit["causes_knockdown"]:
		# 倒地：允許在 VsKnockdown 內重啟
		if cur is VsKnockdown:
			cur.enter(&"vsknockdown")
		else:
			state_machine.transition_to(&"vsknockdown")
	else:
		# 硬直：若已在 VsHurt 內，繞過防重入直接重啟（模仿主遊戲 Hurt.gd 做法）
		if cur is VsHurt:
			cur.enter(&"vshurt")
		elif not (cur is VsKnockdown):  # 倒地中忽略非倒地攻擊（OTG 需另行設計）
			state_machine.transition_to(&"vshurt")

# ── 受傷（直接扣血，不帶硬直，外部工具用）───────────────────────────────────
func take_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)

# ── 武藝加成（vs_world 注入 art_slots 後呼叫）────────────────────────────────
func apply_arts_bonus() -> void:
	var empty := art_slots.count("")
	energy_regen_rate += empty * VsGameManager.EMPTY_SLOT_REGEN_BONUS
