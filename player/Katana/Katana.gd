class_name Katana
extends Weapon
## 武器腳本：太刀 (Katana) 
## 負責處理太刀專屬的連段派生、共鳴資源 (居合/燕返)，以及大招運鏡。

# ==========================================
# 🎛️ 1. 武器核心參數與資源
# ==========================================
@export_group("武器核心參數")
@export var combo_timeout: float = 0.3      # 普攻連段超時重置時間
@export var no_sheath_steps: Array[int] = [1, 11, 12, 30, 42, 80, 81] # 不需播收刀動畫的黑名單招式
@export var ult_energy_cost: float = 100.0  # 大招能量成本
@export var dodge_counter_step: int = 4     # 極限閃避後派生的起始段數

const WEAPON_ID: String = "katana"          
const DIMENSIONAL_SLASH_SCENE = preload("res://Explod/tscn/Dimensional Slash.tscn")
const SWORD_WAVE_SCENE = preload("res://player/Katana/c_3_wave.tscn")

# 🎵 🌟 新增：預載太刀揮空音效
const SFX_WAVE = preload("res://sound/SFX/attack/wave.wav") # A1 專用 (輕盈破空聲)
const SFX_CUT = preload("res://sound/SFX/attack/cut.wav")   # A2, A3, A4 (鋒利斬擊聲)

const ZOOM_LEVELS = { 0: Vector2(1.0, 1.0), 1: Vector2(1.05, 1.05), 2: Vector2(1.1, 1.1), 3: Vector2(1.15, 1.15) }

# ==========================================
# 🌀 2. 共鳴迴路 (Resonance Circuit) 變數
# ==========================================
var current_iai: int = 0                    # 當前居合值
var current_tsubame: int = 0                # 當前燕返值
const MAX_IAI: int = 60                     
const MAX_TSUBAME: int = 60                 
var is_tsubame_ready: bool = false          # 強化戰技 (燕返) 是否就緒

# ==========================================
# 📖 3. 招式數據庫 (Data-Driven Combat Config)
# ==========================================
# [普攻字典]
const LIGHT_ATTACK_CONFIG = {
	# 格式：招式編號: { 動畫名稱, 開啟哪個判定框, 最大連擊數, 打擊間隔, 擊退力, 基礎傷害, 大招能量回復, 切換值回復, 專屬居合值回復 }
	1: {"anim": "katana/attack_1", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(100.0, 0.0), "base_dmg": 512, "hit_sfx_type": "sound_light_2", "energy": 200, "switch": 5, "iai_reward": 2, "sfx": SFX_WAVE},
	2: {"anim": "katana/attack_2", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(150.0, 0.0), "base_dmg": 512, "hit_sfx_type": "slash_light", "energy": 2, "switch": 5, "iai_reward": 2, "sfx": SFX_CUT},
	3: {"anim": "katana/attack_3", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(200.0, 0.0), "base_dmg": 512, "hit_sfx_type": "slash_light", "energy": 2, "switch": 5,"iai_reward": 2, "sfx": SFX_CUT},
	4: {"anim": "katana/attack_4", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(400.0, 0.0), "shake": 30.0, "hit_sfx_type": "slash_light", "base_dmg": 645, "energy": 2, "switch": 5, "iai_reward": 2, "sfx": SFX_CUT},
}

