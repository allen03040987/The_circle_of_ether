class_name Art_Talisman_31
extends MartialArt

func enter() -> void:
	super.enter()
	weapon.step_cooldown = 0.15
	weapon.is_attacking = true
	weapon.is_vfx_fired = false
	weapon.is_tower_spawned = false
	
	weapon.combo_step = 31
	weapon._play_attack(weapon.SKILL_CONFIG[31])
	weapon.gain_talisman_charge(30)

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var anim_time = player.animation_player.current_animation_position
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	new_x = move_toward(new_x, 0.0, base_friction)
	if anim_time >= 0.1 and not weapon.is_vfx_fired:
		weapon.is_vfx_fired = true
		weapon._spawn_weapon_vfx(weapon.SKILL_CONFIG[31])
	
	if anim_time >= 0.3 and not weapon.is_tower_spawned:
		weapon.is_tower_spawned = true 
		if player is Player and CombatManager.has_method("apply_camera_shake"):
			CombatManager.apply_camera_shake(30.0, 0.15)

	return Vector2(new_x, new_y)
