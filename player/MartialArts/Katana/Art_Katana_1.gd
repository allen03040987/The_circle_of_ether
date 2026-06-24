class_name Art_Katana_1
extends MartialArt

const CONFIG = {
	"anim": "katana/Art_Katana_1",
	"hitbox_name": "C1",
	"type": Damage.Type.HEAVY,
	"knockback": Vector2(0.0, -400.0),
	"shake": 20.0,
	"shake_on_hit_only": false,
	"base_dmg": 560,
	"hit_sfx_type": "hit_2",
	"energy": 10,
	"switch": 15,
	"spark_type": 1,      
	"spark_scale": 0.8,   
	"action_type": Weapon.ActionType.SKILL
}

func enter() -> void:
	super.enter()
	
	if not player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.connect(_on_animation_finished)
		
	weapon.step_cooldown = 0.15
	weapon.air_attack_locked = false
	weapon.is_attacking = true
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	weapon.combo_step = 11
	weapon._play_martial_art_attack(CONFIG)

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == CONFIG["anim"]:
		_finish_art()

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	new_x = move_toward(new_x, 0.0, base_friction)
	return Vector2(new_x, new_y)

func cancel() -> void:
	_finish_art()
	super.cancel()

func _finish_art() -> void:
	is_active = false
	if player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.disconnect(_on_animation_finished)
	player.animation_player.speed_scale = 1.0
