class_name Art_Katana_6
extends MartialArt
## 太刀專屬大招卡帶 (Ultimate Dimensional Slash) - 訊號驅動完美版

var _zoom_phase: int = 0
var _is_time_stop_triggered: bool = false
var _is_ending: bool = false

func _ready() -> void:
	art_id = "katana_ult"
	art_name = "次元斬·絕"
	energy_cost = 8.0 # 大招吃滿整條能量條，Weapon.execute_martial_art() 統一扣費，這裡不用自己扣

func enter() -> void:
	super.enter()
	weapon.combo_step = 31
	_is_time_stop_triggered = false
	_is_ending = false

	# 🌟 核心加固 1：改用官方訊號監聽！徹底杜絕物理幀漏掉動畫幀的問題
	if not player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.connect(_on_animation_finished)

	var config = {
		"anim": "katana/Art_Katana_6_start", "hitbox_name": "ArtKatana_6",
		"type": Damage.Type.HEAVY, "base_dmg": 150, "max_hits": 20, "interval": 0.1, "sticky": true,
		"knockback": Vector2(10.0, -100.0), "shake": 5.0, "shake_on_hit_only": true, "hit_sfx_type": "hit",
		"spark": {"type": Hitbox.SparkType.SLASH_3, "scale": 0.55, "random_offset": Vector2(20.0, 20.0)},
		"action_type": Weapon.ActionType.MARTIAL_ART,
	}
	weapon.combo_step = 22
	weapon._play_martial_art_attack(config)
	player.invincible_time_left = 3.0

# 🌟 核心加固 2：用絕對精準的事件中繼站來控制招式生命週期
func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "katana/Art_Katana_6_start" and not _is_ending:
		_is_ending = true
		weapon.combo_step = 32
		var end_config = {
			"anim": "katana/Art_Katana_6_end", "hitbox_name": "None", "type": Damage.Type.LIGHT,
			"knockback": Vector2.ZERO, "shake": 0.0, "shake_on_hit_only": true,
			"base_dmg": 0,
		}
		weapon._play_martial_art_attack(end_config)
		player.invincible_time_left = 0.5

	elif anim_name == "katana/Art_Katana_6_end" and _is_ending:
		_finish_art()

func get_current_velocity(delta: float) -> Vector2:
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta
	var new_x = move_toward(player.velocity.x, 0.0, base_friction * 5.0)

	if _is_ending:
		return Vector2(new_x, 0.0)

	var anim_time = player.animation_player.current_animation_position

	# --- ⏱️ 時停與運鏡邏輯（純數值控制，不再干涉招式退出） ---
	if anim_time >= 0.05 and not _is_time_stop_triggered:
		_is_time_stop_triggered = true
		if player.has_method("trigger_time_stop"): player.trigger_time_stop(3.0, 0.001)
		player.animation_player.speed_scale = 1.0 / 0.001
		player.invincible_time_left = 3.0

	if anim_time >= 0.05 and _zoom_phase == 0:
		_zoom_phase = 1
		weapon._apply_charge_zoom(Vector2(1.2, 1.2), 0.3)

	if anim_time >= 0.70 and _zoom_phase == 1:
		_zoom_phase = 2
		if CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(100.0, 0.07)
		weapon._apply_charge_zoom(Vector2(0.85, 0.85), 0.1)

	if anim_time >= 0.82 and _zoom_phase == 2:
		_zoom_phase = 3
		weapon._apply_charge_zoom(Vector2(0.65, 0.65), 1.8)

	if anim_time >= 2.80 and _zoom_phase == 3:
		_zoom_phase = 4
		if CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(180.0, 0.15)
		weapon._apply_charge_zoom(Vector2(1.0, 1.0), 0.2)

	return Vector2(new_x, 0.0)

func is_handling_gravity() -> bool:
	return true

func cancel() -> void:
	_finish_art()
	super.cancel()

func _finish_art() -> void:
	is_active = false

	# 🌟 核心加固 3：安全斷開訊號，防止記憶體殘留與重複觸發
	if player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.disconnect(_on_animation_finished)

	# 🌟 核心加固 4：暴力將播放速度還原為 1.0！徹底解鎖下一招或 Idle 的動畫停滯！
	player.animation_player.speed_scale = 1.0

	if _is_time_stop_triggered:
		if player.has_method("clear_time_stop"): player.clear_time_stop()
	if weapon.has_method("_apply_charge_zoom"):
		weapon._apply_charge_zoom(Vector2(1.0, 1.0), 0.4)