# [戰技與大招字典] 
const SKILL_CONFIG = {
	21: { "anim": "katana/attack_c3", "hitbox_name": "None", "type": Damage.Type.HEAVY, "knockback": Vector2.ZERO, "shake": 20.0, "shake_on_hit_only": true, "base_dmg": 932, "energy": 15, "switch": 20, "iai_reward": 10 },
	30: { "anim": "katana/attack_c0_charge_start", "hitbox_name": "None", "type": Damage.Type.LIGHT, "knockback": Vector2.ZERO, "shake": 0.0, "shake_on_hit_only": true, "base_dmg": 0, "energy": 0, "switch": 0, "iai_reward": 0 },
	34: { "anim": "katana/attack_c0_release", "hitbox_name": "C0", "type": Damage.Type.LIGHT, "knockback": Vector2(50.0, 0.0), "shake": 6.0, "shake_on_hit_only": true, "base_dmg": 200, "energy": 1, "switch": 2, "iai_reward": 0 },
	32: { "anim": "katana/attack_c0_release", "hitbox_name": "C0", "type": Damage.Type.LIGHT, "knockback": Vector2.ZERO, "shake": 2.0, "shake_on_hit_only": true, "base_dmg": 325, "energy": 1, "switch": 2, "iai_reward": 0 },
	33: { "anim": "katana/attack_c0_release", "hitbox_name": "C0", "type": Damage.Type.LIGHT, "knockback": Vector2.ZERO, "shake": 3.0, "shake_on_hit_only": true, "base_dmg": 325, "energy": 1, "switch": 2, "iai_reward": 0 },
	11: { "anim": "katana/attack_c1", "hitbox_name": "C1", "type": Damage.Type.HEAVY, "knockback": Vector2(0.0, -500.0), "shake": 20.0, "shake_on_hit_only": false, "base_dmg": 560, "energy": 10, "switch": 15, "iai_reward": 5 },
	12: { "anim": "katana/attack_c1_2", "hitbox_name": "C1", "type": Damage.Type.HEAVY, "knockback": Vector2(0.0, -300.0), "shake": 30.0, "shake_on_hit_only": true, "base_dmg": 720, "energy": 10, "switch": 15, "iai_reward": 5 },
	41: { "anim": "katana/skill_down", "hitbox_name": "C2", "type": Damage.Type.LIGHT, "knockback": Vector2(100.0, 0.0), "shake": 2.0, "shake_on_hit_only": true, "base_dmg": 200, "energy": 10, "switch": 15, "iai_reward": 10 },
	
	# 🌟 強化戰技 (42) - 燕返：第一段配置為 12 連擊的黏著攻擊
	42: { "anim": "katana/attack_tsubame", "hitbox_name": "attack_tsubame", "type": Damage.Type.HEAVY, "knockback": Vector2(0.0, -80.0), "shake": 0.0, "shake_on_hit_only": true, 
		"base_dmg": 200, "energy": 25, "switch": 30, "iai_reward": 0, 
		"max_hits": 12, "interval": 0.1, "sticky": true },
	
	# 🌟 大招 (80) - 全屏 20 連斬：脫手黏著攻擊
	80: { "anim": "katana/attack_ult", "hitbox_name": "UltHitbox", "type": Damage.Type.HEAVY, "knockback": Vector2(10.0, -100.0), "shake": 5.0, "shake_on_hit_only": true, "base_dmg": 150, "energy": 0, "switch": 0, "iai_reward": 0, 
		"max_hits": 20, "interval": 0.1, "sticky": true },
	# 🌟 大招結尾演出 (81) - 純收招，無傷害，無無敵
	81: { "anim": "katana/attack_ult_end", "hitbox_name": "None", "type": Damage.Type.LIGHT, "knockback": Vector2.ZERO, "shake": 0.0, "shake_on_hit_only": true, "base_dmg": 0, "energy": 0, "switch": 0, "iai_reward": 0 },
	
	# 🌟 變奏技能前搖 (90) - 純演出，無傷害
	90: { "anim": "katana/attack_c0_charge_start", "hitbox_name": "None", "type": Damage.Type.LIGHT, "knockback": Vector2.ZERO, "shake": 0.0, "shake_on_hit_only": true, "base_dmg": 0, "energy": 0, "switch": 0, "iai_reward": 0 },
}

# [空戰字典]
const AIR_ATTACK_CONFIG = {
	61: { "anim": "katana/air_attack_1", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "type": Damage.Type.LIGHT, "knockback": Vector2(20.0, -200.0), "base_dmg": 300, "energy": 2, "switch": 4, "iai_reward": 2},
	62: { "anim": "katana/air_attack_2", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "type": Damage.Type.LIGHT, "knockback": Vector2(20.0, -300.0), "base_dmg": 300, "energy": 2, "switch": 4, "iai_reward": 2},
}

# ==========================================
# 🚀 4. 物理運算與手感參數
# ==========================================
@export_group("重擊(蓄力拔刀)設定")
@export var charge_time_per_tier: float = 0.5   
@export var max_charge_tiers: int = 3           
@export var thrust_speed: float = 200.0         

@export_group("戰技上 (挑飛) 設定")
@export var launch_start_time: float = 0.2      
@export var launch_duration: float = 0.06       
@export var vertical_launch_speed: float = -650.0 

@export_group("戰技中立 (死亡切割) 設定")
@export var skill_neutral_friction_rate: float = 0.2 

@export_group("空戰設定 (Air Combat)")
@export var min_air_attack_height: float = 40.0 
@export var air_thrust_force: float = -150.0    
@export var air_skill_gravity_rate: float = 0.25 

# --- 內部狀態 ---
var current_active_hitbox: Hitbox = null
var combo_step: int = 0
var last_attack_time: float = 0.0
var is_attacking: bool = false
var step_cooldown: float = 0.0                  

var is_launch_triggered: bool = false
var launch_timer: float = 0.0
var current_charge_timer: float = 0.0
var current_charge_tier: int = 0
var light_hold_timer: float = 0.0               
var skill_timer: float = 0.0

var is_wave_fired: bool = false                 
var air_attack_locked: bool = false             

var is_time_stop_triggered: bool = false 
var _tsubame_zoom_phase: int = 0 
var _camera_tween: Tween 

var _is_hitbox_locked: bool = false

