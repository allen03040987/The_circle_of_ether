class_name Art_Katana_22
extends MartialArt

# 🌟 核心解耦：卡帶自己預載劍氣場景！不再依賴老爸
const SWORD_WAVE_SCENE = preload("res://player/Katana/c_3_wave.tscn")

# 🌟 招式 22 的專屬數據
const CONFIG = {
	"anim": "katana/attack_c3_3",
	"hitbox_name": "None",
	"type": Damage.Type.HEAVY,
	"knockback": Vector2.ZERO,
	"shake": 30.0,
	"shake_on_hit_only": true,
	"base_dmg": 932,
	"energy": 15,
	"switch": 20,
	"iai_reward": 10,
	"action_type": Weapon.ActionType.SKILL
}

func enter() -> void:
	super.enter()
	weapon.step_cooldown = 0.15
	weapon.air_attack_locked = false
	weapon.is_attacking = true
	weapon.is_wave_fired = false # 確保每次發動重置狀態
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	weapon.combo_step = 22
	# 🌟 呼叫純淨接口
	weapon._play_martial_art_attack(CONFIG)
	print("⚔️ [武藝卡帶] 發動：斷空劍氣 (22) —— 劍氣裝填完畢！")

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# 🌟 觸發劍氣
	if player.animation_player.current_animation_position >= 0.32 and not weapon.is_wave_fired:
		weapon.is_wave_fired = true
		if CombatManager.has_method("apply_camera_shake"): 
			CombatManager.apply_camera_shake(20.0) 
		_spawn_sword_wave() # 🌟 改為呼叫自己卡帶內部的發射函數！

	new_x = move_toward(new_x, 0.0, base_friction)
	
	if not player.is_on_floor(): 
		# 動態獲取老爸的空戰重力倍率
		var gravity_rate = weapon.get("air_skill_gravity_rate") if "air_skill_gravity_rate" in weapon else 0.25
		new_y += (player.default_gravity * gravity_rate) * delta

	return Vector2(new_x, new_y)

func is_handling_gravity() -> bool:
	return not player.is_on_floor()

# ==========================================
# 🌊 終極解耦：卡帶自己負責生成、設定與接收劍氣回饋！
# ==========================================
func _spawn_sword_wave() -> void:
	if not SWORD_WAVE_SCENE: return
	var wave = SWORD_WAVE_SCENE.instantiate()
	player.get_tree().current_scene.add_child(wave)
	
	wave.global_position = player.global_position + Vector2(30 * player.direction, -20)
	wave.set("direction", player.direction)
	
	# 等待一幀讓 Node 準備好
	await player.get_tree().process_frame 
	if not is_instance_valid(wave) or not wave.get("hitbox"): return
	
	wave.hitbox.spark_type = 0
	wave.hitbox.spark_color = Color(0.7, 1.5, 0.5, 1.0)
	wave.hitbox.aura_color = Color(0, 1, 1, 1)
	
	# 設定劍氣飛行物理與縮放
	wave.set("speed", 1500.0)
	wave.set("max_distance", 1200.0)
	wave.scale = Vector2(2.0 * player.direction, 2.0)
	
	# 從 CONFIG 中精準抓取數據並寫入判定框
	wave.hitbox.damage_amount = max(1, roundi(float(CONFIG["base_dmg"])))
	wave.hitbox.absolute_knockback = Vector2(400.0 * player.direction, 0.0)
	wave.hitbox.knockback_force = Vector2(400.0, -400.0)
	wave.hitbox.attack_type = Damage.Type.LIGHT
	wave.hitbox.spark_scale = 0.3
	wave.hitbox.hit_sfx_type = "hit_4"
	
	var w_energy = float(CONFIG["energy"])
	var w_iai = int(CONFIG["iai_reward"])
	var wave_state = [false] 
	
	# 建立專屬監聽器，打中敵人時把錢存進本尊口袋
	wave.hitbox.hit.connect(func(hurtbox: Node):
		if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: return
		if not wave_state[0]:
			if weapon.has_method("gain_iai"):
				weapon.gain_iai(w_iai)
			if player.has_method("add_weapon_resource"): 
				player.add_weapon_resource(weapon.get("WEAPON_ID"), w_energy)
			wave_state[0] = true
	)
