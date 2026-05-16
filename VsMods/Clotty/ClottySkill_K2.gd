class_name ClottySkill_UpSlash
extends VsPlayerState

# ==========================================
# 月牙升空斬
# ==========================================
@export_group("⚙️ 技能參數")
@export var mp_cost: float = 20.0          
@export var dash_speed: float = 500.0      
@export var dash_duration: float = 0.15    
@export var jump_force: float = -650.0     
@export var ghost_color: Color = Color(0.4, 0.9, 0.6, 0.5) 

# 🎯 判定與數值設定 (開放給面板)
@export_group("🎯 判定與數值設定")
# 🌟 把 NodePath 改成 String，並且直接寫死老爸肚子裡的路徑！
@export var skill_hitbox_path: String = "Graphics/Hitbox_k2"
@export var base_damage: float = 40.0
@export var target_knockback: Vector2 = Vector2(150, -520) # 🌟 你的目標击退值

# 🌟 核心：開放隨機 X 軸擊退的範圍 (面板可調)
@export var x_knockback_randomness: float = 30.0 # 隨機幅度 ±30

var dash_timer: float = 0.0
var is_dashing: bool = false
var has_jumped: bool = false
var ghost_spawn_timer: float = 0.0

func can_cast() -> bool:
	if not player.is_on_floor(): return false 
	if player.current_mp < mp_cost: return false 
	return true
	
func enter() -> void:
	player.auto_face_opponent()
	player.current_mp -= mp_cost
	player.play_safe_anim("skill_K_2")
	
	# ==========================================
	# 🌟 神級修正：加上 player. 才能從老爸身上找！
	# ==========================================
	var my_hitbox = player.get_node_or_null(skill_hitbox_path) as VsHitbox
	
	if my_hitbox != null:
		# 1. 注入基礎傷害
		my_hitbox.damage = base_damage
		
		# 2. X 軸擊退隨機化！
		var randomized_kb = target_knockback
		randomized_kb.x += randf_range(-x_knockback_randomness, x_knockback_randomness)
		
		my_hitbox.ground_knockback = randomized_kb
		my_hitbox.air_knockback = randomized_kb
		
		# 🌟 裝上監視器：確保有印出這行！
		print("✅ 成功找到 Hitbox！已注入傷害 ", base_damage, " 與擊退：", randomized_kb)
		
		# 預留 (如果未來有全域 Buff)
		if player.has_method("buff_hitbox"):
			player.buff_hitbox(my_hitbox, base_damage)
	else:
		# 🌟 防呆警告：如果你看到這行紅字，代表 skill_hitbox_path 寫錯了！
		printerr("❌ 慘了！老爸肚子裡找不到: ", skill_hitbox_path, "，請檢查 Scene Tree 裡面的節點名稱！")
			
	 
	
	var facing_dir = player.get_node("Graphics").scale.x
	player.velocity.x = facing_dir * dash_speed
	player.velocity.y = 10.0 
	
	is_dashing = true
	has_jumped = false
	dash_timer = dash_duration

func exit() -> void:
	player.deactivate_all_hitboxes()
	
func process_physics(delta: float) -> VsState:
	
	# 🌟 【專屬後撤特權】
	if can_dash_cancel and player.double_tapped_dir != 0.0:
		var facing_dir = player.get_node("Graphics").scale.x
		if player.double_tapped_dir != facing_dir and player.current_stamina >= player.small_dash_cost:
			player.current_stamina -= player.small_dash_cost
			player.get_node("Graphics").scale.x = player.double_tapped_dir
			return state_machine.small_dash_state

	var interrupt = check_interrupts()
	if interrupt != null:
		return interrupt
		
	var current_time = player.animation.current_animation_position
	var facing_dir = player.get_node("Graphics").scale.x
	
	if current_time >= 0.21 and current_time < 0.22: 
		player.velocity.x = 200.0 * facing_dir   
		player.velocity.y = 10.0 
		if is_dashing:
			player.spawn_afterimage(ghost_color, 0.2) 
	
	elif current_time >= 0.24 and current_time < 0.3:
		player.velocity.y = -2000.0 
		player.velocity.x = -100.0 * facing_dir 
		is_dashing = false
		has_jumped = true
		
	elif current_time >= 0.13 and current_time < 0.18:
		player.velocity.y = -700.0 
		
	elif current_time >= 0.18:
		if player.velocity.y < -200:
			player.velocity.y = -200.0 
	
	if current_time > 0.2:
		player.velocity.y += gravity  * delta
		player.velocity.x = move_toward(player.velocity.x, 0.0, player.air_friction * delta)
	
	player.custom_move_and_slide()

	if not player.animation.is_playing() and has_jumped:
		return state_machine.fall_state if state_machine.fall_state != null else state_machine.idle_state
		
	return null