# ==========================================
# 🌀 5. 共鳴迴路邏輯 (Resonance Circuit)
# ==========================================
func gain_iai(amount: int) -> void:
	current_iai = mini(current_iai + amount, MAX_IAI)
	print("🟢 命中！獲得居合值: ", amount, " | 目前居合: ", current_iai, "/", MAX_IAI)

func consume_iai_for_charge() -> void:
	current_iai = maxi(current_iai - 10, 0)
	current_tsubame = mini(current_tsubame + 10, MAX_TSUBAME)
	print("消耗10點居合值，目前居合: ", current_iai, "| 增加燕反值", current_tsubame, "/", MAX_TSUBAME)
	
	if current_tsubame >= MAX_TSUBAME and not is_tsubame_ready:
		is_tsubame_ready = true
		skill_1_timer = 0.0 # 滿燕返即刻重置戰技 CD

# ==========================================
# 🎬 實作 Weapon.gd 合約接口
# ==========================================
func start_light_attack() -> void:
	if step_cooldown > 0: return 
	step_cooldown = 0.15

	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time > combo_timeout:
			combo_step = 0

	# 🪽 空戰處理
	if not player.is_on_floor():
		if air_attack_locked or _get_ground_distance() < min_air_attack_height:
			return
		combo_step = 62 if combo_step == 61 else 61
		is_attacking = true
		_play_air_step(combo_step)
		return

	# 原本這裡是 return，現在改成：如果上一招是戰技或蓄力，直接把段數歸零！
	if combo_step == 30 or SKILL_CONFIG.has(combo_step):
		combo_step = 0

	combo_step += 1
	if not LIGHT_ATTACK_CONFIG.has(combo_step):
		combo_step = 1

	is_attacking = true
	_play_light_step(combo_step)
	
	# --- 蓄力預輸入補償 (Pre-input Buffer) ---
	if Input.is_action_pressed("attack"): light_hold_timer = 0.15
	else: light_hold_timer = 0.0

func start_heavy_attack() -> void:
	if step_cooldown > 0:
		is_attacking = false
		return
	
	step_cooldown = 0.15
	
	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		# 如果距離上次攻擊結束已經超過了 combo_timeout (0.3秒)，就強制把段數忘記！
		if current_time - last_attack_time > combo_timeout:
			combo_step = 0
			
	is_attacking = true
	is_launch_triggered = false
	is_wave_fired = false
	is_time_stop_triggered = false 

	# 🪽 空戰派生處理
	if not player.is_on_floor():
		if Input.is_action_pressed("move_down"):
			_play_skill_step(21) 
			skill_3_timer = skill_3_cd # 🌟 啟動【下砸】冷卻
		elif is_tsubame_ready:
			_play_skill_step(42) 
			is_tsubame_ready = false
			current_tsubame = 0
		else:
			is_attacking = false 
		return

	# 🗡️ 地面方向派生
	if combo_step == 11:
		_play_skill_step(12)
		skill_2_timer = skill_2_cd
		return
		
	if Input.is_action_pressed("move_up"): 
		_play_skill_step(11) 
		skill_2_timer = skill_2_cd # 🌟 啟動【挑飛】冷卻
	elif Input.is_action_pressed("move_down"): 
		_play_skill_step(21) 
		skill_3_timer = skill_3_cd # 🌟 啟動【下砸】冷卻
	else:
		if is_tsubame_ready:
			_play_skill_step(42) 
			is_tsubame_ready = false
			current_tsubame = 0 
		else:
			_play_skill_step(41)
			skill_1_timer = skill_1_cd # 🌟 啟動【中立】冷卻

func start_counter_attack() -> void:
	if step_cooldown > 0: return
	step_cooldown = 0.15
	is_attacking = true
	combo_step = 4 
	_play_light_step(combo_step)

func start_ultimate() -> void:
	if player.has_method("consume_weapon_energy"):
		player.consume_weapon_energy(WEAPON_ID, ult_energy_cost)
		
	step_cooldown = 0.15
	is_attacking = true
	is_time_stop_triggered = false 
	_tsubame_zoom_phase = 0 
	light_hold_timer = 0.0 
	
	ult_timer = ult_cd 
	combo_step = 80
	_play_skill_step(combo_step)
	
	player.is_input_locked = true 

func start_intro_skill() -> void:
	step_cooldown = 0.15
	is_attacking = true
	is_time_stop_triggered = false 
	_tsubame_zoom_phase = 0 
	light_hold_timer = 0.0 
	
	current_tsubame = mini(current_tsubame + 30, MAX_TSUBAME)
	print("🌟 變奏出場！獲得 30 點燕返值，目前燕返: ", current_tsubame, "/", MAX_TSUBAME)
	
	if current_tsubame >= MAX_TSUBAME and not is_tsubame_ready:
		is_tsubame_ready = true
		skill_1_timer = 0.0
	
	combo_step = 90 
	_play_skill_step(combo_step)
	
	player.is_input_locked = true 
	print("🌪️ [太刀] 變奏技能發動！開始前搖演出...")

