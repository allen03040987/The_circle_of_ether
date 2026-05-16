class_name Slime
extends Enemy

enum SlimeState { IDLE, WALK, RUN, PREPARE, ATTACK, HURT, LAUNCHED, DYING }
const KEEP_CURRENT := -1

# ==========================================
# 🎛️ AI 特有參數 (AI Properties)
# ==========================================
@export_group("AI 攻擊設定")
@export var attack_dash_speed: float = 600.0   
@export var attack_dash_duration: float = 0.3  
@export var attack_prepare_time: float = 2.0 
@export var attack_cooldown_time: float = 2.5   

# --- 內部狀態 ---
var current_state: SlimeState = SlimeState.IDLE
var state_time: float = 0.0
var attack_cooldown: float = 0.0 
var warning_tween: Tween

# ==========================================
# 🔗 節點參考 (Node References)
# ==========================================
@onready var wall_checker: RayCast2D = $Graphics/WallChecker
@onready var floor_checker: RayCast2D = $Graphics/FloorChecker
@onready var player_checker: RayCast2D = $Graphics/playerChecker
@onready var calm_down_timer: Timer = $CalmDownTimer
@onready var warning_icon: Sprite2D = $Graphics/WarningIcon
@onready var hitbox_shape: CollisionShape2D = $Graphics/Hitbox/CollisionShape2D 
@onready var hitbox: Hitbox = $Graphics/Hitbox 

# ==========================================
# ⚙️ 初始化與主循環 (Lifecycle)
# ==========================================
func _ready() -> void:
	hitbox_shape.disabled = true
	if warning_icon: warning_icon.visible = false

func can_see_player() -> bool:
	if not player_checker.is_colliding(): return false
	return player_checker.get_collider() is Player

func _physics_process(delta: float) -> void:
	if attack_cooldown > 0: attack_cooldown -= delta 
		
	# 🧠 狀態機大腦輪詢
	while true: 
		var next := get_next_state(current_state) as int
		if next == KEEP_CURRENT: break
		transition_state(current_state, next as SlimeState)
		current_state = next as SlimeState
		state_time = 0.0 
		
	tick_physics(current_state, delta)
	state_time += delta

# ==========================================
# 🧠 AI 決策大腦 (State Transitions)
# ==========================================
func get_next_state(state: SlimeState) -> int:
	# --- 1. 死亡優先 ---
	if stats.health <= 0:
		if state == SlimeState.DYING: return KEEP_CURRENT
		return SlimeState.DYING
		
	# --- 2. 受傷打斷判定 ---
	if pending_damage != null:
		var p_type = pending_damage["type"]
		var p_kb = pending_damage["knockback_force"]
		
		# 霸體判定 (無視硬直)
		if p_type == Damage.Type.NO_STUN:
			pending_damage = null
			return KEEP_CURRENT
			
		# 史萊姆特有動作霸體 (準備與衝刺期間免疫輕擊)
		if (state == SlimeState.ATTACK or state == SlimeState.PREPARE) and p_type == Damage.Type.LIGHT:
			pending_damage = null 
			return KEEP_CURRENT
			
		# 正常受傷分流 (Juggling 浮空修復)
		if p_type == Damage.Type.HEAVY or p_kb.y < 0: 
			return SlimeState.LAUNCHED
		else: 
			return SlimeState.HURT
			
	# --- 3. 日常行為樹 ---
	match state:
		SlimeState.IDLE:
			if can_see_player() and attack_cooldown <= 0: return SlimeState.PREPARE 
			if state_time > 2: return SlimeState.WALK
		SlimeState.WALK:
			if can_see_player() and attack_cooldown <= 0: return SlimeState.PREPARE
		SlimeState.RUN:
			if can_see_player() and attack_cooldown <= 0: return SlimeState.PREPARE
			if calm_down_timer.is_stopped(): return SlimeState.WALK
		SlimeState.PREPARE:
			if state_time >= attack_prepare_time: return SlimeState.ATTACK
		SlimeState.ATTACK:
			if state_time >= attack_dash_duration: return SlimeState.RUN
			
		# 🛑 受傷狀態解除條件
		SlimeState.HURT:
			if not animation_player.is_playing() and is_on_floor(): return SlimeState.RUN
				
		SlimeState.LAUNCHED:
			# 必須往下掉、踩到地板且動畫播完
			if velocity.y >= 0 and is_on_floor() and not animation_player.is_playing(): return SlimeState.RUN
			
	return KEEP_CURRENT

