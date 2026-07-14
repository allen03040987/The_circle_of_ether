class_name Art_Katana_5
extends MartialArt

const SWORD_WAVE_SCENE = preload("res://player/Katana/c_3_wave.tscn")

const CONFIG = {
	"anim": "katana/Art_Katana_5",
	"hitbox_name": "None",
	"type": Damage.Type.HEAVY,
	"knockback": Vector2.ZERO,
	"shake": 50.0,
	"shake_on_hit_only": true,
	"base_dmg": 932,
	"spark": {"type": Hitbox.SparkType.SLASH , "scale": 0.45},
	"action_type": Weapon.ActionType.MARTIAL_ART
}

# 🌟 蓄力三階段狀態宣告
enum Stage { START, LOOP, FIRE }
var current_stage: Stage = Stage.START

var charge_timer: float = 0.0   # 蓄力時間計時器
var waves_to_fire: int = 1      # 總共要發射的劍氣數量
var waves_fired: int = 0        # 已經發射的數量
var wave_fire_timer: float = 0.0# 連發間隔計時器
var last_charge_level: int = 0  # 🌟 新增：用來紀錄上一次的蓄力階數 (0, 1, 2, 3)

func _ready() -> void:
	energy_cost = 4.0

# 🌟 按鍵偵測：普攻/戰技 + 三個武藝卡帶按鍵都要抓，不然放在 art_3(滑鼠中鍵) 這種沒有跟 attack/heavy_attack 共用實體按鍵的槽位，
# 蓄力會被誤判成「放開了」直接擊發——art_1/art_2 因為剛好跟 attack/heavy_attack 共用左鍵/右鍵，之前才會「碰巧」正常
func _check_holding() -> bool:
	return Input.is_action_pressed("attack") or Input.is_action_pressed("heavy_attack") \
		or Input.is_action_pressed("art_1") or Input.is_action_pressed("art_2") or Input.is_action_pressed("art_3")

func enter() -> void:
	super.enter()
	
	# 初始化狀態機
	current_stage = Stage.START
	charge_timer = 0.0
	waves_to_fire = 1
	waves_fired = 0
	wave_fire_timer = 0.0
	last_charge_level = 0
	
	if not player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.connect(_on_animation_finished)
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	# 🌟 第一步：播放蓄力起手前搖動畫
	weapon.combo_step = 30
	player.play_safe_anim("katana/Art_Katana_5_start") # 填入你專案中的起手動畫名
	print("⚔️ [武藝卡帶] 發動：斷空劍氣 —— 蓄力開始！")