func update_timers_only(delta: float) -> void:
	if step_cooldown > 0: step_cooldown -= delta 
	if skill_1_timer > 0: skill_1_timer -= delta
	if skill_2_timer > 0: skill_2_timer -= delta # 🌟 挑飛冷卻
	if skill_3_timer > 0: skill_3_timer -= delta # 🌟 下砸冷卻
	if ult_timer > 0: ult_timer -= delta

# ==========================================
# 🏃 物理與特效場控核心 (The Stage Director)
# ==========================================
func get_current_velocity(delta: float) -> Vector2:
	if not is_attacking:
		return player.velocity

	if player.is_on_floor(): air_attack_locked = false

	var new_x = player.velocity.x
	var new_y = player.velocity.y

	# ----------------------------------------
	# ⏳ 長按普攻轉蓄力 (Hold to Charge)
	# ----------------------------------------
	if combo_step in [1, 2, 3, 4, 61, 62]: # 拔除地面限制，並加入空戰連段
		# 如果居合值根本不到 10，連計時都不用計，直接無視長按！
		if current_iai >= 10 and Input.is_action_pressed("attack"):
			light_hold_timer += delta
			
			# 稍微縮短一點判定時間 (0.4 -> 0.35)，因為我們加了後搖判定防呆
			if light_hold_timer >= 0.35:
				
				# 防呆機制！必須等普攻動畫播到後半段 (大於 50%) 才允許進入蓄力
				var anim_len = player.animation_player.current_animation_length
				var anim_pos = player.animation_player.current_animation_position
				
				if anim_len > 0.0 and (anim_pos / anim_len) >= 0.5:
					if current_iai >= 10:
						combo_step = 30 # 進入蓄力拔刀準備姿勢
						current_charge_timer = 0.0
						current_charge_tier = 0
						_play_skill_step(30)
					else:
						# 居合值不足 10，不准進入蓄力！直接重置計時器
						light_hold_timer = 0.0
				
		else:
			light_hold_timer = 0.0

	# ----------------------------------------
	# 🔋 蓄力結算 (Charge Resolution)
	# ----------------------------------------
	if combo_step == 30:
		# 蓄力期間允許微調面向
		var move_dir := Input.get_axis("move_left", "move_right")
		# 殘影不准微調面向
		if not is_zero_approx(move_dir) and not player.name.begins_with("Phantom"):
			player.direction = player.Direction.LEFT if move_dir < 0 else player.Direction.RIGHT
			
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta * 2.0)
		
		# 判斷是否為殘影。殘影視為「直接鬆開按鍵」！
		var is_holding = Input.is_action_pressed("attack")
		if player.name.begins_with("Phantom"):
			is_holding = false 
		
		# 使用 is_holding 取代原本的 Input.is_action_pressed("attack")
		if is_holding:
			current_charge_timer += delta
			var new_tier = min(max_charge_tiers, floori(current_charge_timer / charge_time_per_tier))
			
			if new_tier > current_charge_tier:
				# 🌟 同步修復：先檢查有沒有錢 (居合值)！
				if current_iai >= 10:
					current_charge_tier = new_tier
					consume_iai_for_charge()
					
					# 🌟 有錢扣，才准播蓄力升階特效！
					player.spawn_anim_vfx(
						"Aggregation ring", 
						0, -20,           
						Vector2(1.5, 1.5), 
						0,                 
						Color.WHITE,      
						Color.WHITE,     
						false,             
						2,                 
						1.0                
					)
					
					if CombatManager.has_method("apply_camera_shake"):
						CombatManager.apply_camera_shake(2.0 + current_charge_tier * 1.5)
					_apply_charge_zoom(ZOOM_LEVELS[current_charge_tier])
					
				else:
					# 🌟 沒錢了！強制鎖死計時器，不准升階也不給特效！
					current_charge_timer = current_charge_tier * charge_time_per_tier
					
			if not player.animation_player.is_playing():
				player.play_safe_anim("katana/attack_c0_charge_loop")
		else:
			# 鬆開按鍵 (或身為殘影)：結算並釋放
			_apply_charge_zoom(ZOOM_LEVELS[0])
			
			# 如果蓄力未滿一階就提早鬆手，直接取消動作收刀，不發動攻擊！
			if current_charge_tier == 0:
				is_attacking = false
				combo_step = 0
				current_charge_timer = 0.0
				light_hold_timer = 0.0
				
				player.is_input_locked = false # 🌟 核心修復 1：把這行補上去！確保提早放棄蓄力時會解鎖。
				
				if player.scabbard: 
					player.scabbard.fade_in()
			else:
				var release_step = 34 # 預設一階
				if current_charge_tier == 2: release_step = 32
				elif current_charge_tier == 3: release_step = 33
				_play_skill_step(release_step)

	# ----------------------------------------
	# 🚀 蓄力衝刺 (Thrust)
	# ----------------------------------------
	
	elif combo_step in [32, 33, 34]:
		var anim_time = player.animation_player.current_animation_position
		if anim_time < 0.05:
			var speed_multiplier = 1.0
			if combo_step == 34: speed_multiplier = 4.5
			elif combo_step == 32: speed_multiplier = 6.5 
			elif combo_step == 33: speed_multiplier = 8.0
			new_x = player.direction * (thrust_speed * speed_multiplier)
		else: 
			new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		
		
	# ----------------------------------------
	# 🦅 挑飛與滯空 (Launch & Aerial Hold)
	# ----------------------------------------
	elif combo_step == 12:
		if player.animation_player.current_animation_position >= launch_start_time and not is_launch_triggered:
			is_launch_triggered = true
			launch_timer = launch_duration
		if is_launch_triggered:
			if launch_timer > 0: 
				launch_timer -= delta
				new_y = vertical_launch_speed
				new_x = 0.0 # 取消水平動量，純粹上拋
			else: 
				new_x = 0.0
				if new_y < 0:
					# 到達最高點前減速，給予接招時間
					new_y = move_toward(new_y, 0.0, player.default_gravity * 2.0 * delta)
				else:
					new_y += player.default_gravity * delta
		else:
			# 🌟 核心修復：補上起飛前的 0.2 秒前搖煞車！
			new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
	
	# ----------------------------------------
	# 🌊 劍氣發射 (Sword Wave)
	# ----------------------------------------
	elif combo_step == 21: 
		var anim_time = player.animation_player.current_animation_position
		if anim_time >= 0.32 and not is_wave_fired:
			is_wave_fired = true
			if CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(20.0) 
			spawn_sword_wave("skill_down")
			
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		if not player.is_on_floor(): new_y += (player.default_gravity * air_skill_gravity_rate) * delta

	elif combo_step == 41: 
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * skill_neutral_friction_rate * delta)
	
	elif combo_step == 90: 
		# 變奏前搖雙倍煞車
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * 2.0 * delta)
		
	# ----------------------------------------
	# 🦅 強化戰技 (42) - 燕返：二段式變身邏輯
	# ----------------------------------------
	elif combo_step == 42: 
		var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * 5.0 * (speed_mult * speed_mult) * delta)
		
		if player.is_on_floor(): new_y = 0.0
		else: new_y = player.default_gravity * air_skill_gravity_rate * delta 
		
		var anim_time = player.animation_player.current_animation_position
		
		# [階段一] 0.08s 獲得純無敵保護
		if anim_time >= 0.08 and not is_time_stop_triggered:
			is_time_stop_triggered = true 
			player.invincible_time_left = 2.0 
			
		# [階段一] 0.10s 鏡頭特寫
		if anim_time >= 0.10 and _tsubame_zoom_phase == 0:
			_tsubame_zoom_phase = 1
			_apply_charge_zoom(Vector2(0.75, 0.75), 1.6) 
				
		# 🌟 [階段二] 1.76s 終極拔刀！Hitbox 屬性瞬間重塑
		if anim_time >= 1.76 and not is_wave_fired:
			is_wave_fired = true 
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(60.0) 
				
			if is_instance_valid(current_active_hitbox):
				# 將 12 連斬黏著框改造為單發核彈框
				current_active_hitbox.hit_targets.clear() 
				current_active_hitbox.max_hits = 1        
				current_active_hitbox.sticky_multi_hit = false 
				current_active_hitbox.damage_amount = 1500 
				current_active_hitbox.knockback_force = Vector2(200.0, -500.0) 
				current_active_hitbox.shake_intensity = 400.0
				current_active_hitbox.has_generated_energy = false 
				
			_is_hitbox_locked = false 
			disable_hitbox() 
			enable_hitbox("CollisionShape2D2") # 開啟大範圍判定框
			
	# ----------------------------------------
	# 🌌 大招 (80) - 全屏 20 連斬與動態運鏡
	# ----------------------------------------
	elif combo_step == 80: 
		# 保留移動慣性 (抗時停補償)
		var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * 5.0 * (speed_mult * speed_mult) * delta)
		new_y = 0.0 
		
		var anim_time = player.animation_player.current_animation_position
		
		# [領域展開] 0.05s 瞬間進入全屏時停與無敵
		if anim_time >= 0.05 and not is_time_stop_triggered:
			is_time_stop_triggered = true 
			if player.has_method("trigger_time_stop"):
				player.trigger_time_stop(3.0, 0.05) 
			# 動畫反向加速維持原速
			player.animation_player.speed_scale = 1.0 / 0.05 
			player.invincible_time_left = 3.0
			
		# 🎥 [鏡頭 1] 0.05s 推進特寫
		if anim_time >= 0.05 and _tsubame_zoom_phase == 0:
			_tsubame_zoom_phase = 1
			_apply_charge_zoom(Vector2(1.2, 1.2), 0.3) 
			
		# 🎥 [鏡頭 2] 0.70s 快速反向特寫 + 震動
		if anim_time >= 0.70 and _tsubame_zoom_phase == 1:
			_tsubame_zoom_phase = 2
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(100.0, 0.07) 
			_apply_charge_zoom(Vector2(0.85, 0.85), 0.1) 
		
		# 🎥 [鏡頭 3] 0.82s 拉遠展現全屏斬擊
		if anim_time >= 0.82 and _tsubame_zoom_phase == 2:
			_tsubame_zoom_phase = 3
			_apply_charge_zoom(Vector2(0.65, 0.65), 1.8) 
			
		# 🎥 [鏡頭 4] 2.80s 結尾震動與恢復
		if anim_time >= 2.80 and _tsubame_zoom_phase == 3:
			_tsubame_zoom_phase = 4
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(180.0, 0.15) 
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.2)

	# ----------------------------------------
	# 🪽 空戰慣性滑行
	# ----------------------------------------
	elif combo_step in [61, 62]:
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)

	else:
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)

	return Vector2(new_x, new_y)
	
