class_name VsPlayer
extends CharacterBody2D

# ── 體質效果枚舉 ──────────────────────────────────────────────────────────────
enum ArmorTier {
	NONE,        # 正常
	HYPER,       # 霸體：免疫非破霸攻擊的擊退/硬直
	STRONG_HYPER # 強霸體：免疫非強破霸攻擊的擊退/硬直，並獲得 50% 減傷
}

# ── 設定 ─────────────────────────────────────────────────────────────────────
@export var player_id:       int   = 1
@export var max_hp:          float = 1000.0
# 武藝能量：脫戰後每秒恢復，上限 50
@export var max_arts_energy: float = 50.0
@export var arts_regen_rate: float = 10.0   # 每秒回復量（apply_arts_bonus 會疊加）
# 衝刺能量：永遠自動恢復，上限 100
@export var max_dash_energy: float = 100.0
@export var dash_regen_rate: float = 10.0   # 每秒回復量（永遠生效）

# ── 武藝槽（由 vs_world 從 VsGameManager 注入）──────────────────────────────
var art_slots: Array[String] = ["", "", ""]

# ── 數值 ─────────────────────────────────────────────────────────────────────
var hp:          float
var arts_energy: float
var dash_energy: float
var facing_dir:  int = 1    # 1 = 右, -1 = 左
## 確定性地面旗標：由 _move_deterministic 移動後以 test_move()（無狀態位置查詢）
## 更新，隨快照保存還原。所有模擬邏輯一律讀 grounded（VsPlayerState._grounded()），
## 嚴禁 is_on_floor()——它依賴 move_and_slide 的內部記憶，rollback 下不可靠。
var grounded:    bool = true

# ── 戰鬥 ─────────────────────────────────────────────────────────────────────
var invincible_time_left:  float      = 0.0   # 剩餘無敵秒數（以 delta 遞減）
var post_dash_armor_left:  float      = 0.0   # 衝刺後強霸體倒計（秒）
var pending_hit:           Dictionary = {}    # 本幀設定，下幀處理（空 = 無）
var queued_hitstun:        float      = 0.4   # VsHurt.enter() 讀取的硬直時長
var last_input:            InputState         # 當幀輸入備份（供 enter() 讀取方向）

# ── 節點 ─────────────────────────────────────────────────────────────────────
@onready var state_machine: VsStateMachine  = $VsStateMachine
@onready var anim_player:  AnimationPlayer = $AnimationPlayer
@onready var graphics:     Node2D          = $Graphics
@onready var hurtbox:      VsHurtbox       = $Graphics/VsHurtbox
var hitbox: VsHitbox  # 由 _ready() 程式碼建立

# 脫戰計時器：用 float + 模擬 delta，不用 Timer 節點（Timer 用真實時間，rollback 下會飄）
const OUT_OF_COMBAT_DELAY := 2.0
var out_of_combat_left: float = 0.0

# ── 初始化 ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	hp          = max_hp
	arts_energy = max_arts_energy
	dash_energy = max_dash_energy
	_build_hitbox()
	_register_attack_state()
	state_machine.init(self, &"vsidle")
	hurtbox.hurt.connect(_on_hurtbox_hurt)

func _build_hitbox() -> void:
	var hb := VsHitbox.new()
	hb.name = "VsHitbox"
	hb.owner_player = self   # 受擊方向計算用（模擬資料，不依賴 scene tree transform）
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
	_move_deterministic(delta)
	graphics.scale.x = facing_dir

## 移動嚴禁用 move_and_slide()：它內部有「上一幀是否在地面」的隱藏記憶
## （地面吸附機制），rollback 還原 position 後該記憶仍是回滾前的舊值，
## 重模擬的移動結果會與直跑不同（實測：一邊多施一次重力 → y 永久分歧）。
## move_and_collide() 與 test_move() 都是無狀態查詢，結果只取決於當前
## position/velocity，且 motion 向量顯式傳入，不依賴引擎真實 delta。
func _move_deterministic(sim_delta: float) -> void:
	var col := move_and_collide(velocity * sim_delta)
	if col:
		var n := col.get_normal()
		if absf(n.y) > 0.7:
			# 地板 / 天花板：垂直速度歸零，剩餘位移只保留水平分量
			velocity.y = 0.0
			var rem := col.get_remainder()
			rem.y = 0.0
			if rem != Vector2.ZERO:
				move_and_collide(rem)
		else:
			# 牆壁：水平速度歸零，剩餘位移只保留垂直分量
			velocity.x = 0.0
			var rem := col.get_remainder()
			rem.x = 0.0
			if rem != Vector2.ZERO:
				move_and_collide(rem)
	# 消除碰撞求解的浮點雜訊：position 精度對齊 checksum（0.01px）
	# 這樣任何真實的位置分叉都至少差 0.01px，保證被 checksum 抓到
	position = position.snapped(Vector2(0.01, 0.01))
	# 地面旗標唯一更新點：純位置查詢（往下 0.1px 是否碰撞），無隱藏狀態，
	# 隨快照保存 → rollback 重模擬讀到正確值
	grounded = test_move(global_transform, Vector2(0.0, 0.1))

# ── 能量 ─────────────────────────────────────────────────────────────────────
## 消耗衝刺能量（30點/次）；失敗回傳 false
func use_dash_energy(amount: float) -> bool:
	if dash_energy < amount:
		return false
	dash_energy -= amount
	return true

