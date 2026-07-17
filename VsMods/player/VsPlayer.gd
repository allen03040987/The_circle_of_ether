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
## 連段窗口旗標：由攻擊動畫的 `.:can_combo` 軌道開關（主遊戲同款做法），
## 程式碼不要直接排程它——時間點去動畫軌道上調。VsAttack 的 enter/exit 會歸零。
var can_combo:   bool = false

# ── 戰鬥 ─────────────────────────────────────────────────────────────────────
var invincible_time_left:  float      = 0.0   # 剩餘無敵秒數（以 delta 遞減）
var post_dash_armor_left:  float      = 0.0   # 衝刺後強霸體倒計（秒）
var pending_hit:           Dictionary = {}    # 本幀設定，下幀處理（空 = 無）
var queued_hitstun:        float      = 0.4   # VsHurt.enter() 讀取的硬直時長
var queued_knockdown:      bool       = false # 落地屬性（y=0）：VsHurt 硬直完進倒地
var last_input:            InputState         # 當幀輸入備份（供 enter() 讀取方向）

# ── 節點 ─────────────────────────────────────────────────────────────────────
@onready var state_machine: VsStateMachine  = $VsStateMachine
@onready var anim_player:  AnimationPlayer = $AnimationPlayer
@onready var graphics:     Node2D          = $Graphics
@onready var hurtbox:      VsHurtbox       = $Graphics/VsHurtbox
## Graphics 下所有 VsHitbox（每招一顆：HitboxA1~A5...，大小/位置/傷害數值都在
## 編輯器節點上調），開關由各攻擊動畫的 monitoring 軌道驅動，_ready() 收集
var hitboxes: Array[VsHitbox] = []
## 對手參照（由 vs_world._spawn_players 注入）——回到 idle 自動面向對方用
var opponent: VsPlayer = null

# 脫戰計時器：用 float + 模擬 delta，不用 Timer 節點（Timer 用真實時間，rollback 下會飄）
const OUT_OF_COMBAT_DELAY := 2.0
var out_of_combat_left: float = 0.0

# ── 初始化 ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	hp          = max_hp
	arts_energy = max_arts_energy
	dash_energy = max_dash_energy
	# MANUAL 模式在運行時才切（rollback 需要：動畫由 apply_input 以模擬 delta 推進）。
	# 不寫死在 tscn——編輯器預覽在 MANUAL 模式下不會推進，動畫面板會壞掉不能播
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for c in graphics.get_children():
		if c is VsHitbox:
			c.owner_player = self   # 受擊方向計算用（模擬資料，不依賴 scene tree transform）
			hitboxes.append(c)
	state_machine.init(self, &"vsidle")
	hurtbox.hurt.connect(_on_hurtbox_hurt)

# ── 主更新（由 vs_world 每幀呼叫）────────────────────────────────────────────
func apply_input(delta: float, input: InputState) -> void:
	last_input = input
	_update_energy_regen(delta)
	_tick_invincibility(delta)
	_apply_pending_hit()
	# 動畫用模擬 delta 手動推進（AnimationPlayer 是 MANUAL 模式）——
	# 攻擊動畫的 can_combo / hitbox monitoring 軌道值因此是模擬時間的純函數，
	# rollback 重模擬每幀都會重跑軌道，兩端保證一致。放在狀態更新之前，
	# 讓「動畫時間」與各狀態的 elapsed 對齊（enter 播動畫的下一幀兩者同為 1 delta）
	anim_player.advance(delta)
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

	# 落地規則分流：
	#   落地屬性 + y<0 擊退 → 擊飛（忽略硬直，落地那一刻直接進倒地）
	#   落地屬性 + y=0 擊退 → 正常硬直，硬直結束後進倒地（queued_knockdown）
	#   無落地屬性          → 正常硬直
	var cur := state_machine.current_state
	var kb: Vector2 = hit["knockback"]
	if hit["causes_knockdown"] and kb.y < 0.0:
		if cur is VsLaunched:
			cur.enter(&"vslaunched")   # 空中再次被擊飛（juggle）：重入刷新
		else:
			state_machine.transition_to(&"vslaunched")
	elif cur is VsKnockdown or cur is VsLaunched:
		pass  # 倒地（OTG）/擊飛中被普通攻擊打到：只吃傷害與擊退速度，不改變狀態
	else:
		queued_knockdown = hit["causes_knockdown"]
		if cur is VsHurt:
			cur.enter(&"vshurt")
		else:
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
		"cc":     can_combo,
		"inv":    invincible_time_left,
		"pda":    post_dash_armor_left,
		"phit":   pending_hit.duplicate(true),
		"qhit":   queued_hitstun,
		"qkd":    queued_knockdown,
		"ctimer": out_of_combat_left,
		# 每顆判定框的 [monitoring, has_hit]：monitoring 平時由動畫軌道驅動，
		# has_hit 防 rollback 重模擬時同一攻擊窗重複命中
		"hbs":    hitboxes.map(func(h: VsHitbox) -> Array: return [h.monitoring, h.has_hit]),
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
	can_combo            = s["cc"]
	invincible_time_left = s["inv"]
	post_dash_armor_left = s["pda"]
	pending_hit          = s["phit"].duplicate(true)
	queued_hitstun       = s["qhit"]
	queued_knockdown     = s["qkd"]
	out_of_combat_left   = s["ctimer"]
	graphics.scale.x     = facing_dir
	var hbs: Array = s["hbs"]
	for i in hitboxes.size():
		hitboxes[i].monitoring = hbs[i][0]
		hitboxes[i].has_hit    = hbs[i][1]
		hitboxes[i].hit_targets.clear()
	state_machine.set_state_quiet(s["sname"])
	if state_machine.current_state:
		state_machine.current_state.restore_state(s["sdata"])
	# 動畫時間必須立刻對齊還原後的狀態：軌道值由 advance() 依動畫時間驅動，
	# 時間不對的話重模擬會漏觸發/多觸發 can_combo、hitbox monitoring 的 key
	sync_anim_to_state()

