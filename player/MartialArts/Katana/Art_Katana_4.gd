class_name Art_Katana_4
extends MartialArt

const CONFIG = {
	"anim": "katana/Art_Katana_4",
	"hitbox_name": "Art_Katana_3",
	"type": Damage.Type.LIGHT,
	"max_hits": 4,
	"interval": 0.12,
	"sticky": true,
	"knockback": Vector2(550.0, -100.0),
	"shake": 20.0,
	"shake_on_hit_only": true,
	"base_dmg": 450,
	"energy": 5,
	"switch": 5,
	"hit_sfx_type": "hit",
	"action_type": Weapon.ActionType.SKILL
}

func _ready() -> void:
	can_use_in_air = true # 🌟 開放空戰特權
	
func enter() -> void:
	super.enter()
	
	if not player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.connect(_on_animation_finished)
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1
	weapon.combo_step = 21 
	weapon._play_martial_art_attack(CONFIG)
	print("⚔️ [武藝卡帶] 發動：裂地連斬·貳 (21)")

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == CONFIG["anim"]:
		_finish_art()

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	new_x = move_toward(new_x, 0.0, base_friction)
	
	if not player.is_on_floor(): 
		var gravity_rate = weapon.get("air_skill_gravity_rate") if "air_skill_gravity_rate" in weapon else 0.25
		new_y += (player.default_gravity * gravity_rate) * delta

	return Vector2(new_x, new_y)

func is_handling_gravity() -> bool:
	return not player.is_on_floor()

func cancel() -> void:
	_finish_art()
	super.cancel()

func _finish_art() -> void:
	is_active = false
	if player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.disconnect(_on_animation_finished)
	player.animation_player.speed_scale = 1.0
