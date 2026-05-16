class_name ClottySkill_K3
extends VsPlayerState

@export_group("⏳ 滯空設定")
@export var hover_duration: float = 0.3          
@export var fall_gravity_multiplier: float = 0.8 
@export var projectile_scene: PackedScene 

var state_timer: float = 0.0 

func can_cast() -> bool:
	return true 

func enter() -> void:
	state_timer = 0.0 
	player.velocity = Vector2.ZERO 
	player.auto_face_opponent()
	player.play_safe_anim("skill_k_3")

func process_physics(delta: float) -> VsState:
	# 🌟 專屬後撤特權
	if can_dash_cancel and player.double_tapped_dir != 0.0:
		var facing_dir = player.get_node("Graphics").scale.x
		if player.double_tapped_dir != facing_dir and player.current_stamina >= player.small_dash_cost:
			player.current_stamina -= player.small_dash_cost
			player.get_node("Graphics").scale.x = player.double_tapped_dir
			return state_machine.small_dash_state

	var interrupt = check_interrupts()
	if interrupt != null:
		return interrupt
		
	state_timer += delta
	
	# 滯空與下墜邏輯
	if state_timer <= hover_duration:
		player.velocity.y = 0.0
	else:
		player.velocity.y += gravity * fall_gravity_multiplier * delta
	
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.ground_friction * delta)
	player.custom_move_and_slide()
	
	if not player.animation.is_playing():
		if player.is_on_floor():
			return state_machine.idle_state
		else:
			return state_machine.fall_state
			
	return null