# ==========================================
# 🏃 物理行為執行 (Physics Tick)
# ==========================================
func tick_physics(state: SlimeState, delta: float) -> void:
	match state:
		SlimeState.IDLE, SlimeState.DYING:
			move(0.0, delta)
			
		SlimeState.PREPARE:
			if state_time < (attack_prepare_time - 0.5):
				var back_speed = max_speed * 0.4
				velocity.x = move_toward(velocity.x, -direction * back_speed, acceleration * delta)
			else:
				velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			velocity.y += default_gravity * delta
			custom_move_and_slide() # 🌟 修復：套用最高位移原則
			
		SlimeState.WALK:
			if is_on_floor() and (wall_checker.is_colliding() or not floor_checker.is_colliding()):
				direction *= -1
				wall_checker.force_raycast_update()
				floor_checker.force_raycast_update()
			move(max_speed / 2, delta)
			
		SlimeState.RUN:
			if is_on_floor() and (wall_checker.is_colliding() or not floor_checker.is_colliding()):
				direction *= -1
				wall_checker.force_raycast_update()
				floor_checker.force_raycast_update()
			move(max_speed, delta)
			
		SlimeState.ATTACK:
			velocity.x = direction * attack_dash_speed
			velocity.y += default_gravity * delta
			custom_move_and_slide() # 🌟 修復：套用最高位移原則
			
		SlimeState.HURT:
			var knockback_friction = max_speed * 3.0 
			velocity.x = move_toward(velocity.x, 0.0, knockback_friction * delta)
			velocity.y += default_gravity * delta
			custom_move_and_slide() # 🌟 修復：套用最高位移原則
			
		SlimeState.LAUNCHED:
			var knockback_friction = max_speed * 3.0 
			velocity.x = move_toward(velocity.x, 0.0, knockback_friction * delta)
			velocity.y += default_gravity * delta
			custom_move_and_slide() # 🌟 修復：套用最高位移原則

# ==========================================
# 🎬 狀態切換與特效控制 (Transitions)
# ==========================================
func transition_state(from: SlimeState, to: SlimeState) -> void:
	# --- 離開當前狀態的清理 ---
	match from:
		SlimeState.PREPARE:
			if warning_icon: warning_icon.visible = false
			if warning_tween: warning_tween.kill() 
		SlimeState.ATTACK:
			hitbox_shape.set_deferred("disabled", true)
			velocity.x = 0 
			attack_cooldown = attack_cooldown_time

	# --- 進入新狀態的初始化 ---
	match to:
		SlimeState.IDLE:
			animation_player.play("idle")
		SlimeState.WALK:
			animation_player.play("walk")
			if not floor_checker.is_colliding():
				direction *= -1
				floor_checker.force_raycast_update()
		SlimeState.RUN:
			animation_player.play("run")
			calm_down_timer.start()
		SlimeState.PREPARE:
			animation_player.play("idle") 
			if warning_icon:
				warning_icon.visible = false
				warning_icon.modulate.a = 0.0
				var wait_time = max(0.0, attack_prepare_time - 0.6)
				get_tree().create_timer(wait_time).timeout.connect(func():
					if not is_instance_valid(self): return 
					if current_state == SlimeState.PREPARE and warning_icon:
						warning_icon.visible = true
						if warning_tween: warning_tween.kill() 
						warning_tween = create_tween()
						warning_tween.tween_property(warning_icon, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)
				)
		SlimeState.ATTACK:
			animation_player.play("run")
			
			if hitbox:
				hitbox.damage_amount = 1
				hitbox.attack_type = Damage.Type.LIGHT
				hitbox.knockback_force = Vector2(400.0, 0.0) 
				if "shake_intensity" in hitbox: hitbox.shake_intensity = 3.0 
					
			hitbox_shape.set_deferred("disabled", false)
			
		SlimeState.HURT, SlimeState.LAUNCHED:
			animation_player.stop()
			animation_player.play("hit")
			
			var p_knockback: Vector2 = pending_damage["knockback_force"]
			velocity.x = p_knockback.x
			velocity.y = p_knockback.y
			
			if not is_zero_approx(p_knockback.x):
				direction = Direction.LEFT if p_knockback.x > 0 else Direction.RIGHT
				
			pending_damage = null
			
		SlimeState.DYING:
			animation_player.play("die")

# ==========================================
# 💥 受擊接收 (Damage Reception)
# ==========================================
func _on_hurtbox_hurt(hitbox: Hitbox) -> void:
	take_damage(hitbox)