# 武器是否接管重力 (True 時總監不干涉 Y 軸)
func is_handling_gravity() -> bool:
	if combo_step == 12 and is_launch_triggered: return true
	if not player.is_on_floor() and combo_step in [21, 42]: return true
	if combo_step == 80: return true
	return false

# ==========================================
# 🎬 招式結束判定 (Cut!)
# ==========================================
func is_attack_finished() -> bool:
	# 如果根本不在攻擊狀態，直接回報完成，讓總監放人！
	if not is_attacking: 
		return true
	
	if not player.animation_player.is_playing():
		
		# ==========================================
		# 大招演出完後的「結尾接力」
		# ==========================================
		if combo_step == 80:
			# 立即強制切換到 81 號「結尾動畫」
			combo_step = 81
			_play_skill_step(81) 
		
			return false 
		
		# --- 變奏無縫銜接 ---
		if combo_step == 90:
			combo_step = 33
			_play_skill_step(combo_step)
			print("🌪️ 前搖結束，化作閃電拔刀突進！")
			return false 
			
		# --- 蓄力無縫預輸入 (Hold-to-Chain Buffer) ---
		if Input.is_action_pressed("attack"):
			if combo_step in [1, 2, 3, 4, 12, 21, 32, 33, 34, 41, 61, 62]:
				# 只有在居合 >= 10，而且「確實進入蓄力」時，才攔截狀態機！
				if current_iai >= 10:
					combo_step = 30 
					current_charge_timer = 0.0
					current_charge_tier = 0
					_play_skill_step(30)
					return false # 成功進入蓄力，回傳 false 告訴總監「我還沒打完」

		player.is_input_locked = false 
		
		if combo_step == 61: air_attack_locked = true 
		last_attack_time = Time.get_ticks_msec() / 1000.0
		is_attacking = false
		step_cooldown = 0.0
		
		if combo_step in [42, 80] or _tsubame_zoom_phase > 0:
			_tsubame_zoom_phase = 0
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.4)
			if player.has_method("clear_time_stop"): player.clear_time_stop()
				
		# 終極防線：強制鎖死 Hitbox
		_is_hitbox_locked = true 
		disable_hitbox()
		
		if not requires_sheath() and player.scabbard:
			player.scabbard.fade_in()
			
		return true
	return false

