class_name TrainingDummy
extends CharacterBody2D

# ==========================================
# 🔗 節點參考
# ==========================================
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var stats_label: Label = $StatsLabel
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D

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
var default_gravity := ProjectSettings.get("physics/2d/default_gravity") as float

enum DummyState { IDLE, HURT, LAUNCHED }
var current_state: DummyState = DummyState.IDLE

# 🌟 對齊怪物的物理參數
@export var max_speed: float = 100.0
@export var acceleration: float = 2000.0 # 🌟 新增：怪物等級的抓地力/煞車力！

func _ready() -> void:
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
				_play_safe_anim("up")
				
		DummyState.LAUNCHED:
			if velocity.y >= 0 and is_on_floor() and not animation_player.is_playing():
				current_state = DummyState.IDLE
				_play_safe_anim("up")
				
		DummyState.IDLE:
			var current_anim = animation_player.current_animation
			if not animation_player.is_playing() or (current_anim != "hurt" and current_anim != "hurt_2" and current_anim != "up"):
				_play_safe_anim("idle")

	# ==========================================
	# 🏃 物理計算 (Physics Tick)
	# ==========================================
	match current_state:
		DummyState.IDLE:
			# 🌟 動畫結束後，使用高達 2000 的摩擦力瞬間煞停 (模擬怪物恢復站姿的抓地力)
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			velocity.y += default_gravity * delta
			move_and_slide()
			
		DummyState.HURT, DummyState.LAUNCHED:
			# 🌟 受傷期間，使用較滑的擊退摩擦力 (通常為 300)
			var knockback_friction = max_speed * 3.0 
			velocity.x = move_toward(velocity.x, 0.0, knockback_friction * delta)
			velocity.y += default_gravity * delta
			move_and_slide()

func _process(delta: float) -> void:
	if is_in_combat:
		combat_time += delta
		reset_timer -= delta
		_update_ui()
		if reset_timer <= 0:
			is_in_combat = false
			stats_label.modulate = Color.YELLOW 

func _on_hurtbox_hurt(hitbox: Hitbox) -> void:
	var dmg = hitbox.damage_amount if "damage_amount" in hitbox else 1
	var type = hitbox.attack_type if "attack_type" in hitbox else Damage.Type.LIGHT
	var is_heavy = (type == Damage.Type.HEAVY)
	
	var spawn_pos = global_position + Vector2(0, -20)
	if CombatManager.has_method("spawn_damage_number"):
		CombatManager.spawn_damage_number(dmg, spawn_pos, is_heavy)
	
	if not is_in_combat or reset_timer <= 0:
		combat_time = 0.0
		total_damage = 0
		max_hit = 0
		is_in_combat = true
		stats_label.modulate = Color.WHITE
		
	total_damage += dmg
	if dmg > max_hit: max_hit = dmg
	reset_timer = COMBAT_TIMEOUT 
	
	# ==========================================
	# 🚀 物理擊退觸發 (同步最新版的絕對方向系統！)
	# ==========================================
	var final_kb := Vector2.ZERO
	if "absolute_knockback" in hitbox:
		final_kb = hitbox.absolute_knockback
	elif "knockback_force" in hitbox: # 容錯防呆
		final_kb = hitbox.knockback_force
		
	# 浮空限制：在地板上且為輕擊時，沒收向上擊退力
	if type == Damage.Type.LIGHT and is_on_floor():
		if final_kb.y < 0:
			final_kb.y = 0.0
			
	# ==========================================
	# 動能保留系統 (Momentum Preservation)
	# ==========================================
	# 1. 垂直 (Y軸) 保留：若木人樁已被挑飛在空中，且新攻擊不具備向上擊退力，則繼承當前垂直速度
	if not is_on_floor() and final_kb.y == 0:
		final_kb.y = velocity.y
		
	# 2. 水平 (X軸) 保留：若新攻擊無水平擊退，保留當前滑行/擊退動能
	if is_zero_approx(final_kb.x):
		final_kb.x = velocity.x
			
	# ✅ 賦予最終計算結果
	velocity.x = final_kb.x
	velocity.y = final_kb.y

	animation_player.stop() 
	
	# 判斷是進入重擊擊飛 (LAUNCHED) 還是輕擊受傷 (HURT)
	# 🌟 注意：因為我們上面保留了 velocity.y，這裡判斷 final_kb.y 就能正確維持擊飛狀態！
	if type == Damage.Type.HEAVY or final_kb.y < 0:
		current_state = DummyState.LAUNCHED
		_play_safe_anim("hurt_2") 
	else:
		if is_on_floor():
			current_state = DummyState.HURT
			_play_safe_anim("hurt")
			
	if sprite:
		sprite.modulate = Color(2, 2, 2, 1) 
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)

func _update_ui() -> void:
	if combat_time == 0: return
	var dps = float(total_damage) / combat_time
	stats_label.text = "總傷: %d\n最高: %d\n時間: %.1f\nDPS: %.0f" % [total_damage, max_hit, combat_time, dps]

func _play_safe_anim(anim_name: String) -> void:
	if animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			animation_player.play(anim_name)
