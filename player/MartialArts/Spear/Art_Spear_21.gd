class_name Art_Spear_21
extends MartialArt

func enter() -> void:
	super.enter()
	weapon.step_cooldown = 0.15
	weapon.is_attacking = true
	
	# 極限轉向特權
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	weapon.combo_step = 21
	weapon._play_attack(weapon.SKILL_CONFIG[21])
	print("🌪️ 發動大範圍聚怪武藝！")

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# 21 的物理邏輯非常單純，就是套用基準摩擦力
	new_x = move_toward(new_x, 0.0, base_friction)

	return Vector2(new_x, new_y)
