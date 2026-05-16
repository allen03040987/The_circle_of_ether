class_name ClottySkill_Special
extends VsPlayerState

var is_cinematic_active: bool = false

func can_cast() -> bool:
	if not player.is_on_floor(): return false 
	if "is_awakened" in player and player.is_awakened: return false
	if "current_energy" in player and player.current_energy < player.max_energy: return false
	return true

func enter() -> void:
	is_cinematic_active = true 
	
	if "is_awakened" in player: player.is_awakened = true
		
	player.velocity = Vector2.ZERO
	player.auto_face_opponent()
	player.play_safe_anim("special") 
	
	if player.has_method("activate_the_world"):
		player.activate_the_world()
		
	player.play_ultimate_cinematic(2.5)
	player.trigger_cinematic_zoom(true, 1.5, 0.2)
	
	_sequence_mid_cinematic_effects()

func _sequence_mid_cinematic_effects() -> void:
	await get_tree().create_timer(1.6, true, false, true).timeout
	
	if state_machine.current_state == self:
		player.play_camera_shake(20.0, 0.4)
		player.trigger_cinematic_zoom(true, 1.0, 0.15)
		
	await get_tree().create_timer(0.9, true, false, true).timeout
	
	if state_machine.current_state == self:
		is_cinematic_active = false

func exit() -> void:
	if is_cinematic_active:
		player.trigger_cinematic_zoom(true, 1.0, 0.2)
		
	is_cinematic_active = false
	
func process_physics(delta: float) -> VsState:
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.ground_friction * delta)
	player.custom_move_and_slide()
	
	if not player.animation.is_playing() and not is_cinematic_active:
		return state_machine.idle_state
		
	return null
