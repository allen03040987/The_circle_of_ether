class_name ClottySkill_K4
extends VsPlayerState

# ==========================================
# ⚔️ 技能 K4 (十字幻影墜 / 地面單劈)
# ==========================================
@export_group("⚙️ 技能參數")
@export var mp_cost: float = 15.0
@export var dive_speed: float = 1200.0   

@export_group("🎯 判定框綁定")
@export var hitbox_ground_path: NodePath 
@export var hitbox_air_multi_path: NodePath 
@export var hitbox_air_dive_path: NodePath  

var is_air_mode: bool = false
var is_diving: bool = false

func can_cast() -> bool:
	if player.current_mp < mp_cost: return false 
	return true

func enter() -> void:
	player.current_mp -= mp_cost
	player.auto_face_opponent()
	is_diving = false
	
	# 清理判定框記憶
	var hb_g = get_node_or_null(hitbox_ground_path) as VsHitbox
	var hb_am = get_node_or_null(hitbox_air_multi_path) as VsHitbox
	var hb_ad = get_node_or_null(hitbox_air_dive_path) as VsHitbox
	
	if hb_g: hb_g.hit_targets.clear()
	if hb_ad: hb_ad.hit_targets.clear()
	
	if hb_am: 
		hb_am.hit_targets.clear()
		# 🧲 聚怪魔法
		hb_am.air_knockback = Vector2(-100, -20) 
		hb_am.ground_knockback = Vector2(-100, -20) 
		hb_am.hitstun_time = 0.3 

	is_air_mode = not player.is_on_floor()

	if is_air_mode:
		player.velocity.x = 0.0
		player.velocity.y = 0.0 
		player.play_safe_anim("skill_K_4")
		_air_sequence()
	else:
		player.strike_impulse(150.0)
		player.play_safe_anim("skill_K_4_floor")

# ==========================================
# 🎬 空中專屬：隱身與五連打排程系統
# ==========================================
func _air_sequence() -> void:
	await get_tree().create_timer(0.15, false, false, true).timeout
	if state_machine.current_state != self: return
	
	# 👻 進入隱身狀態 (單機版直接呼叫)
	_set_visibility(false)
	
	var hb_am = get_node_or_null(hitbox_air_multi_path) as VsHitbox
	for i in range(5):
		if state_machine.current_state != self: break
		
		if hb_am: hb_am.hit_targets.clear()
		player.play_camera_shake(5.0, 0.1) 
		
		await get_tree().create_timer(0.1, false, false, true).timeout
		
	if state_machine.current_state != self: return
	
	# ☄️ 解除隱身
	_set_visibility(true)
	player.play_safe_anim("skill_K_4_end")
	is_diving = true

func process_physics(delta: float) -> VsState:
	var interrupt = check_interrupts()
	if interrupt != null:
		return interrupt
		
	if is_air_mode:
		if is_diving:
			player.velocity.x = 0.0
			player.velocity.y = dive_speed
			
			if player.is_on_floor():
				player.velocity.y = 0.0
				player.play_camera_shake(15.0, 0.2) 
				return state_machine.idle_state 
		else:
			# 隱身死釘在空中
			player.velocity.x = 0.0
			player.velocity.y = 0.0
	else:
		# 地面滑行
		player.velocity.x = move_toward(player.velocity.x, 0.0, player.ground_friction * delta)
		if not player.animation.is_playing():
			return state_machine.idle_state
			
	player.custom_move_and_slide()
	return null

func exit() -> void:
	_set_visibility(true)
	player.deactivate_all_hitboxes()
	is_diving = false

# ==========================================
# 👻 隱身控制系統 (純單機極速版)
# ==========================================
func _set_visibility(is_visible: bool) -> void:
	var graphics = player.get_node_or_null("Graphics")
	if graphics:
		graphics.modulate.a = 1.0 if is_visible else 0.0