## 消耗武藝能量；失敗回傳 false，成功同時重置脫戰計時
func use_arts_energy(amount: float) -> bool:
	if arts_energy < amount:
		return false
	arts_energy -= amount
	out_of_combat_left = OUT_OF_COMBAT_DELAY
	return true

func mark_in_combat() -> void:
	out_of_combat_left = OUT_OF_COMBAT_DELAY

func _update_energy_regen(delta: float) -> void:
	# 衝刺能量：永遠恢復
	dash_energy = minf(dash_energy + dash_regen_rate * delta, max_dash_energy)
	# 武藝能量：脫戰後恢復
	if out_of_combat_left > 0.0:
		out_of_combat_left = maxf(out_of_combat_left - delta, 0.0)
	else:
		arts_energy = minf(arts_energy + arts_regen_rate * delta, max_arts_energy)
	# 衝刺後強霸體倒計
	if post_dash_armor_left > 0.0:
		post_dash_armor_left = maxf(post_dash_armor_left - delta, 0.0)

# ── 體質效果 ──────────────────────────────────────────────────────────────────
## 根據當前狀態與計時器計算實際 ArmorTier（衍生值，不儲存）
func get_armor_tier() -> ArmorTier:
	var cur := state_machine.current_state
	if cur is VsGuard:
		return ArmorTier.STRONG_HYPER
	if post_dash_armor_left > 0.0:
		return ArmorTier.STRONG_HYPER
	return ArmorTier.NONE

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
		return

	if is_invincible(): return

	# 計算攻擊方向（dir_x：受擊者相對攻擊來源的方向）
	# 一律用模擬資料 position，不用 global_position（scene tree 快取在
	# rollback 重模擬中可能過期，會算出不同的擊退方向 → desync）
	var src_x := hitbox.owner_player.position.x if hitbox.owner_player else position.x
	var dir_x := int(sign(src_x - position.x))
	if dir_x == 0: dir_x = -facing_dir

	# 防禦：交由 VsGuard 處理（強霸體減傷 + 強破霸破防）
	if cur is VsGuard:
		(cur as VsGuard).on_guard_hit(hitbox)
		return

	# 體質效果判定
	var at := get_armor_tier()
	var bl := hitbox.break_level

	var allows_hitstun: bool
	var dmg_mult: float
	match at:
		ArmorTier.STRONG_HYPER:
			allows_hitstun = (bl == VsHitbox.BreakLevel.STRONG_ARMOR_BREAK)
			dmg_mult = 1.0 if bl == VsHitbox.BreakLevel.STRONG_ARMOR_BREAK else 0.5
		ArmorTier.HYPER:
			allows_hitstun = (bl >= VsHitbox.BreakLevel.ARMOR_BREAK)
			dmg_mult = 1.0
		_:  # NONE
			allows_hitstun = true
			dmg_mult = 1.0

	if not allows_hitstun:
		# 霸體吸收擊退/硬直；仍承受傷害（可能有 50% 減傷）
		hp = maxf(hp - hitbox.damage * dmg_mult, 0.0)
		mark_in_combat()
		return

	# 一般受傷：排隊（下幀 _apply_pending_hit 處理）
	pending_hit = {
		"damage":           hitbox.damage * dmg_mult,
		"hitstun_time":     hitbox.hitstun_time,
		"knockback":        Vector2(hitbox.knockback.x * dir_x, hitbox.knockback.y),
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
		if cur is VsKnockdown:
			cur.enter(&"vsknockdown")
		else:
			state_machine.transition_to(&"vsknockdown")
	else:
		if cur is VsHurt:
			cur.enter(&"vshurt")
		elif not (cur is VsKnockdown):
			state_machine.transition_to(&"vshurt")

# ── 受傷（直接扣血，不帶硬直，外部工具用）───────────────────────────────────
func take_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)

# ── Rollback：快照 / 還原 / 動畫同步 ─────────────────────────────────────────
func save_state() -> Dictionary:
	var cur := state_machine.current_state
	return {
		"pos":    position,
		"vel":    velocity,
		"hp":     hp,
		"arts_e": arts_energy,
		"dash_e": dash_energy,
		"facing": facing_dir,
		"gnd":    grounded,
		"inv":    invincible_time_left,
		"pda":    post_dash_armor_left,
		"phit":   pending_hit.duplicate(true),
		"qhit":   queued_hitstun,
		"ctimer": out_of_combat_left,
		"sname":  state_machine.current_state_name,
		"sdata":  cur.save_state() if cur else {},
	}

func restore_state(s: Dictionary) -> void:
	position             = s["pos"]
	velocity             = s["vel"]
	hp                   = s["hp"]
	arts_energy          = s["arts_e"]
	dash_energy          = s["dash_e"]
	facing_dir           = s["facing"]
	grounded             = s["gnd"]
	invincible_time_left = s["inv"]
	post_dash_armor_left = s["pda"]
	pending_hit          = s["phit"].duplicate(true)
	queued_hitstun       = s["qhit"]
	out_of_combat_left   = s["ctimer"]
	graphics.scale.x     = facing_dir
	hitbox.monitoring    = false
	hitbox.reset_hits()
	state_machine.set_state_quiet(s["sname"])
	if state_machine.current_state:
		state_machine.current_state.restore_state(s["sdata"])

func sync_anim_to_state() -> void:
	if state_machine.current_state:
		state_machine.current_state.sync_anim()

# ── 武藝加成（vs_world 注入 art_slots 後呼叫）────────────────────────────────
func apply_arts_bonus() -> void:
	var empty := art_slots.count("")
	arts_regen_rate += empty * VsGameManager.EMPTY_SLOT_REGEN_BONUS
