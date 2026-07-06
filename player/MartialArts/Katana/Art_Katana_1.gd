class_name Art_Katana_1
extends MartialArt
## 逆鱗返：原地格擋預備 5 秒，期間被攻擊就完全格擋、射出劍氣反擊、獲得 1 秒無敵

const SWORD_WAVE_SCENE = preload("res://player/Katana/c_3_wave.tscn")

const CONFIG = {
	"anim": "katana/Art_Katana_1", # 格擋成功出招（反擊劍氣）
	"base_dmg": 700,
	"energy": 15,
	"action_type": Weapon.ActionType.SKILL
}

const ANIM_START := "katana/Art_Katana_1_start" # 格檔前
const ANIM_LOOP := "katana/Art_Katana_1_loop"   # 格檔循環中
const ANIM_END := "katana/Art_Katana_1_end"     # 格檔結束（沒被打斷，時間到自然收招）

const CHANNEL_DURATION: float = 2.0
const COUNTER_INVINCIBLE_DURATION: float = 1.0
const WAVE_FIRE_TIME: float = 0.35 # 劍氣在「格擋成功出招」動畫播到這個時間點才發射

enum Stage { START, LOOP, COUNTER, END }
var current_stage: Stage = Stage.START

var channel_timer: float = 0.0
var has_countered: bool = false
var wave_fired: bool = false
var has_turned: bool = false # 站樁期間只能轉向一次

func enter() -> void:
	super.enter()

	weapon.step_cooldown = 0.15
	weapon.air_attack_locked = false
	weapon.is_attacking = true

	current_stage = Stage.START
	channel_timer = CHANNEL_DURATION
	has_countered = false
	has_turned = false

	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	weapon.combo_step = 11

	if not player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.connect(_on_animation_finished)

	player.play_safe_anim(ANIM_START)
	print("🥋 [逆鱗返] 進入格擋預備，", CHANNEL_DURATION, " 秒內被攻擊將觸發反擊！")

func _on_animation_finished(anim_name: String) -> void:
	match current_stage:
		Stage.START:
			if anim_name == ANIM_START:
				current_stage = Stage.LOOP
				player.play_safe_anim(ANIM_LOOP)
		Stage.END:
			if anim_name == ANIM_END:
				_finish_art()
		Stage.COUNTER:
			if anim_name == CONFIG["anim"]:
				_finish_art()

## 供 Player.gd 在挨打當下呼叫：完全格擋這一下攻擊，射出劍氣反擊並獲得無敵
func trigger_counter() -> void:
	if not is_active or has_countered: return
	has_countered = true
	current_stage = Stage.COUNTER
	wave_fired = false

	player.grant_invincibility(COUNTER_INVINCIBLE_DURATION)
	player.play_safe_anim(CONFIG["anim"])

	if CombatManager.has_method("apply_camera_shake"):
		CombatManager.apply_camera_shake(15.0, 0.1)

	print("⚔️ [逆鱗返] 觸發反擊！獲得 ", COUNTER_INVINCIBLE_DURATION, " 秒無敵，劍氣將於動畫 ", WAVE_FIRE_TIME, " 秒時發射！")

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
	wave.hitbox.absolute_knockback = Vector2(100.0 * player.direction, 0.0)
	wave.hitbox.knockback_force = Vector2(100.0, -400.0)
	wave.hitbox.attack_type = Damage.Type.LIGHT
	wave.hitbox.spark_scale = 0.3
	wave.hitbox.hit_sfx_type = "hit"

	var w_energy = float(CONFIG["energy"])
	var wave_state = [false]

	wave.hitbox.hit.connect(func(hurtbox: Node):
		if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: return
		if not wave_state[0]:
			if player.has_method("add_weapon_resource"):
				player.add_weapon_resource(weapon.get("WEAPON_ID"), w_energy)
			wave_state[0] = true
	)

func get_current_velocity(delta: float) -> Vector2:
	if is_active and not has_countered and current_stage != Stage.END:
		channel_timer -= delta
		if channel_timer <= 0.0:
			current_stage = Stage.END
			player.play_safe_anim(ANIM_END)

	if current_stage == Stage.COUNTER and not wave_fired:
		if player.animation_player.current_animation_position >= WAVE_FIRE_TIME:
			wave_fired = true
			_spawn_sword_wave()
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(20.0, 0.15)

	# 🌟 Loop 階段可以無限轉向；其餘階段（START/COUNTER/END）只有一次轉向權限
	if current_stage == Stage.LOOP:
		var turn_input = Input.get_axis("move_left", "move_right")
		if not is_zero_approx(turn_input):
			player.direction = 1 if turn_input > 0 else -1
	elif not has_turned and is_active:
		var turn_input = Input.get_axis("move_left", "move_right")
		if not is_zero_approx(turn_input):
			var new_dir = 1 if turn_input > 0 else -1
			if new_dir != player.direction:
				player.direction = new_dir
				has_turned = true

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
