class_name Art_Katana_11
extends MartialArt

# 🌟 招式 11 的所有數據完全收歸卡帶自己管，徹底與老爸解耦
const CONFIG = {
	"anim": "katana/attack_c1",
	"hitbox_name": "C1",
	"type": Damage.Type.HEAVY,
	"knockback": Vector2(0.0, -400.0),
	"shake": 20.0,
	"shake_on_hit_only": false,
	"base_dmg": 560,
	"hit_sfx_type": "hit_2",
	"energy": 10,
	"switch": 15,
	"iai_reward": 5,
	"spark_type": 1,      # 🌟 歸還：原本硬編碼在老爸身上的特效類型
	"spark_scale": 0.8,   # 🌟 歸還：原本硬編碼在老爸身上的特效縮放
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

	weapon.combo_step = 11
	# 🌟 核心修改：改為呼叫新接口，直接把卡帶自帶的 CONFIG 拍過去！
	weapon._play_martial_art_attack(CONFIG)

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	new_x = move_toward(new_x, 0.0, base_friction)
	return Vector2(new_x, new_y)
