class_name Art_Spear_22
extends MartialArt

@export var launch_start_time: float = 0.4
@export var launch_duration: float = 0.06        
@export var vertical_launch_speed: float = -650.0 

var is_launch_triggered: bool = false
var launch_timer: float = 0.0

func enter() -> void:
	super.enter()
	weapon.step_cooldown = 0.15
	weapon.is_attacking = true # 🌟 核心修復：宣告我正在攻擊！
	is_launch_triggered = false
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	weapon.combo_step = 22
	weapon._play_attack(weapon.SKILL_CONFIG[22])
	print("🚀 發動向上挑飛武藝！")

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	if player.animation_player.current_animation_position >= launch_start_time and not is_launch_triggered:
		is_launch_triggered = true
		launch_timer = launch_duration
		
	if is_launch_triggered:
		if launch_timer > 0: 
			launch_timer -= delta
			new_y = vertical_launch_speed
			new_x = 0.0 
		else: 
			new_x = 0.0
			if new_y < 0:
				new_y = move_toward(new_y, 0.0, player.default_gravity * 2.0 * delta)
			else:
				new_y += player.default_gravity * delta
	else:
		new_x = move_toward(new_x, 0.0, base_friction)

	return Vector2(new_x, new_y)

func is_handling_gravity() -> bool:
	return is_launch_triggered