func sync_anim_to_state() -> void:
	if state_machine.current_state:
		state_machine.current_state.sync_anim()

# ── 武藝加成（vs_world 注入 art_slots 後呼叫）────────────────────────────────
func apply_arts_bonus() -> void:
	var empty := art_slots.count("")
	arts_regen_rate += empty * VsGameManager.EMPTY_SLOT_REGEN_BONUS

# ==========================================
# 🎨 狀態輪廓描邊（主遊戲 StatusOutline 同款）：藍=霸體、黃=強霸體、紅=無敵
# 優先權：無敵 > 強霸體 > 霸體。純視覺——每個渲染幀從「當下模擬狀態」衍生，
# 不參與模擬、不進快照，rollback 無關（tween 用真實時間也沒關係）。
# ==========================================
const OUTLINE_SHADER = preload("res://classes/StatusOutline.gdshader")
const OUTLINE_COLOR_HYPER        := Color(0.5, 0.8, 1.4, 0.7)  ## 藍（低調）
const OUTLINE_COLOR_STRONG_HYPER := Color(1.4, 1.1, 0.0, 1.0)  ## 黃（HDR 飽和）
const OUTLINE_COLOR_INVINCIBLE   := Color(1.0, 0.15, 0.15, 1.0) ## 紅
const OUTLINE_FADE_DURATION: float = 0.15

var _outline_mat:      ShaderMaterial = null
var _outline_original: Material       = null
var _outline_tween:    Tween          = null
var _outline_state:    String         = ""  ## "" / "invincible" / "strong_hyper" / "hyper"

func _process(_delta: float) -> void:
	_update_status_outline()

func _update_status_outline() -> void:
	var desired := ""
	# 跟主遊戲共用同一個純視覺開關（設定選單的「狀態輪廓」）
	if Game.config_enable_status_outline:
		if is_invincible():
			desired = "invincible"
		else:
			match get_armor_tier():
				ArmorTier.STRONG_HYPER: desired = "strong_hyper"
				ArmorTier.HYPER:        desired = "hyper"

	if desired != _outline_state:
		_outline_state = desired
		match desired:
			"invincible":   _apply_outline_color(OUTLINE_COLOR_INVINCIBLE)
			"strong_hyper": _apply_outline_color(OUTLINE_COLOR_STRONG_HYPER)
			"hyper":        _apply_outline_color(OUTLINE_COLOR_HYPER)
			_:              _clear_outline()

	# spritesheet 每幀重算「目前這一格」的 UV 範圍，避免描邊採樣到隔壁格（主遊戲同款處理）
	if is_instance_valid(_outline_mat) and _outline_state != "":
		_sync_outline_frame_bounds()

func _apply_outline_color(color: Color) -> void:
	if _outline_mat == null:
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = OUTLINE_SHADER
	_outline_mat.set_shader_parameter("line_color", color)
	_outline_mat.set_shader_parameter("outline_alpha", 0.0)
	var sprite := graphics.get_node_or_null("Sprite2D")
	if is_instance_valid(sprite):
		if sprite.material != _outline_mat:
			_outline_original = sprite.material
			sprite.material = _outline_mat
	if is_instance_valid(_outline_tween) and _outline_tween.is_valid(): _outline_tween.kill()
	_outline_tween = create_tween()
	_outline_tween.tween_property(_outline_mat, "shader_parameter/outline_alpha", 1.0, OUTLINE_FADE_DURATION)

func _clear_outline() -> void:
	if not is_instance_valid(_outline_mat): return
	if is_instance_valid(_outline_tween) and _outline_tween.is_valid(): _outline_tween.kill()
	_outline_tween = create_tween()
	_outline_tween.tween_property(_outline_mat, "shader_parameter/outline_alpha", 0.0, OUTLINE_FADE_DURATION)
	_outline_tween.tween_callback(_restore_outline_material)

func _restore_outline_material() -> void:
	var sprite := graphics.get_node_or_null("Sprite2D")
	if is_instance_valid(sprite) and sprite.material == _outline_mat:
		sprite.material = _outline_original
	_outline_original = null

func _sync_outline_frame_bounds() -> void:
	var sprite := graphics.get_node_or_null("Sprite2D") as Sprite2D
	if not is_instance_valid(sprite): return
	var h := maxi(sprite.hframes, 1)
	var v := maxi(sprite.vframes, 1)
	if h <= 1 and v <= 1:
		_outline_mat.set_shader_parameter("frame_uv_min", Vector2.ZERO)
		_outline_mat.set_shader_parameter("frame_uv_max", Vector2.ONE)
		return
	var col := sprite.frame % h
	var row := int(sprite.frame / float(h))
	var uv_min := Vector2(float(col) / h, float(row) / v)
	var uv_max := uv_min + Vector2(1.0 / h, 1.0 / v)
	_outline_mat.set_shader_parameter("frame_uv_min", uv_min)
	_outline_mat.set_shader_parameter("frame_uv_max", uv_max)
