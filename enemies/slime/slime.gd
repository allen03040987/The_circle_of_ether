class_name Slime
extends Enemy
## 史萊姆雜兵 AI
## 採用高效能的 Code-based FSM (輕量級狀態機) 實現群體管理。

enum SlimeState { IDLE, WALK, RUN, PREPARE, ATTACK, HURT, LAUNCHED, DYING }
const KEEP_CURRENT := -1

# ==========================================
# 🎛️ AI 與攻擊設定 
# ==========================================
@export_group("AI 行為設定")
@export var attack_dash_speed: float = 600.0   
@export var attack_dash_duration: float = 0.3  
@export var attack_prepare_time: float = 2.0 
@export var attack_cooldown_time: float = 2.5   

# 🌟 解耦：把傷害參數提取到外部，方便面板調整
@export_group("史萊姆攻擊力")
@export var base_damage: int = 10
@export var base_knockback: Vector2 = Vector2(400.0, 0.0)

# --- 內部狀態 ---
var current_state: SlimeState = SlimeState.IDLE
var state_time: float = 0.0
var attack_cooldown: float = 0.0 
var warning_tween: Tween

# ==========================================
# 🔗 節點參考
# ==========================================
@onready var wall_checker: RayCast2D = $Graphics/WallChecker
@onready var floor_checker: RayCast2D = $Graphics/FloorChecker
@onready var player_checker: RayCast2D = $Graphics/playerChecker
@onready var calm_down_timer: Timer = $CalmDownTimer
@onready var warning_icon: Sprite2D = $Graphics/WarningIcon
@onready var hitbox_shape: CollisionShape2D = $Graphics/Hitbox/CollisionShape2D 
@onready var hitbox: Hitbox = $Graphics/Hitbox 

# ==========================================
# ⚙️ 核心生命週期與大腦輪詢
# ==========================================
func _ready() -> void:
	super._ready() # 確保繼承的 Enemy._ready() 被呼叫
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
# 🧠 AI 狀態轉移判定 (State Logic)
# ==========================================
func get_next_state(state: SlimeState) -> int:
	# 1. 死亡優先
	if stats.health <= 0:
		if state == SlimeState.DYING: return KEEP_CURRENT
		return SlimeState.DYING
		
	# 2. 受傷打斷判定
	if pending_damage != null:
		var p_type = pending_damage["type"]
		var p_kb = pending_damage["knockback_force"]
		
		if p_type == Damage.Type.NO_STUN:
			pending_damage = null
			return KEEP_CURRENT
			
		if (state == SlimeState.ATTACK or state == SlimeState.PREPARE) and p_type == Damage.Type.LIGHT:
			pending_damage = null 
			return KEEP_CURRENT
			
		if p_type == Damage.Type.HEAVY or p_kb.y < 0: 
			return SlimeState.LAUNCHED
		else: 
			return SlimeState.HURT
			
	# 3. 日常行為樹
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
		SlimeState.HURT:
			if not animation_player.is_playing() and is_on_floor(): return SlimeState.RUN
		SlimeState.LAUNCHED:
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
			custom_move_and_slide()
			
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
			custom_move_and_slide()
			
		SlimeState.HURT, SlimeState.LAUNCHED:
			var knockback_friction = max_speed * 3.0 
			velocity.x = move_toward(velocity.x, 0.0, knockback_friction * delta)
			velocity.y += default_gravity * delta
			custom_move_and_slide()

# ==========================================
# 🎬 狀態切換與特效控制 (Transitions)
# ==========================================
func transition_state(from: SlimeState, to: SlimeState) -> void:
	# --- 離開狀態的清理 ---
	match from:
		SlimeState.PREPARE:
			if warning_icon: warning_icon.visible = false
			if warning_tween: warning_tween.kill() 
		SlimeState.ATTACK:
			hitbox_shape.set_deferred("disabled", true)
			velocity.x = 0 
			attack_cooldown = attack_cooldown_time

	# --- 進入狀態的初始化 ---
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
				hitbox.damage_amount = base_damage
				hitbox.attack_type = Damage.Type.LIGHT
				hitbox.knockback_force = base_knockback 
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
			
			# 🌟 核心防護：死亡瞬間立刻關閉所有碰撞與判定！防止幽靈攻擊或被鞭屍位移
			hitbox_shape.set_deferred("disabled", true)
			var hurtbox = graphics.get_node_or_null("Hurtbox/CollisionShape2D")
			if hurtbox: hurtbox.set_deferred("disabled", true)
			
			# 取消物理層
			set_collision_layer_value(1, false)
			set_collision_mask_value(1, false)

# ==========================================
# 💥 受擊接收 
# ==========================================
func _on_hurtbox_hurt(hb: Hitbox) -> void:
	take_damage(hb)
