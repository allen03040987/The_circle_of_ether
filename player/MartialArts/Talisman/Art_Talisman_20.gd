class_name Art_Talisman_20
extends MartialArt

func enter() -> void:
	super.enter()
	weapon.step_cooldown = 0.15
	weapon.is_attacking = true
	weapon.is_vfx_fired = false 
	weapon.is_tower_spawned = false 
	
	weapon.combo_step = 20
	weapon._play_attack(weapon.SKILL_CONFIG[20])
	weapon.gain_talisman_charge(10) 
	
	if player is Player:
		player.invincible_time_left = 1.0

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var anim_time = player.animation_player.current_animation_position
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	new_x = move_toward(new_x, 0.0, base_friction)
	
	if anim_time >= 0.1 and not weapon.is_vfx_fired:
		weapon.is_vfx_fired = true
		weapon._spawn_weapon_vfx(weapon.SKILL_CONFIG[20]) 
			
	if anim_time >= 1.15 and not weapon.is_tower_spawned:
		weapon.is_tower_spawned = true
		weapon._spawn_healing_tower()
		for i in range(9):
			var angle = deg_to_rad(i * 40.0)
			weapon._spawn_laser_projectile(weapon.SKILL_CONFIG[20], angle)
			
	if player is Player:
		if anim_time >= 0.0 and anim_time <= 1.0:
			player.invincible_time_left = max(player.invincible_time_left, 0.1) 
		elif anim_time > 1.0 and anim_time < 1.1:
			if player.invincible_timer.time_left == 0:
				player.invincible_time_left = 0.0

	return Vector2(new_x, new_y)
