class_name Art_Katana_22
extends MartialArt

func enter() -> void:
	super.enter()
	weapon.step_cooldown = 0.15
	weapon.air_attack_locked = false
	weapon.is_attacking = true
	weapon.is_wave_fired = false # 確保每次發動重置狀態
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	weapon.combo_step = 22
	weapon._play_skill_step(22)

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# 🌟 觸發劍氣
	if player.animation_player.current_animation_position >= 0.32 and not weapon.is_wave_fired:
		weapon.is_wave_fired = true
		if CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(20.0) 
		weapon.spawn_sword_wave("skill_down")

	new_x = move_toward(new_x, 0.0, base_friction)
	if not player.is_on_floor(): 
		new_y += (player.default_gravity * weapon.air_skill_gravity_rate) * delta

	return Vector2(new_x, new_y)

func is_handling_gravity() -> bool:
	return not player.is_on_floor()
