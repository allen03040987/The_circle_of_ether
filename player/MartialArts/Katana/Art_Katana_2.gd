class_name Art_Katana_2
extends MartialArt

const CONFIG = {
	"anim": "katana/Art_Katana_2",
	"hitbox_name": "Art_Katana_1",
	"type": Damage.Type.HEAVY,
	"max_hits": 4,                     
	"interval": 0.1,                   
	"sticky": true,                    
	"knockback": Vector2(50.0, -400.0),
	"shake": 10.0,                     
	"shake_on_hit_only": true,
	"base_dmg": 180,                   
	"hit_sfx_type": "hit",
	"energy": 3,                       
	"switch": 4,
	"spark_type": 1,
	"spark_scale": 0.8,
	"action_type": Weapon.ActionType.SKILL
}

@export var launch_start_time: float = 0.1      
@export var launch_duration: float = 0.1       
@export var vertical_launch_speed: float = -650.0 
@export var forward_launch_speed: float = 380.0 

var is_launch_triggered: bool = false
var launch_timer: float = 0.0

func enter() -> void:
	super.enter()
	
	if not player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.connect(_on_animation_finished)
		
	weapon.step_cooldown = 0.15
	weapon.air_attack_locked = false
	weapon.is_attacking = true
	is_launch_triggered = false
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	weapon.combo_step = 99
	weapon._play_martial_art_attack(CONFIG)

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == CONFIG["anim"]:
		_finish_art()

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
			new_y = vertical_launch_speed * speed_mult
			new_x = player.direction * forward_launch_speed * speed_mult 
		else: 
			new_x = move_toward(new_x, 0.0, base_friction * 0.5)
			if new_y < 0:
				new_y = move_toward(new_y, 0.0, player.default_gravity * 2.0 * delta)
			else:
				new_y += player.default_gravity * delta
	else:
		new_x = move_toward(new_x, 0.0, base_friction)

	return Vector2(new_x, new_y)

func is_handling_gravity() -> bool:
	return is_launch_triggered

func cancel() -> void:
	_finish_art()
	super.cancel()

func _finish_art() -> void:
	is_active = false
	if player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.disconnect(_on_animation_finished)
	player.animation_player.speed_scale = 1.0
