class_name Art_Katana_5
extends MartialArt

const SWORD_WAVE_SCENE = preload("res://player/Katana/c_3_wave.tscn")

const CONFIG = {
	"anim": "katana/Art_Katana_5",
	"hitbox_name": "None",
	"type": Damage.Type.HEAVY,
	"knockback": Vector2.ZERO,
	"shake": 30.0,
	"shake_on_hit_only": true,
	"base_dmg": 932,
	"energy": 15,
	"switch": 20,
	"action_type": Weapon.ActionType.SKILL
}

# 🌟 改由卡帶自己管理發射狀態，不再依賴太刀老爸！
var _is_wave_fired: bool = false

func enter() -> void:
	super.enter()
	_is_wave_fired = false 
	
	if not player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.connect(_on_animation_finished)
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	weapon.combo_step = 21
	weapon._play_martial_art_attack(CONFIG)
	print("⚔️ [武藝卡帶] 發動：斷空劍氣 (22) —— 劍氣裝填完畢！")

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == CONFIG["anim"]:
		_finish_art()

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# 🌟 觸發劍氣
	if player.animation_player.current_animation_position >= 0.32 and not _is_wave_fired:
		_is_wave_fired = true
		if CombatManager.has_method("apply_camera_shake"): 
			CombatManager.apply_camera_shake(20.0) 
		_spawn_sword_wave() 

	new_x = move_toward(new_x, 0.0, base_friction)
	
	if not player.is_on_floor(): 
		var gravity_rate = weapon.get("air_skill_gravity_rate") if "air_skill_gravity_rate" in weapon else 0.25
		new_y += (player.default_gravity * gravity_rate) * delta

	return Vector2(new_x, new_y)

func is_handling_gravity() -> bool:
	return not player.is_on_floor()

func _spawn_sword_wave() -> void:
	if not SWORD_WAVE_SCENE: return
	var wave = SWORD_WAVE_SCENE.instantiate()
	player.get_tree().current_scene.add_child(wave)
	
	wave.global_position = player.global_position + Vector2(30 * player.direction, -20)
	wave.set("direction", player.direction)
	
	await player.get_tree().process_frame 
	if not is_instance_valid(wave) or not wave.get("hitbox"): return
	
	wave.hitbox.spark_type = 0
	wave.hitbox.spark_color = Color(0.7, 1.5, 0.5, 1.0)
	wave.hitbox.aura_color = Color(0, 1, 1, 1)
	
	wave.set("speed", 1500.0)
	wave.set("max_distance", 1200.0)
	wave.scale = Vector2(2.0 * player.direction, 2.0)
	
	wave.hitbox.damage_amount = max(1, roundi(float(CONFIG["base_dmg"])))
	wave.hitbox.absolute_knockback = Vector2(400.0 * player.direction, 0.0)
	wave.hitbox.knockback_force = Vector2(400.0, -400.0)
	wave.hitbox.attack_type = Damage.Type.LIGHT
	wave.hitbox.spark_scale = 0.3
	wave.hitbox.hit_sfx_type = "hit_4"
	
	var w_energy = float(CONFIG["energy"])
	var wave_state = [false] 
	
	wave.hitbox.hit.connect(func(hurtbox: Node):
		if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: return
		if not wave_state[0]:
			if player.has_method("add_weapon_resource"): 
				player.add_weapon_resource(weapon.get("WEAPON_ID"), w_energy)
			wave_state[0] = true
	)

func cancel() -> void:
	_finish_art()
	super.cancel()

func _finish_art() -> void:
	is_active = false
	if player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.disconnect(_on_animation_finished)
	player.animation_player.speed_scale = 1.0