# ==========================================
# 💥 強制打斷處理 
# ==========================================
func cancel_attack() -> void:
	player.is_input_locked = false 
	_apply_charge_zoom(ZOOM_LEVELS[0])
	is_attacking = false
	combo_step = 0
	step_cooldown = 0.0
	is_launch_triggered = false
	current_charge_tier = 0
	current_charge_timer = 0.0
	light_hold_timer = 0.0
	is_wave_fired = false 
	_tsubame_zoom_phase = 0
	
	if is_time_stop_triggered:
		is_time_stop_triggered = false
		if player.has_method("clear_time_stop"): player.clear_time_stop() 
	else:
		is_time_stop_triggered = false 
	
	_is_hitbox_locked = true 
	disable_hitbox()
	
	if player.scabbard: player.scabbard.fade_in()
		
func requires_sheath() -> bool:
	if combo_step == 0:
		return false
	return combo_step not in no_sheath_steps
	
# ==========================================
# ⚙️ 內部實作與 Hitbox 綁定
# ==========================================
func _play_light_step(step: int) -> void:
	disable_hitbox()
	var config: Dictionary = LIGHT_ATTACK_CONFIG[step]
	_apply_hitbox_config(config)
	
	if config.has("sfx") and config["sfx"] != null:
		# 參數：音檔, 音量 (-8.0), 音調隨機度 (交給 AudioManager 處理)
		AudioManager.play_sfx(config["sfx"], -8.0)
		
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _play_skill_step(step: int) -> void:
	disable_hitbox()
	var config: Dictionary = SKILL_CONFIG[step]
	_apply_hitbox_config(config)
	
	# 🎵 🌟 戰技與大招的揮空音效
	if config.has("sfx") and config["sfx"] != null:
		AudioManager.play_sfx(config["sfx"], -5.0)
		
	# 特殊 Hitbox 屬性覆寫
	if current_active_hitbox:
		if step in [11, 12]: current_active_hitbox.spark_type = 1; current_active_hitbox.spark_scale = 0.8
		elif step == 41: current_active_hitbox.max_hits = 5; current_active_hitbox.hit_interval = 0.1; current_active_hitbox.sticky_multi_hit = true
		elif step == 34: current_active_hitbox.max_hits = 2; current_active_hitbox.hit_interval = 0.1; current_active_hitbox.sticky_multi_hit = true
		elif step == 32: current_active_hitbox.max_hits = 4; current_active_hitbox.hit_interval = 0.1; current_active_hitbox.sticky_multi_hit = true
		elif step == 33: current_active_hitbox.max_hits = 7; current_active_hitbox.hit_interval = 0.1; current_active_hitbox.sticky_multi_hit = true; current_active_hitbox.spark_scale = 0.6; current_active_hitbox.spark_color = Color(1.0, 0.0, 0.0, 1.0); current_active_hitbox.aura_color = Color(1.0, 0.0, 0.0, 1.0)  
		elif step == 42: current_active_hitbox.spark_scale = 0.6
		elif step == 80: current_active_hitbox.spark_scale = 1.0
	
	if not player.is_on_floor() and step in [21, 42]:
		player.velocity.y = air_thrust_force * 0.5
		
	combo_step = step
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _play_air_step(step: int) -> void:
	disable_hitbox() 
	var config: Dictionary = AIR_ATTACK_CONFIG[step]
	_apply_hitbox_config(config)
	player.velocity.y = air_thrust_force 
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _apply_hitbox_config(config: Dictionary) -> void:
	_is_hitbox_locked = false 
	var target_hitbox_name = config.get("hitbox_name", "Hitbox")
	var hitbox := get_node_or_null(target_hitbox_name) as Hitbox
	
	if hitbox:
		hitbox.damage_amount = config["base_dmg"]
		hitbox.max_hits = config.get("max_hits", 1)
		hitbox.hit_sfx_type = config.get("hit_sfx_type", "")
		hitbox.hit_interval = config.get("interval", 0.0)
		hitbox.attack_type = config.get("type", Damage.Type.LIGHT)
		hitbox.knockback_force = config.get("knockback", Vector2.ZERO)
		
		# 鎖死太刀所有連段(包含燕返、大招)的絕對方向！
		var base_kb_x = abs(hitbox.knockback_force.x)
		hitbox.absolute_knockback = Vector2(base_kb_x * player.direction, hitbox.knockback_force.y)
		
		if "shake_intensity" in hitbox: hitbox.shake_intensity = config.get("shake", 2.5)
		if "shake_on_hit_only" in hitbox: hitbox.shake_on_hit_only = config.get("shake_on_hit_only", true)
		hitbox.sticky_multi_hit = config.get("sticky", false)
		
		if "energy_reward" in hitbox: hitbox.energy_reward = float(config.get("energy", 0))
		if "switch_reward" in hitbox: hitbox.switch_reward = float(config.get("switch", 0))
		if "iai_reward" in hitbox: hitbox.iai_reward = int(config.get("iai_reward", 0))
		
		hitbox.spark_type = 0; hitbox.spark_scale = 0.3; hitbox.spark_color = Color(0.7, 1.5, 0.5, 1.0); hitbox.aura_color = Color(0, 1, 1, 1)
		hitbox.hit_targets.clear() 
		current_active_hitbox = hitbox
		