func _on_animation_finished(anim_name: String) -> void:
	# 🌟 分支 A：起手前搖播完了
	if current_stage == Stage.START and anim_name == "katana/Art_Katana_5_start":
		if _check_holding():
			current_stage = Stage.LOOP
			player.play_safe_anim("katana/Art_Katana_5_loop")
			print("🔄 玩家持續按壓：轉入蓄力循環 (Loop)...")
		else:
			_start_firing()

	# 🌟 分支 B：發射動畫播完了
	elif current_stage == Stage.FIRE and anim_name == CONFIG["anim"]:
		# 核心修復：拔除 if waves_fired >= waves_to_fire 限制！
		# 只要出刀動畫播完，就算因為浮點數誤差少射了一發，也必須強制收招，解鎖玩家！
		_finish_art()
		print("🏁 斷空劍氣：動畫自然播放完畢，強制收招解鎖。")

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# ------------------------------------------
	# ⏱️ 階段 0 與 1：蓄力計時與轉向區 (START 與 LOOP 均適用)
	# ------------------------------------------
	if current_stage == Stage.START or current_stage == Stage.LOOP:
		charge_timer += delta
		
		# 🌟 修改：將震動提示上限改為 3 階 (第 3 秒滿階)
		var current_level = int(charge_timer) 
		if current_level > last_charge_level and current_level <= 3:
			last_charge_level = current_level
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(12.0) 
				if current_level == 3:
					print("⚡ 斷空劍氣：蓄力滿階 (6發)！可繼續扣招等待時機...")
				else:
					print("⚡ 斷空劍氣：蓄力進入第 ", current_level, " 階！")
		
		var input_dir = Input.get_axis("move_left", "move_right")
		if input_dir != 0 and player is Player:
			player.direction = 1 if input_dir > 0 else -1
			
		if current_stage == Stage.LOOP:
			# 維持強制擊發門檻為 8.0 秒
			if not _check_holding() or charge_timer >= 8.0:
				_start_firing()
				
	# ------------------------------------------
	# 🚀 階段 2：發射中 (間隔 0.07 秒連發)
	# ------------------------------------------
	elif current_stage == Stage.FIRE:
		var anim_pos = player.animation_player.current_animation_position
		var anim_len = player.animation_player.current_animation_length # 🌟 新增：獲取當前動畫總長度
		
		if anim_pos >= 0.02:
			if waves_fired < waves_to_fire:
				wave_fire_timer -= delta
				if wave_fire_timer <= 0.0:
					# 第一發爆發大震動
					if waves_fired == 0 and CombatManager.has_method("apply_camera_shake"):
						CombatManager.apply_camera_shake(CONFIG["shake"], 0.2)
						
					wave_fire_timer = 0.07 
					_spawn_sword_wave()
					waves_fired += 1
			
			# 🌟 核心重構：智慧型動態動畫扣留守衛
			# 如果劍氣還沒全部吐完，且動畫已經快走到終點了（距離結束不到 0.04 秒）➔ 立刻強設定格暫停！
			# 這樣不管你的出刀動畫是 0.3 秒還是 1 秒短，都絕對能在結尾前扣住動畫，讓 6 發劍氣安穩射完！
			if waves_fired < waves_to_fire and anim_pos >= (anim_len - 0.04):
				player.animation_player.pause()
				
			# 劍氣終於全部射完了，且動畫目前處於暫停定格狀態 ➔ 恢復播放，讓老爸把刀收回去
			elif waves_fired >= waves_to_fire and not player.animation_player.is_playing():
				player.animation_player.play()
				
			# 🌟 核心重構：安全回歸網
			# 劍氣射完，且動畫走到最後邊緣，順暢呼叫收招
			if waves_fired >= waves_to_fire and anim_pos >= (anim_len - 0.05):
				_finish_art()

	# ------------------------------------------
	# 🛑 常規煞車與重力計算
	# ------------------------------------------
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
	
	# 💡 小細節：如果連發，可以稍微讓每一發的大小或判定有些微差異
	wave.scale = Vector2(2.0 * player.direction, 2.0)
	
	wave.hitbox.damage_amount = max(1, roundi(float(CONFIG["base_dmg"])))
	wave.hitbox.absolute_knockback = Vector2(100.0 * player.direction, 0.0)
	wave.hitbox.knockback_force = Vector2(100.0, -400.0)
	wave.hitbox.attack_type = Damage.Type.LIGHT
	wave.hitbox.spark_scale = 0.3
	wave.hitbox.hit_sfx_type = "hit"

# 🌟 輔助函數：執行擊發狀態切換
# 🌟 輔助函數：執行擊發狀態切換
func _start_firing() -> void:
	current_stage = Stage.FIRE
	
	# 🌟 核心修改：精準的階梯式劍氣數量判定
	if charge_timer < 1.0:
		waves_to_fire = 1
	elif charge_timer < 2.0:
		waves_to_fire = 2
	elif charge_timer < 3.0:
		waves_to_fire = 4
	else:
		waves_to_fire = 6
	
	# 在放開按鍵、出刀發射的一瞬間，觸發爆發震動！
	if CombatManager.has_method("apply_camera_shake"): 
		CombatManager.apply_camera_shake(CONFIG["shake"], 0.2) 
	
	weapon.combo_step = 21
	weapon._play_martial_art_attack(CONFIG)
	print("💥 斷空釋放！蓄力時間: ", snapped(charge_timer, 0.1), " 秒 ➔ 擊發數量: ", waves_to_fire)
	
func cancel() -> void:
	# 🌟 蓄力期間（START/LOOP，還沒放出任何一發劍氣）被強制打斷：退還部分武藝能量，不讓玩家血本無歸
	if current_stage == Stage.START or current_stage == Stage.LOOP:
		if is_instance_valid(player) and player.has_method("gain_martial_energy"):
			player.gain_martial_energy(2.0)
			print("↩️ 斷空劍氣蓄力中被打斷，返還 2 點武藝能量")

	_finish_art()
	super.cancel()

func _finish_art() -> void:
	is_active = false
	if player.animation_player.animation_finished.is_connected(_on_animation_finished):
		player.animation_player.animation_finished.disconnect(_on_animation_finished)
	player.animation_player.speed_scale = 1.0
