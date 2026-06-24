class_name Katana
extends Weapon
## 武器腳本：太刀 (Katana) 
## 負責處理太刀專屬的連段派生與大招運鏡 (已剝離共鳴與底層蓄力)。

# ==========================================
# 🎛️ 1. 武器核心參數
# ==========================================
@export_group("武器核心參數")
@export var combo_timeout: float = 0.3      
@export var no_sheath_steps: Array[int] = [1, 11, 12, 31, 32, 99] # 招式代號已更新
@export var ult_energy_cost: float = 100.0  

const WEAPON_ID: String = "katana"          
const DIMENSIONAL_SLASH_SCENE = preload("res://Explod/tscn/Dimensional Slash.tscn")
const SWORD_WAVE_SCENE = preload("res://player/Katana/c_3_wave.tscn")

# ==========================================
# 🥋 專屬武藝系統 (Martial Arts Loadout)
# ==========================================
@export var equipped_martial_arts: Array[String] = [
	"res://player/MartialArts/Katana/Art_Katana_1.gd", 
	"res://player/MartialArts/Katana/Art_Katana_2.gd", 
	"res://player/MartialArts/Katana/Art_Katana_3.gd"
]

func _ready() -> void:
	super._ready() 
	call_deferred("_delayed_load_arts")

func _delayed_load_arts() -> void:
	load_martial_arts(equipped_martial_arts)

const ZOOM_LEVELS = { 0: Vector2(1.0, 1.0), 1: Vector2(1.01, 1.01), 2: Vector2(1.02, 1.02), 3: Vector2(1.03, 1.03) }

# ==========================================
# 📖 2. 招式數據庫 (Data-Driven Combat Config)
# ==========================================