# ==========================================
# 🛠️ 輔助工具區
# ==========================================
func _get_ground_distance() -> float:
	var space_state = player.get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(player.global_position, player.global_position + Vector2(0, 1000))
	query.collision_mask = 1 
	var result = space_state.intersect_ray(query)
	if result: return player.global_position.distance_to(result.position)
	return 1000.0 

func _apply_charge_zoom(target_zoom: Vector2, duration: float = 0.2) -> void:
	# 殘影不准控制鏡頭！
	if player.name.begins_with("Phantom"): return
	
	var camera = get_viewport().get_camera_2d()
	if camera:
		if _camera_tween and _camera_tween.is_valid(): _camera_tween.kill()
		_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
		var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
		_camera_tween.set_speed_scale(speed_mult)
		_camera_tween.tween_property(camera, "zoom", target_zoom, duration)

func spawn_sword_wave(wave_type: String) -> void:
	if not SWORD_WAVE_SCENE: return
	var wave = SWORD_WAVE_SCENE.instantiate() as SwordWave
	get_tree().current_scene.add_child(wave)
	
	wave.global_position = player.global_position + Vector2(30 * player.direction, -20)
	wave.direction = player.direction
	
	await get_tree().process_frame 
	if not is_instance_valid(wave) or not wave.hitbox: return
	
	wave.hitbox.spark_type = 0; wave.hitbox.spark_color = Color(0.7, 1.5, 0.5, 1.0); wave.hitbox.aura_color = Color(0, 1, 1, 1)
	
	match wave_type:
		"skill_down":
			var config = SKILL_CONFIG[21] 
			wave.speed = 900.0; wave.max_distance = 150.0; wave.scale = Vector2(2.0 * player.direction, 2.0)
			wave.hitbox.damage_amount = max(1, roundi(float(config["base_dmg"])))
			
			# 鎖死劍氣的絕對方向！
			wave.hitbox.absolute_knockback = Vector2(400.0 * player.direction, 0.0)
			
			wave.hitbox.knockback_force = Vector2(400.0, 0.0)
			wave.hitbox.attack_type = Damage.Type.LIGHT
			wave.hitbox.spark_scale = 0.3
			
			if "energy_reward" in wave.hitbox: wave.hitbox.energy_reward = float(config.get("energy", 0))
			if "switch_reward" in wave.hitbox: wave.hitbox.switch_reward = float(config.get("switch", 0))
			if "iai_reward" in wave.hitbox: wave.hitbox.iai_reward = int(config.get("iai_reward", 0))
			if "multi_hit_energy" in wave.hitbox: wave.hitbox.multi_hit_energy = false
			
