class_name Art_Katana_21
extends MartialArt

# 🌟 招式 21 的專屬數據：6 段黏著打擊完全封裝！
const CONFIG = {
	"anim": "katana/attack_c3_2",
	"hitbox_name": "C3",
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
	"iai_reward": 5,
	"hit_sfx_type": "hit",
	"action_type": Weapon.ActionType.SKILL
}

func enter() -> void:
	super.enter()
	weapon.step_cooldown = 0.15
	weapon.air_attack_locked = false
	weapon.is_attacking = true
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	weapon.combo_step = 21
	
	# 🌟 呼叫純淨接口，拍入 CONFIG
	weapon._play_martial_art_attack(CONFIG)
	print("⚔️ [武藝卡帶] 發動：裂地連斬·貳 (21)")

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	new_x = move_toward(new_x, 0.0, base_friction)
	
	if not player.is_on_floor(): 
		# 🌟 動態安全獲取：確保就算裝在沒有 air_skill_gravity_rate 的武器上也不會報錯
		var gravity_rate = weapon.get("air_skill_gravity_rate") if "air_skill_gravity_rate" in weapon else 0.25
		new_y += (player.default_gravity * gravity_rate) * delta

	return Vector2(new_x, new_y)

func is_handling_gravity() -> bool:
	return not player.is_on_floor()
