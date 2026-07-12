class_name TrainingDummy
extends Enemy

# ==========================================
# 📊 測傷資料庫
# ==========================================
var is_in_combat: bool = false
var combat_time: float = 0.0
var total_damage: int = 0
var max_hit: int = 0
var reset_timer: float = 0.0
const COMBAT_TIMEOUT: float = 3.0

# ==========================================
# 🌍 物理與狀態
# ==========================================
enum DummyState { IDLE, HURT, LAUNCHED }
var current_state: DummyState = DummyState.IDLE

@onready var stats_label: Label = $StatsLabel
@onready var hurtbox: Hurtbox = $Hurtbox

func _ready() -> void:
	super._ready() # 讓 Enemy 基底接上破防紅閃等共用邏輯
	if not hurtbox.hurt.is_connected(_on_hurtbox_hurt):
		hurtbox.hurt.connect(_on_hurtbox_hurt)
	_update_ui()

func _physics_process(delta: float) -> void:
	# ==========================================
	# 🤖 狀態機轉換 (Transitions)
	# ==========================================
	match current_state:
		DummyState.HURT:
			if not animation_player.is_playing() and is_on_floor():
				current_state = DummyState.IDLE
				play_safe_anim("up")

		DummyState.LAUNCHED:
			if velocity.y >= 0 and is_on_floor() and not animation_player.is_playing():
				current_state = DummyState.IDLE
				play_safe_anim("up")

		DummyState.IDLE:
			var current_anim = animation_player.current_animation
			if not animation_player.is_playing() or (current_anim != "hurt" and current_anim != "hurt_2" and current_anim != "up"):
				play_safe_anim("idle")

	# ==========================================
	# 🏃 物理計算 (Physics Tick)
	# ==========================================
	match current_state:
		DummyState.IDLE:
			# 🌟 動畫結束後，使用高達 2000 的摩擦力瞬間煞停 (模擬怪物恢復站姿的抓地力)
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			velocity.y += default_gravity * delta
			custom_move_and_slide()

		DummyState.HURT, DummyState.LAUNCHED:
			# 🌟 擊退摩擦力沿用跟 Slime/BossNaihe 一致的手感
			var knockback_friction = max_speed * 3.0
			velocity.x = move_toward(velocity.x, 0.0, knockback_friction * delta)
			velocity.y += default_gravity * delta
			custom_move_and_slide()

func _process(delta: float) -> void:
	super._process(delta)
	if is_in_combat:
		combat_time += delta
		reset_timer -= delta
		_update_ui()
		if reset_timer <= 0:
			is_in_combat = false
			stats_label.modulate = Color.YELLOW

func _on_hurtbox_hurt(hitbox: Hitbox) -> void:
	var dmg = hitbox.damage_amount if "damage_amount" in hitbox else 1

	# 🌟 血量、擊退計算（含浮空限制/動能保留）、白閃特效都交給 Enemy.gd 統一處理，不再自己重寫一份
	take_damage(hitbox)

	# --- 測傷 UI（木樁專屬，跟其他敵人無關）---
	if not is_in_combat or reset_timer <= 0:
		combat_time = 0.0
		total_damage = 0
		max_hit = 0
		is_in_combat = true
		stats_label.modulate = Color.WHITE

	total_damage += dmg
	if dmg > max_hit: max_hit = dmg
	reset_timer = COMBAT_TIMEOUT

	# --- 套用 take_damage() 算好的擊退力，決定 Hurt / Launched ---
	if pending_damage != null:
		var kb: Vector2 = pending_damage["knockback_force"]
		var p_type = pending_damage["type"]
		pending_damage = null

		velocity = kb

		if p_type == Damage.Type.HEAVY or kb.y < 0:
			current_state = DummyState.LAUNCHED
			play_safe_anim("hurt_2")
		elif p_type != Damage.Type.NO_STUN:
			current_state = DummyState.HURT
			play_safe_anim("hurt")

func _update_ui() -> void:
	if combat_time == 0: return
	var dps = float(total_damage) / combat_time
	stats_label.text = "總傷: %d\n最高: %d\n時間: %.1f\nDPS: %.0f" % [total_damage, max_hit, combat_time, dps]