# ==========================================
# 🛡️ 狀態機防護名單 (The Bouncer's List)
# ==========================================
func can_air_light() -> bool:
	if air_attack_locked or _get_ground_distance() < min_air_attack_height: return false
	return true

# 🌟 全新的智慧方向防護網
func can_use_heavy() -> bool:
	# 燕返最高優先級：只要準備好，無視所有冷卻！
	if is_tsubame_ready: return true 
	
	# 🌟 核心修復：如果現在是挑飛第一段 (11)，代表玩家要派生第二段 (12)，無條件放行！
	if combo_step == 11: return true 
	
	# 1. 處理空戰限制 (空中只能放下砸)
	if not player.is_on_floor():
		if Input.is_action_pressed("move_down"):
			if skill_3_timer > 0:
				print("⏳ [防護網攔截] 下砸戰技冷卻中！")
				return false
			return true 
		return false 
			
	# 2. 處理地面方向冷卻限制
	if Input.is_action_pressed("move_up"):
		if skill_2_timer > 0:
			print("⏳ [防護網攔截] 挑飛戰技冷卻中！")
			return false
	elif Input.is_action_pressed("move_down"):
		if skill_3_timer > 0:
			print("⏳ [防護網攔截] 下砸戰技冷卻中！")
			return false
	else:
		# 什麼都沒按，就是中立戰技
		if skill_1_timer > 0:
			print("⏳ [防護網攔截] 中立戰技冷卻中！")
			return false
		
	return true

func can_use_ultimate() -> bool:
	if ult_timer > 0: return false 
	if not player.is_on_floor(): return false 
	
	if player.has_method("get_weapon_energy"):
		if player.get_weapon_energy(WEAPON_ID) < ult_energy_cost:
			print("⚠️ [", WEAPON_ID, "] 大招能量不足！需要: ", ult_energy_cost, "，目前僅有: ", player.get_weapon_energy(WEAPON_ID))
			return false 
			
	return true



# ==========================================
# 💾 武器狀態保存與繼承
# ==========================================
func export_weapon_data() -> Dictionary:
	return {
		"current_iai": current_iai,
		"current_tsubame": current_tsubame,
		"is_tsubame_ready": is_tsubame_ready,
		"skill_1_timer": skill_1_timer if "skill_1_timer" in self else 0.0,
		"skill_2_timer": skill_2_timer if "skill_2_timer" in self else 0.0,
		"skill_3_timer": skill_3_timer if "skill_3_timer" in self else 0.0,
		"ult_timer": ult_timer if "ult_timer" in self else 0.0
	}

func import_weapon_data(data: Dictionary) -> void:
	current_iai = data.get("current_iai", 0)
	current_tsubame = data.get("current_tsubame", 0)
	is_tsubame_ready = data.get("is_tsubame_ready", false)
	
	if "skill_1_timer" in self: skill_1_timer = data.get("skill_1_timer", 0.0)
	if "skill_2_timer" in self: skill_2_timer = data.get("skill_2_timer", 0.0)
	if "skill_3_timer" in self: skill_3_timer = data.get("skill_3_timer", 0.0)
	if "ult_timer" in self: ult_timer = data.get("ult_timer", 0.0)
	
# --- 鎖死機制防護下的 Hitbox 開關 ---
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