# 🗡️ [地面普攻字典] (代號: 1 ~ 5)
const DICT_LIGHT_GROUND = {
	1: {"anim": "katana/light_1", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(100.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit_3", "energy": 200, "switch": 500, "action_type": Weapon.ActionType.NORMAL},
	2: {"anim": "katana/light_2", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(150.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5, "action_type": Weapon.ActionType.NORMAL},
	3: {"anim": "katana/light_3", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(200.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5, "action_type": Weapon.ActionType.NORMAL},
	4: {"anim": "katana/light_4", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(200.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5, "action_type": Weapon.ActionType.NORMAL},
	5: {"anim": "katana/light_5", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(400.0, 0.0), "shake": 30.0, "hit_sfx_type": "hit_5", "base_dmg": 645, "energy": 2, "switch": 5, "action_type": Weapon.ActionType.NORMAL},
	# 🌟 新增：長按普攻派生 (代號 10) - 極高擊退力與傷害！
	10: {"anim": "katana/light_enhanced", "hitbox_name": "C0", "max_hits": 1, "interval": 0.0, "knockback": Vector2(650.0, -300.0), "shake": 25.0, "hit_sfx_type": "hit_5", "base_dmg": 850, "energy": 10, "switch": 15, "action_type": Weapon.ActionType.NORMAL}
}


# 🦅 [空中連段字典] (代號: 11, 12)
const DICT_LIGHT_AIR = {
	11: { "anim": "katana/air_light_1", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "type": Damage.Type.LIGHT, "knockback": Vector2(20.0, -200.0), "base_dmg": 300,"hit_sfx_type": "hit", "energy": 2, "switch": 4, "action_type": Weapon.ActionType.NORMAL},
	12: { "anim": "katana/air_light_2", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "type": Damage.Type.LIGHT, "knockback": Vector2(200.0, -300.0), "base_dmg": 300,"hit_sfx_type": "hit", "energy": 2, "switch": 4, "action_type": Weapon.ActionType.NORMAL},
}

# 💥 [戰技與大招字典] (代號: 21, 31, 32)
const DICT_HEAVY_ULT = {
	21: { "anim": "katana/heavy_1", "hitbox_name": "C2", "type": Damage.Type.LIGHT, "knockback": Vector2(100.0, 0.0), "shake": 2.0, "shake_on_hit_only": true, "base_dmg": 200, "hit_sfx_type": "hit", "energy": 10, "switch": 15, "max_hits": 3, "interval": 0.1, "sticky": true },
	# 🌟 三段式下墜戰技配置
	25: { "anim": "katana/air_heavy_start", "hitbox_name": "None", "base_dmg": 0 }, # 階段 1：下墜前準備（無判定）
	26: { "anim": "katana/air_heavy_loop", "hitbox_name": "Air_J", "type": Damage.Type.LIGHT, "knockback": Vector2(200.0, 0.0), "base_dmg": 120, "max_hits": 5, "interval": 0.1, "hit_sfx_type": "hit", "sticky": true }, # 階段 2：下墜循環（帶有多段向下拖拽判定）
	27: { "anim": "katana/air_heavy_land", "hitbox_name": "None", "type": Damage.Type.HEAVY, "knockback": Vector2(500.0, -250.0), "shake": 45.0, "shake_on_hit_only": false, "base_dmg": 750, "hit_sfx_type": "hit", "action_type": Weapon.ActionType.SKILL },
	30: { "anim": "katana/sheath_enhanced_loop", "hitbox_name": "None", "base_dmg": 0 },
	31: { "anim": "katana/sheath_enhanced", "hitbox_name": "attack_tsubame", "type": Damage.Type.HEAVY, "knockback": Vector2(0.0, -80.0), "shake": 0.0, "shake_on_hit_only": true, "base_dmg": 200, "hit_sfx_type": "hit", "energy": 25, "switch": 30, "max_hits": 12, "interval": 0.1, "sticky": true, "action_type": Weapon.ActionType.SKILL },
}

# ==========================================
# 🚀 3. 物理運算與手感參數
# ==========================================
@export_group("戰技中立設定")
@export var skill_neutral_friction_rate: float = 0.2 

@export_group("空戰設定 (Air Combat)")
@export var min_air_attack_height: float = 40.0 
@export var air_thrust_force: float = -150.0    
@export var air_skill_gravity_rate: float = 0.25 

# --- 內部狀態 ---
var current_active_hitbox: Hitbox = null

var _current_energy_reward: float = 0.0
var _current_switch_reward: float = 0.0
var _multi_hit_energy: bool = false
var _has_granted_resources_this_step: bool = false

var combo_step: int = 0
var last_attack_time: float = 0.0
var is_attacking: bool = false
var light_hold_timer: float = 0.0
var step_cooldown: float = 0.0                  

var air_attack_locked: bool = false             

var is_time_stop_triggered: bool = false 
var _camera_tween: Tween 
var _is_hitbox_locked: bool = false

# 🌟 閃避充能資源 (借用舊的居合變數讓 UI 無縫接軌)
var current_iai: int = 0                    
const MAX_IAI: int = 20 # 滿層條件設定為 20 次！
var heavy_hold_timer: float = 0.0 # 專屬戰技蓄力計時器
var _tsubame_zoom_phase: int = 0    # 🌟 歸還：燕返專屬運鏡階段控制
var is_wave_fired: bool = false

func gain_iai(amount: int) -> void:
	current_iai = mini(current_iai + amount, MAX_IAI)
	print("✨ 極限閃避成功！目前強化戰技充能: ", current_iai, "/", MAX_IAI)
# ==========================================
# 🎬 實作 Weapon.gd 合約接口
# ==========================================
func start_light_attack() -> void:
	if step_cooldown > 0: return 
	step_cooldown = 0.15

	if is_instance_valid(active_martial_art):
		active_martial_art.cancel()
		active_martial_art = null

	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time > combo_timeout:
			combo_step = 0

	# --- 🦅 空戰邏輯 (🌟 核心修復：還原空中普攻連段) ---
	if not player.is_on_floor():
		if air_attack_locked or _get_ground_distance() < min_air_attack_height:
			return
		if combo_step == 11:
			combo_step = 12
			air_attack_locked = true 
		else:
			combo_step = 11
		is_attacking = true
		_play_air_step(combo_step)
		return

	# --- 🗡️ 陸戰邏輯 ---
	if DICT_HEAVY_ULT.has(combo_step):
		combo_step = 0

	combo_step += 1
	if not DICT_LIGHT_GROUND.has(combo_step):
		combo_step = 1

	is_attacking = true
	_play_light_step(combo_step)

func start_heavy_attack() -> void:
	if step_cooldown > 0:
		is_attacking = false
		return
	
	step_cooldown = 0.15
	air_attack_locked = false
	
	if is_instance_valid(active_martial_art):
		active_martial_art.cancel()
		active_martial_art = null
		
	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time > combo_timeout:
			combo_step = 0
			
	is_attacking = true
	is_time_stop_triggered = false 
	
	# 🌟 空戰邏輯：進入第 1 階段「下墜前準備」
	if not player.is_on_floor():
		combo_step = 25
		heavy_hold_timer = 0.0
		
		var input_dir = Input.get_axis("move_left", "move_right")
		if input_dir != 0 and player is Player:
			player.direction = 1 if input_dir > 0 else -1
			
		# 🌟 核心修改：發動瞬間給予老爸一個強烈向上的物理速度！
		player.velocity.y = air_thrust_force * 2.0
			
		_play_heavy_ult_step(25)
		print("🦅 空中重擊：躍起並進入下墜前準備 (25)")
		return

	# 🌟 陸戰邏輯 (徹底拔除殘留的錯誤能量判斷，還原純淨手感)
	combo_step = 21
	heavy_hold_timer = 0.0
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1
		
	_play_heavy_ult_step(21)
	skill_1_timer = skill_1_cd

func update_timers_only(delta: float) -> void:
	if step_cooldown > 0: step_cooldown -= delta 
	if skill_1_timer > 0: skill_1_timer -= delta
	if ult_timer > 0: ult_timer -= delta
			
	if player.is_on_floor():
		air_attack_locked = false 
		if not is_attacking and combo_step in [11, 12]:
			combo_step = 0

func get_current_velocity(delta: float) -> Vector2:
	if is_instance_valid(active_martial_art) and active_martial_art.is_active:
		return active_martial_art.get_current_velocity(delta)
		
	if not is_attacking:
		return player.velocity

	if player.is_on_floor(): air_attack_locked = false

	# ==========================================
	# 🌟 戰技長按偵測與強化戰技蓄力 (無縫派生)
	# ==========================================
	if combo_step in [21, 30]:
		if Input.is_action_pressed("heavy_attack"): 
			heavy_hold_timer += delta
			
			# 1️⃣ 在戰技 (21) 起手前 0.1 秒內，如果按住不放且資源滿了，切換進入蓄力狀態 (30)
			if combo_step == 21 and heavy_hold_timer >= 0.2 and current_iai >= MAX_IAI:
				combo_step = 30
				_play_heavy_ult_step(30)
				print("⚡ 偵測到長按！取消一般戰技，轉入燕返蓄力...")
				
			# 2️⃣ 總蓄力時間滿 1.0 秒，釋放終極燕返 (31)
			elif combo_step == 30 and heavy_hold_timer >= 1.0:
				current_iai = 0             # 扣除資源
				combo_step = 31             # 💥 轉為終極燕返狀態！
				heavy_hold_timer = 0.0
				_tsubame_zoom_phase = 0     
				is_wave_fired = false       
				
				# 允許拔刀前極限轉向
				var input_dir = Input.get_axis("move_left", "move_right")
				if input_dir != 0 and player is Player:
					player.direction = 1 if input_dir > 0 else -1
					
				_play_heavy_ult_step(31)
				print("💥 蓄力 1 秒完成！終極燕返拔刀斬！！！")
				
		else:
			# 如果玩家放開了戰技鍵
			if combo_step == 30:
				# 🌟 核心修改：已經進入蓄力，但沒滿 1 秒就放開 ➔ 打出一般戰技！(不扣資源)
				combo_step = 21
				heavy_hold_timer = 0.0
				
				# 貼心設計：讓玩家在放開的瞬間還可以做最後的轉向
				var input_dir = Input.get_axis("move_left", "move_right")
				if input_dir != 0 and player is Player:
					player.direction = 1 if input_dir > 0 else -1
					
				_play_heavy_ult_step(21)
				print("💨 蓄力提早釋放！轉為一般戰技 (21)！")
			else:
				# 還在起手 21 號狀態就放開 ➔ 判定為一般點按，正常打完 21 號戰技
				heavy_hold_timer = 0.0

	if player.is_on_floor(): air_attack_locked = false

	var new_x = player.velocity.x
	var new_y = player.velocity.y

	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# ==========================================
	# 🌟 長按計時與派生偵測
	# ==========================================
	if Input.is_action_pressed("attack"):
		light_hold_timer += delta
	else:
		light_hold_timer = 0.0

	# 如果目前正在揮舞普攻 1~5 段，且按住超過 0.3 秒，立刻派生橫斬！
	if combo_step in [1, 2, 3, 4, 5]:
		if light_hold_timer >= 0.3:
			# 發動前允許極限轉向
			var input_dir = Input.get_axis("move_left", "move_right")
			if input_dir != 0 and player is Player:
				player.direction = 1 if input_dir > 0 else -1
				
			combo_step = 10 
			light_hold_timer = 0.0 # 清空計時器
			_play_light_step(combo_step)
			print("🔥 普攻長按觸發：高擊退橫斬！")

	# ==========================================
	# 🏃 物理位移狀態機
	# ==========================================
	if combo_step == 21: 
		new_x = move_toward(new_x, 0.0, base_friction * skill_neutral_friction_rate)
	
	# ==========================================
	# 🌪️ 31 號終極燕返：時停、無敵、運鏡與判定框突變
	# ==========================================
	elif combo_step == 31: 
		# 遵循最高指導原則：只計算摩擦力與空中阻力，不干涉原生 custom_move_and_slide!
		new_x = move_toward(new_x, 0.0, base_friction * 5.0)
		new_y = 0.0 if player.is_on_floor() else player.default_gravity * air_skill_gravity_rate * delta 
		
		var anim_time = player.animation_player.current_animation_position
		
		# 1️⃣ 0.08 秒：觸發極限無敵幀
		if anim_time >= 0.08 and not is_time_stop_triggered:
			is_time_stop_triggered = true 
			if player is Player: 
				player.invincible_time_left = 2.0 
			
		# 2️⃣ 0.10 秒：拉近特寫鏡頭
		if anim_time >= 0.10 and _tsubame_zoom_phase == 0:
			_tsubame_zoom_phase = 1
			_apply_charge_zoom(Vector2(0.75, 0.75), 1.6) 
				
		# 3️⃣ 1.76 秒：多段斬擊結束，瞬間突變為 1500 傷害的大斬擊，並更換網格形狀！
		if anim_time >= 1.76 and not is_wave_fired:
			is_wave_fired = true 
			if CombatManager.has_method("apply_camera_shake"): 
				CombatManager.apply_camera_shake(60.0) 
				
			if is_instance_valid(current_active_hitbox):
				current_active_hitbox.hit_targets.clear() 
				current_active_hitbox.max_hits = 1        
				current_active_hitbox.sticky_multi_hit = false 
				current_active_hitbox.damage_amount = 1500 
				current_active_hitbox.knockback_force = Vector2(200.0, -500.0) 
				current_active_hitbox.shake_intensity = 400.0
				_has_granted_resources_this_step = false
				
			_is_hitbox_locked = false 
			disable_hitbox() 
			enable_hitbox("CollisionShape2D2") # 啟動大範圍終結形狀
			
	elif combo_step == 10: # 🌟 10 號長按橫斬：發招瞬間給予一點向前突進！
		var anim_time = player.animation_player.current_animation_position
		new_x = move_toward(new_x, 0.0, base_friction)

	elif combo_step in [11, 12]:
		new_x = move_toward(new_x, 0.0, base_friction)
		
	# ==========================================
	# 🦅 三段式下墜戰技物理控速
	# ==========================================
	elif combo_step == 25:
		# 【下墜前】：主動向上推力
		new_x = move_toward(new_x, 0.0, base_friction * 0.2)
		new_y = air_thrust_force * 1.5 * speed_mult 

	elif combo_step == 26:
		# 【下墜循環】：🌟 核心修改 ➔ 均速斜向下砸！
		# 給予 X 軸固定向前的速度 (例如 500.0，可自由調整)，配合 Y 軸形成斜角衝鋒！
		new_x = player.direction * 500.0 * speed_mult 
		new_y = 800.0 * speed_mult 
		
		# 智慧落地偵測
		if player.is_on_floor():
			combo_step = 27
			_play_heavy_ult_step(27)
			if CombatManager.has_method("apply_camera_shake"): 
				CombatManager.apply_camera_shake(45.0, 0.18)
			print("💥 觸地！轉換為落地擊碎衝擊 (27)")

	elif combo_step == 27:
		# 【落地】：縱向速度完全歸零，橫向套用基準摩擦力進行收招煞車
		new_x = move_toward(new_x, 0.0, base_friction)
		new_y = 0.0
	else:
		new_x = move_toward(new_x, 0.0, base_friction)

	return Vector2(new_x, new_y)
	
func is_handling_gravity() -> bool:
	if is_instance_valid(active_martial_art) and active_martial_art.is_active:
		if active_martial_art.has_method("is_handling_gravity"): return active_martial_art.is_handling_gravity()
			
	# 🌟 允許 25(下墜前) 與 26(下墜循環) 全權接管重力更新
	if not player.is_on_floor() and combo_step in [25, 26, 31]: return true
	return false

# ==========================================
# 🎬 招式結束判定 (高階訊號驅動卡帶專用防護版)
# ==========================================
func is_attack_finished() -> bool:
	# 🌟 1. 優先處理「武藝卡帶」的生命週期！(絕對免疫動畫首幀延遲)
	if is_instance_valid(active_martial_art):
		if active_martial_art.is_active:
			return false # 卡帶還在跑，總監絕對不准卡歌！
		else:
			# 卡帶剛剛宣告自己跑完了 (觸發了 _finish_art)
			active_martial_art = null
			_is_hitbox_locked = true 
			disable_hitbox()
			
			# 🌟 讓系統標記為正常收招，防止被總監當作打斷而取消收刀！
			is_attacking = false
			last_attack_time = Time.get_ticks_msec() / 1000.0
			
			
			# 判斷是否需要收刀
			if not requires_sheath() and player.get("scabbard"): 
				player.scabbard.fade_in()
			return true 

	# 🌟 2. 一般普攻/空戰/多段普通戰技的生命週期
	if not is_attacking: return true
	
	if not player.animation_player.is_playing():
		# 🌟 核心鏈接：當「下墜前準備 (25)」動畫播完，自動轉入「下墜循環 (26)」
		if combo_step == 25:
			combo_step = 26
			_play_heavy_ult_step(26)
			return false # 告訴總監招式還在跑，繼續留在原狀態
			
		player.is_input_locked = false 
		
		# 空戰普攻打完鎖死
		if combo_step in [11, 12]: 
			air_attack_locked = true
			
		last_attack_time = Time.get_ticks_msec() / 1000.0
		step_cooldown = 0.0
		light_hold_timer = 0.0
		_is_hitbox_locked = true 
		disable_hitbox()
		
		if combo_step == 31 or _tsubame_zoom_phase > 0:
			_tsubame_zoom_phase = 0
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.4)
		
		if not requires_sheath() and player.get("scabbard"): 
			player.scabbard.fade_in()
			
		return true
		
	return false

# ==========================================
# 💥 強制打斷處理 
# ==========================================
func cancel_attack() -> void:
	if is_instance_valid(active_martial_art):
		active_martial_art.cancel()
		active_martial_art = null

	if not player.is_on_floor() and combo_step in [11, 12]: 
		air_attack_locked = true
		
	player.is_input_locked = false 
	_apply_charge_zoom(ZOOM_LEVELS[0])
	
	is_attacking = false
	combo_step = 0
	step_cooldown = 0.0
	_tsubame_zoom_phase = 0
	light_hold_timer = 0.0
	if is_time_stop_triggered:
		is_time_stop_triggered = false
		if player.has_method("clear_time_stop"): player.clear_time_stop() 
	
	_is_hitbox_locked = true 
	disable_hitbox()
	
	if player.get("scabbard"): 
		player.scabbard.fade_in()
		
func requires_sheath() -> bool:
	if combo_step == 0: return false
	return combo_step not in no_sheath_steps
	
# ==========================================
# ⚙️ 內部實作與接口
# ==========================================
func _play_light_step(step: int) -> void:
	disable_hitbox()
	var config: Dictionary = DICT_LIGHT_GROUND[step]
	_apply_hitbox_config(config)
	
	if config.has("sfx") and config["sfx"] != null: AudioManager.play_sfx(config["sfx"], -8.0)
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _play_heavy_ult_step(step: int) -> void:
	disable_hitbox()
	var config: Dictionary = DICT_HEAVY_ULT[step]
	_apply_hitbox_config(config)

	if config.has("sfx") and config["sfx"] != null: AudioManager.play_sfx(config["sfx"], -5.0)

	combo_step = step
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _play_air_step(step: int) -> void:
	disable_hitbox() 
	var config: Dictionary = DICT_LIGHT_AIR[step]
	_apply_hitbox_config(config)
	player.velocity.y = air_thrust_force 
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _play_martial_art_attack(config: Dictionary) -> void:

	disable_hitbox()
	_apply_hitbox_config(config)
	
	if current_active_hitbox:
		if config.has("spark_type"): current_active_hitbox.spark_type = config["spark_type"]
		if config.has("spark_scale"): current_active_hitbox.spark_scale = config["spark_scale"]
	
	if config.has("sfx") and config["sfx"] != null: AudioManager.play_sfx(config["sfx"], -5.0)
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])
	
func _apply_hitbox_config(config: Dictionary) -> void:
	_is_hitbox_locked = false 
	current_action_type = config.get("action_type", Weapon.ActionType.NONE)
	
	var target_hitbox_name = config.get("hitbox_name", "Hitbox")
	var hitbox := get_node_or_null(target_hitbox_name) as Hitbox
	
	if hitbox:
		hitbox.damage_amount = config["base_dmg"]
		hitbox.max_hits = config.get("max_hits", 1)
		hitbox.hit_sfx_type = config.get("hit_sfx_type", "")
		hitbox.hit_interval = config.get("interval", 0.0)
		hitbox.attack_type = config.get("type", Damage.Type.LIGHT)
		hitbox.knockback_force = config.get("knockback", Vector2.ZERO)
		
		var base_kb_x = abs(hitbox.knockback_force.x)
		hitbox.absolute_knockback = Vector2(base_kb_x * player.direction, hitbox.knockback_force.y)
		
		if "shake_intensity" in hitbox: hitbox.shake_intensity = config.get("shake", 2.5)
		if "shake_on_hit_only" in hitbox: hitbox.shake_on_hit_only = config.get("shake_on_hit_only", true)
		hitbox.sticky_multi_hit = config.get("sticky", false)
		
		if "energy_reward" in hitbox: hitbox.energy_reward = float(config.get("energy", 0))
		if "switch_reward" in hitbox: hitbox.switch_reward = float(config.get("switch", 0))
		
		hitbox.spark_type = 0; hitbox.spark_scale = 0.3; hitbox.spark_color = Color(0.7, 1.5, 0.5, 1.0); hitbox.aura_color = Color(0, 1, 1, 1)
		hitbox.hit_targets.clear() 
		
		_current_energy_reward = float(config.get("energy", 0))
		_multi_hit_energy = config.get("multi_hit_energy", false)
		_has_granted_resources_this_step = false
		
		if current_active_hitbox and current_active_hitbox.hit.is_connected(_on_hitbox_hit):
			current_active_hitbox.hit.disconnect(_on_hitbox_hit)
			
		current_active_hitbox = hitbox
		if not current_active_hitbox.hit.is_connected(_on_hitbox_hit):
			current_active_hitbox.hit.connect(_on_hitbox_hit)

func _on_hitbox_hit(hurtbox: Node) -> void:
	if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: return
	if _multi_hit_energy or not _has_granted_resources_this_step:
		if _current_energy_reward > 0:
			if player.has_method("add_weapon_resource"): player.add_weapon_resource(WEAPON_ID, _current_energy_reward)
		_has_granted_resources_this_step = true
		
func _get_ground_distance() -> float:
	var space_state = player.get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(player.global_position, player.global_position + Vector2(0, 1000))
	query.collision_mask = 1 
	var result = space_state.intersect_ray(query)
	if result: return player.global_position.distance_to(result.position)
	return 1000.0 

func _apply_charge_zoom(target_zoom: Vector2, duration: float = 0.2) -> void:
	if not (player is Player): return
	if player.name.begins_with("Phantom"): return
	
	var camera = get_viewport().get_camera_2d()
	if camera:
		if _camera_tween and _camera_tween.is_valid(): _camera_tween.kill()
		_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
		_camera_tween.set_speed_scale(speed_mult)
		
		if target_zoom == ZOOM_LEVELS[0]:
			var final_zoom = CombatManager.base_zoom if CombatManager.get("base_zoom") != null else Vector2(1.0, 1.0)
			_camera_tween.tween_property(camera, "zoom", final_zoom, duration)
			_camera_tween.tween_callback(func():
				if CombatManager.get("is_close_up_active") != null: CombatManager.is_close_up_active = false
			)
		else:
			if CombatManager.get("is_close_up_active") != null: CombatManager.is_close_up_active = true
			_camera_tween.tween_property(camera, "zoom", target_zoom, duration)

func can_air_light() -> bool:
	if air_attack_locked or _get_ground_distance() < min_air_attack_height: return false
	return true

func can_use_heavy() -> bool:
	# 🌟 解除空中鎖死的限制，只要高度夠，普攻打到一半也能無縫接下墜斬！
	if not player.is_on_floor(): 
		if _get_ground_distance() < min_air_attack_height: 
			return false
		return true 
		
	# 陸戰防護維持原樣
	if skill_1_timer > 0: return false
	return true

func can_use_ultimate() -> bool:
	if ult_timer > 0: return false 
	if not player.is_on_floor(): return false 
	if player.has_method("get_weapon_energy"):
		if player.get_weapon_energy(WEAPON_ID) < ult_energy_cost: return false 
	return true

func export_weapon_data() -> Dictionary:
	return {
		"current_iai": current_iai, # 🌟 核心修復：把辛苦存來的閃避能量打包存檔！
		"skill_1_timer": skill_1_timer if "skill_1_timer" in self else 0.0, 
		"ult_timer": ult_timer if "ult_timer" in self else 0.0
	}

func import_weapon_data(data: Dictionary) -> void:
	current_iai = data.get("current_iai", 0) # 🌟 核心修復：切換回來時，精準讀取閃避能量！
	
	if "skill_1_timer" in self: skill_1_timer = data.get("skill_1_timer", 0.0)
	if "ult_timer" in self: ult_timer = data.get("ult_timer", 0.0)
	
func enable_hitbox(shape_name: String = "") -> void:
	if _is_hitbox_locked: return
	if current_active_hitbox:
		for child in current_active_hitbox.get_children():
			if child is CollisionShape2D:
				if shape_name == "" or child.name == shape_name: child.set_deferred("disabled", false)

func disable_hitbox(shape_name: String = "") -> void:
	if current_active_hitbox:
		for child in current_active_hitbox.get_children():
			if child is CollisionShape2D:
				if shape_name == "" or child.name == shape_name: child.set_deferred("disabled", true)
