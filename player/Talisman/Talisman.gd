class_name Talisman
extends Weapon
## 武器腳本：符咒 (Talisman)

const WEAPON_ID: String = "talisman"

# ==========================================
# 🎛️ 1. 武器核心參數與資源
# ==========================================
@export_group("武器核心參數")
@export var combo_timeout: float = 0.3      
@export var no_sheath_steps: Array[int] = [40,50,90] 
@export var ult_energy_cost: float = 100.0  

const TALISMAN_VFX_SCENE = preload("res://player/Talisman/TalismanVFX.tscn")
const HEALING_TOWER_SCENE = preload("res://player/Talisman/HealingTower.tscn") 
const LASER_SCENE = preload("res://player/Talisman/TalismanLaser.tscn")

# ==========================================
# 📖 2. 招式數據庫 (Data-Driven Combat Config)
# ==========================================
const LIGHT_ATTACK_CONFIG = {
	1: {"anim": "talisman/attack_1", "hitbox_name": "Hitbox", "base_dmg": 100, "energy": 5, "switch": 5, "charge_reward": 0, "vfx_anim": "a1", "vfx_fly_dist": 0.0, "action_type": Weapon.ActionType.NORMAL},
	2: {"anim": "talisman/attack_2", "hitbox_name": "Hitbox", "base_dmg": 120, "energy": 5, "switch": 5, "charge_reward": 0, "vfx_anim": "a2", "vfx_fly_dist": 0.0, "action_type": Weapon.ActionType.NORMAL},
	3: {"anim": "talisman/attack_3", "hitbox_name": "Hitbox", "base_dmg": 40, "energy": 2, "switch": 2, "max_hits": 3, "interval": 0.1, "sticky": true, "vfx_anim": "a3", "charge_reward": 10, "vfx_fly_dist": 0.0, "action_type": Weapon.ActionType.NORMAL},
	
	# 🌟 強化普攻型態 (4~5) - 補上專屬的 heal_amount 數值
	4: {"anim": "talisman/attack_4", "hitbox_name": "Hitbox", "base_dmg": 160, "energy": 6, "switch": 6, "charge_reward": 0, "heal_amount": 3, "vfx_fly_dist": 0.0, "vfx_anim": "a5", "action_type": Weapon.ActionType.NORMAL},
	5: {"anim": "talisman/attack_5", "hitbox_name": "Hitbox", "base_dmg": 180, "energy": 6, "switch": 6, "charge_reward": 0, "heal_amount": 3, "vfx_fly_dist": 0.0, "vfx_anim": "a6", "action_type": Weapon.ActionType.NORMAL},
	
	# 🌟 新增：常態空中普攻 (60) - 滯空發射單發雷射
	60: {"anim": "talisman/air_attack_1", "hitbox_name": "None", "base_dmg": 100, "energy": 5, "switch": 5, "charge_reward": 10, "vfx_fly_dist": 0.0, "vfx_anim": "a6", "action_type": Weapon.ActionType.NORMAL}
	
}

const SKILL_CONFIG = {
	20: {
		"anim": "talisman/c1", "hitbox_name": "C1", 
		"base_dmg": 50, "energy": 5, "switch": 10, "charge_reward": 0,
		"max_hits": 5, "interval": 0.1, "sticky": true,                 
		"vfx_anim": "c0", "vfx_fly_dist": 0.0,
		
		# 🌟 新增：召喚塔時附帶的全方位激光彈幕設定
		"laser_scale": 0.8,           
		"laser_tracking": true,      
		"laser_dmg": 200,             # 激光每條獨立傷害
		"laser_type": Damage.Type.LIGHT,
		"laser_offset": Vector2(0.0, -30.0),
		"laser_shake": 30.0 
	},
	30: {
		"anim": "talisman/c2", "hitbox_name": "C2", 
		"type": Damage.Type.HEAVY, 
		"base_dmg": 80, "energy": 5, "switch": 10, "charge_reward": 0, 
		# 🌟 降級為普通擊飛技：最大連擊數改為 4，移除雷射屬性
		"max_hits": 4, "interval": 0.1, "sticky": true, "shake": 20.0,
		"knockback": Vector2(0.0, -350.0), 
		"vfx_anim": "a4", "vfx_fly_dist": 0.0,
		"action_type": Weapon.ActionType.SKILL
	},
	40: {
		"anim": "talisman/c3_2", "hitbox_name": "None", 
		"base_dmg": 0, "energy": 0, "switch": 0, "charge_reward": 0
	},
	50: {
		"anim": "talisman/c3", "hitbox_name": "None", 
		# 🌟 補上傷害與資源數值，這樣 0.77 秒射出去的激光才會有威力！
		"base_dmg": 120, "energy": 5, "switch": 5, "charge_reward": 0,
		"vfx_anim": "a5" # 🌟 新增：讓 50 號進入發射時也能正確讀取到 A4 特效
	},
	# 🌟 新增：大招啟動連擊 (80) - 4 連擊演出
	80: {
		"anim": "talisman/attack_ult", "hitbox_name": "UltHitbox", 
		"type": Damage.Type.HEAVY, "base_dmg": 150, "energy": 0, "switch": 0, "charge_reward": 0,
		"max_hits": 10, "interval": 0.1, "sticky": true, "shake": 10.0,
		"knockback": Vector2(100.0, -100.0),
		"action_type": Weapon.ActionType.ULTIMATE,
		
		# 🌟 繼承自 30 號的巨型激光專屬屬性！
		"laser_scale": 4.0,          
		"laser_tracking": false,     
		"laser_dmg": 250,                                            
		"laser_type": Damage.Type.HEAVY,             
		"laser_knockback": Vector2(600.0, -500.0),   
		"laser_shake": 70.0                                          
	},
	# 🌟 新增：變奏入場 (90) - 完全借用 50 的動畫與特效，但掛載時停邏輯
	90: {
		"anim": "talisman/c3", "hitbox_name": "None", 
		"base_dmg": 120, "energy": 5, "switch": 5, "charge_reward": 0,
		"vfx_anim": "a5" 
	}
}

# ==========================================
# 🌀 3. 共鳴迴路 (Resonance Circuit) 變數
# ==========================================
var current_talisman_charge: int = 0      
const MAX_TALISMAN_CHARGE: int = 50     

func gain_talisman_charge(amount: int) -> void:
	if amount > 0:
		current_talisman_charge = mini(current_talisman_charge + amount, MAX_TALISMAN_CHARGE)
		print("🟢 命中！獲得靈符值: ", amount, " | 目前靈符: ", current_talisman_charge, "/", MAX_TALISMAN_CHARGE)

# ==========================================
# 🎛️ 內部狀態變數
# ==========================================
@export_group("空戰設定 (Air Combat)")
@export var min_air_attack_height: float = 40.0 
@export var air_thrust_force: float = -150.0    
@export var air_skill_gravity_rate: float = 0.95 # 🌟 新增：對齊太刀的緩降率
var air_attack_locked: bool = false

var is_time_stop_triggered: bool = false 
var _tsubame_zoom_phase: int = 0 
var _camera_tween: Tween 
const ZOOM_LEVELS = { 0: Vector2(1.0, 1.0), 1: Vector2(1.15, 1.15), 2: Vector2(1.2, 1.2) }

var combo_step: int = 0
var last_attack_time: float = 0.0
var is_attacking: bool = false
var step_cooldown: float = 0.0

var is_vfx_fired: bool = false 
var is_tower_spawned: bool = false 
# 🌟 新增：殘影狀態同步鎖，確保殘影只在接管時校正一次變數
var _phantom_flags_synced: bool = false
# 🌟 新增：型態切換鎖 (對齊長槍 is_ult_active 工法)
var is_enhanced_mode: bool = false

# 🌟 新增：大招後台 Buff 變數
var is_ult_buff_active: bool = false 
var ult_buff_duration_timer: float = 0.0
var ult_heal_timer: float = 0.0  # 💚 獨立的回血計時器
var ult_laser_timer: float = 0.0 # ⚔️ 獨立的雷射計時器
var active_ult_buff_vfx: Node = null

var current_active_hitbox: Hitbox = null
var _is_hitbox_locked: bool = false

var _current_energy_reward: float = 0.0
var _current_switch_reward: float = 0.0
var _current_charge_reward: int = 0       
var _multi_hit_energy: bool = false       
var _has_granted_resources_this_step: bool = false


func _ready() -> void:
	if owner != null:
		if not owner.is_node_ready(): await owner.ready
		player = owner

# ==========================================
# 🎬 實作 Weapon.gd 合約接口
# ==========================================
func start_light_attack() -> void:
	if is_attacking and combo_step >= 20: return 
	
	if step_cooldown > 0: return
	step_cooldown = 0.15
	
	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time > combo_timeout:
			combo_step = 0
			
	if combo_step >= 20:
		combo_step = 0
			
	is_attacking = true
	is_vfx_fired = false 
	
	# ==========================================
	# 🔮 共鳴迴路：型態分流與靈符值扣除
	# ==========================================
	if is_enhanced_mode:
		# 1. 雙重保險：如果按太快導致靈符在上一招結束時剛好低於 10，立刻攔截退場
		if current_talisman_charge < 10:
			is_enhanced_mode = false
			print("🔮 [靈符值] 不足 10 點，拒絕發動！強制退回普通型態。")
			combo_step = 1 
		else:
			# 2. 強化普攻連段循環 (4 -> 5 -> 4) (🌟 特權：不受空中鎖限制)
			if combo_step < 4 or combo_step > 5:
				combo_step = 4
			else:
				combo_step += 1
				if combo_step > 5: combo_step = 4
				
			# 3. 扣除資源
			current_talisman_charge -= 10
			print("🔮 [靈符值] 消耗 10 點！目前剩餘: ", current_talisman_charge, "/50")
			
			# ==========================================
			# 💚 核心需求：每打一次強化普攻，立刻觸發共鳴回血！
			# ==========================================
			var current_config = LIGHT_ATTACK_CONFIG[combo_step]
			var heal_val = current_config.get("heal_amount", 0)
			
			if heal_val > 0 and player.get("stats") and "health" in player.stats:
				player.stats.health += heal_val
				print("💚 [共鳴迴路] 釋放強化普攻！為玩家恢復了 ", heal_val, " 點生命值。當前 HP: ", player.stats.health)
				
				if player.has_method("spawn_anim_vfx"):
					player.spawn_anim_vfx("heal_flash", 0, -30)
			
			# 4. 結算退場機制
			if current_talisman_charge < 10:
				is_enhanced_mode = false
				print("🔮 [靈符值] 已消耗殆盡，下一刀將恢復普通狀態。")
	else:
		# ==========================================
		# 🌟 核心分流：常規型態下的空中與地面
		# ==========================================
		if not player.is_on_floor():
			# 🚨 大一統修復：常態空戰（60）嚴格執行單輪限制與高度檢查
			if air_attack_locked or _get_ground_distance() < min_air_attack_height:
				is_attacking = false
				return
				
			combo_step = 60
			air_attack_locked = true # 觸發後鎖死，直到落地或放出戰技/變奏重置
			print("🦅 [常態空戰] 觸發滯空射擊 (60)！")
		else:
			# 常規地面連段循環 (1 -> 2 -> 3 -> 1)
			combo_step += 1
			if combo_step > 3 or combo_step < 1:
				combo_step = 1
			
	# ==========================================
	# 🌟 統一交付發動 (加入空戰動畫攔截替換機制)
	# ==========================================
	if is_enhanced_mode:
		var config = LIGHT_ATTACK_CONFIG[combo_step].duplicate()
		if not player.is_on_floor():
			if combo_step == 4:
				config["anim"] = "talisman/air_attack_1"
			elif combo_step == 5:
				config["anim"] = "talisman/air_attack_2"
		_play_attack(config)
	else:
		_play_attack(LIGHT_ATTACK_CONFIG[combo_step])

# ==========================================
# 🌌 大招 (Ultimate)
# ==========================================
func start_ultimate() -> void:
	# 🌟 清理舊的 Buff 特效防呆
	if is_instance_valid(active_ult_buff_vfx):
		active_ult_buff_vfx.queue_free()
		active_ult_buff_vfx = null
	
	if player.has_method("consume_weapon_energy"):
		player.consume_weapon_energy(WEAPON_ID, ult_energy_cost)
		
	step_cooldown = 0.15
	is_attacking = true
	is_vfx_fired = false 
	is_tower_spawned = false # 🌟 核心新增：重置巨砲發射鎖！
	is_time_stop_triggered = false 
	_tsubame_zoom_phase = 0
	
	ult_timer = ult_cd 
	air_attack_locked = false 
	
	combo_step = 80 
	player.invincible_time_left = 3.0 # 施法期間絕對無敵
	
	_play_attack(SKILL_CONFIG[combo_step])
	player.is_input_locked = true 
	print("💥 [符咒] 領域展開！開始 4 連擊特寫...")
	
# ==========================================
# 🌟 變奏入場技能 (Intro Skill)
# ==========================================
func start_intro_skill() -> void:
	step_cooldown = 0.15
	is_attacking = true
	is_vfx_fired = false 
	is_tower_spawned = false 
	is_time_stop_triggered = false 
	_tsubame_zoom_phase = 0 
	
	air_attack_locked = false
	
	# 🌟 核心修復：發動第 0 影格立刻拉滿無敵！徹底封死被打斷扣血的漏洞
	if is_instance_valid(player):
		player.invincible_time_left = 1.5
	
	# 入場直接給予 20 點靈符，並強制進入強化型態！
	gain_talisman_charge(20)
	is_enhanced_mode = true
	
	combo_step = 90 
	_play_attack(SKILL_CONFIG[combo_step])
	
	player.is_input_locked = true 
	print("🌪️ [符咒] 變奏技能發動！開始時停特寫...")
	
func start_heavy_attack() -> void:
	if is_attacking and combo_step >= 20: return 
	
	if step_cooldown > 0:
		is_attacking = false
		return
		
	step_cooldown = 0.15
	is_attacking = true
	is_vfx_fired = false 
	is_tower_spawned = false 
	
	air_attack_locked = false
	
	combo_step = 0 
	
	# ==========================================
	# 🌟 核心分流：將「戰技下 (move_down)」獨立出來，允許空中與地面施放
	# ==========================================
	if Input.is_action_pressed("move_down"):
		
		
		if is_enhanced_mode:
			combo_step = 40
			_play_attack(SKILL_CONFIG[combo_step])
			skill_3_timer = skill_3_cd
			is_enhanced_mode = false
			print("🔮 [戰技下] 播放退出動畫 (40)！手動解除強化型態。")
			
		else:
			gain_talisman_charge(10) # 🌟 維持空放給 10 點
			if current_talisman_charge >= 10:
				combo_step = 50
				_play_attack(SKILL_CONFIG[combo_step])
				skill_3_timer = skill_3_cd
				is_enhanced_mode = true
				print("🔮 [戰技下] 播放進入動畫 (50)！進入強化型態。")
			else:
				print("⚠️ [戰技下] 靈符值不足，無法進入強化狀態！")
				is_attacking = false # 🌟 防呆：失敗時解除鎖定
				
	elif player.is_on_floor():
		# ==========================================
		# 🌟 僅限地面的戰技 (挑飛、中立蓋塔)
		# ==========================================
		if Input.is_action_pressed("move_up"):
			combo_step = 30
			_play_attack(SKILL_CONFIG[combo_step])
			skill_2_timer = skill_2_cd
			gain_talisman_charge(50) 
			
		else:
			combo_step = 20
			_play_attack(SKILL_CONFIG[combo_step])
			skill_1_timer = skill_1_cd
			gain_talisman_charge(10) 
			
	else:
		# 空中按了上或中立，無效化
		is_attacking = false

func update_timers_only(delta: float) -> void:
	if step_cooldown > 0: step_cooldown -= delta
	if skill_1_timer > 0: skill_1_timer -= delta 
	if skill_2_timer > 0: skill_2_timer -= delta 
	if skill_3_timer > 0: skill_3_timer -= delta 
	if ult_timer > 0: ult_timer -= delta
	
	if player.is_on_floor():
		air_attack_locked = false 
	# ==========================================
	# 🌟 大招後台雙線 Buff 運算 (回血與協同雷射獨立)
	# ==========================================
	if is_ult_buff_active:
		if ult_buff_duration_timer > 0:
			ult_buff_duration_timer -= delta
			
			# ----------------------------------------
			# 💚 1. 被動回血線 (自動觸發，每 2 秒一次)
			# ----------------------------------------
			if ult_heal_timer > 0: ult_heal_timer -= delta
			if ult_heal_timer <= 0.0:
				ult_heal_timer = 2.0
				if player.get("stats") and "health" in player.stats:
					player.stats.health += 3
					if player.has_method("spawn_anim_vfx"):
						player.spawn_anim_vfx("heal_flash", 0, -30)
						
			# ----------------------------------------
			# ⚔️ 2. 主動協同雷射線 (冷卻 1 秒，需玩家普攻才觸發)
			# ----------------------------------------
			if ult_laser_timer > 0: ult_laser_timer -= delta
			if ult_laser_timer <= 0.0:
				var current_state = player.state_machine.current_state.name.to_lower() if is_instance_valid(player.state_machine.current_state) else ""
				
				# 🌟 核心防護：確定玩家正在攻擊狀態，且真的拿著武器
				if current_state == "weaponattack" and is_instance_valid(player.current_weapon):
					var c_step = player.current_weapon.get("combo_step")
					# 如果玩家拿著的武器，現在打出來的招式標籤是「NORMAL (普攻)」
					if player.current_weapon.current_action_type == Weapon.ActionType.NORMAL:
						ult_laser_timer = 1.0
						_trigger_ult_lasers()
		else:
			is_ult_buff_active = false
			print("⏳ [符咒] 15 秒靈能爆發 Buff 結束。")
			
			if is_instance_valid(active_ult_buff_vfx):
				active_ult_buff_vfx.queue_free()
				active_ult_buff_vfx = null
				

func _trigger_ult_lasers() -> void:
	if not is_instance_valid(player): return
	
	# 播放符咒專屬發射特效
	_spawn_weapon_vfx({"vfx_anim": "a5"})
	
	# 🌟 生成兩枚雷射：透過 laser_offset 設定在玩家後上方
	var pulse_config = {
		"laser_dmg": 160,                
		"laser_scale": 1.0, 
		"laser_tracking": true, 
		"laser_type": Damage.Type.LIGHT,
		# 🌟 核心位移：X=-40 代表退到身後，Y=-80 代表拉高至頭頂上方
		"laser_offset": Vector2(-40.0, -50.0), 
		"energy": 0,                     
		"switch": 0
	}
	
	# 🌟 扇形角度：往正前方的上下 10 度偏移發射，確保能覆蓋前方扇形區域
	var angles = [deg_to_rad(-10.0), deg_to_rad(10.0)]
	for angle in angles:
		_spawn_laser_projectile(pulse_config, angle)
		
	print("✨ [符咒後台] 協同攻擊！跟隨普攻從後上方發射雙雷射。")
	
# ==========================================
# 🏃 物理與特效場控核心
# ==========================================
func get_current_velocity(delta: float) -> Vector2:
	if not is_attacking: return player.velocity
	
	if player.is_on_floor(): air_attack_locked = false
	
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	
	var anim_time = player.animation_player.current_animation_position
	
	# ==========================================
	# 🌟 核心修復：殘影接管的旗標同步防呆 (Phantom State Sync)
	# ==========================================
	if player.name.begins_with("Phantom") and not _phantom_flags_synced:
		_phantom_flags_synced = true
		
		# 根據殘影接管瞬間的動畫進度，補償（關閉）已經錯過的特效旗標！
		if combo_step in [1, 2, 3, 4, 5, 20, 30] and anim_time >= 0.1:
			is_vfx_fired = true
		if combo_step == 50 and anim_time >= 0.7: # 🌟 順手修正：對齊 0.7 秒
			is_vfx_fired = true
		if combo_step == 20 and anim_time >= 1.15:
			is_tower_spawned = true
		if combo_step == 30 and anim_time >= 0.84:
			is_tower_spawned = true
	
	# ----------------------------------------
	# 物理摩擦力分流 (對齊太刀與長槍)
	# ----------------------------------------
	if combo_step in [1, 2, 3, 4, 5]:
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		
		# 🌟 新增：針對強化普攻的空戰處理 (讓 4, 5 也有浮空感)
		if not player.is_on_floor() and combo_step in [4, 5]:
			if anim_time < 0.1:
				new_y = air_thrust_force * 0.5 # 出招瞬間微幅上浮
			else:
				# 隨後套用緩降重力
				new_y += (player.default_gravity * air_skill_gravity_rate) * delta
				
		if anim_time >= 0.1 and not is_vfx_fired:
			is_vfx_fired = true
			
			_spawn_weapon_vfx(LIGHT_ATTACK_CONFIG[combo_step])
				
			if combo_step in [4, 5]:
				var angles = []
				
				if combo_step == 4:
					angles = [deg_to_rad(-10.0), 0.0, deg_to_rad(-20.0)]
				elif combo_step == 5:
					angles = [deg_to_rad(10.0), 0.0, deg_to_rad(20.0)]
					
				for angle in angles:
					_spawn_laser_projectile(LIGHT_ATTACK_CONFIG[combo_step], angle)
				
	elif combo_step == 20:
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		
		if anim_time >= 0.1 and not is_vfx_fired:
			is_vfx_fired = true
			_spawn_weapon_vfx(SKILL_CONFIG[combo_step]) # 🌟 拔除防護網，殘影必須發射特效！
				
		if anim_time >= 1.15 and not is_tower_spawned:
			is_tower_spawned = true
			
			# 1. 鏡頭震動防護
			
			
			# 2. 拔除防護網蓋塔
			_spawn_healing_tower()
			
			
			for i in range(9):
				var angle = deg_to_rad(i * 40.0)
				_spawn_laser_projectile(SKILL_CONFIG[combo_step], angle)
				
		# 🌟 玩家無敵防護 (只有本體才需要無敵，殘影不需要)
		if not player.name.begins_with("Phantom"):
			if anim_time >= 0.0 and anim_time <= 1.0:
				player.invincible_time_left = max(player.invincible_time_left, 0.1) 
			elif anim_time > 1.0 and anim_time < 1.1:
				if player.invincible_timer.time_left == 0:
					player.invincible_time_left = 0.0
					
	elif combo_step == 30:
		# 施法時的地面摩擦力
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		
		# 在 0.1 秒時發射特效 (第一次：起手結印)
		if anim_time >= 0.1 and not is_vfx_fired:
			is_vfx_fired = true
			_spawn_weapon_vfx(SKILL_CONFIG[combo_step])
			
	# ==========================================
	# 🌟 戰技下退出 (40) 物理邏輯
	# ==========================================
	elif combo_step == 40:
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		
		# 🌟 新增空戰緩降感
		if not player.is_on_floor():
			if anim_time < 0.1: new_y = air_thrust_force * 0.5
			else: new_y += (player.default_gravity * air_skill_gravity_rate) * delta
			
	# ==========================================
	# 🌟 戰技下進入 (50) 物理與動態激光連發邏輯
	# ==========================================
	elif combo_step == 50:
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		
		# 🌟 新增空戰緩降感
		if not player.is_on_floor():
			if anim_time < 0.1: new_y = air_thrust_force * 0.5
			else: new_y += (player.default_gravity * air_skill_gravity_rate) * delta
		
		# 在 0.7 秒時噴發激光
		if anim_time >= 0.7 and not is_vfx_fired:
			is_vfx_fired = true
			
			# 🌟 新增：讀取 50 號字典裡的 vfx_anim ("a4") 並噴發特效
			_spawn_weapon_vfx(SKILL_CONFIG[combo_step])
			
			# ==========================================
			# 💥 新增：發射瞬間的強烈鏡頭震動！(嚴格排除殘影)
			# ==========================================
			if not player.name.begins_with("Phantom"): 
				if CombatManager.has_method("apply_camera_shake"): 
					# 給予 40.0 的震動強度，匹配多管齊發的後座力！
					CombatManager.apply_camera_shake(40.0) 
			
			# 🌟 動態計算激光數量 (因為 PhantomStriker 已經幫我們複製了，這裡直接讀取就行！)
			var num_lasers = clamp(int(current_talisman_charge / 10), 1, 5)
			var angles = []
			
			match num_lasers:
				1: angles = [0.0]
				2: angles = [deg_to_rad(-10.0), deg_to_rad(10.0)]
				3: angles = [deg_to_rad(-15.0), 0.0, deg_to_rad(15.0)]
				4: angles = [deg_to_rad(-20.0), deg_to_rad(-7.0), deg_to_rad(7.0), deg_to_rad(20.0)]
				5: angles = [deg_to_rad(-20.0), deg_to_rad(-10.0), 0.0, deg_to_rad(10.0), deg_to_rad(20.0)]
				
			print("🌟 [戰技下] 根據靈符值 ", current_talisman_charge, "，發射了 ", num_lasers, " 條激光！")
				
			for angle in angles:
				_spawn_laser_projectile(SKILL_CONFIG[combo_step], angle)
		
	# ==========================================
	# 🌟 常態空中普攻 (60) 物理與滯空激光邏輯 (對齊太刀浮空感)
	# ==========================================
	elif combo_step == 60:
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		
		# 🌟 賦予太刀般的浮空感
		if anim_time < 0.1:
			new_y = air_thrust_force # 拔槍瞬間上浮
		else:
			new_y += (player.default_gravity * air_skill_gravity_rate) * delta # 之後緩緩落下
			
		if anim_time >= 0.1 and not is_vfx_fired:
			is_vfx_fired = true
			_spawn_weapon_vfx(LIGHT_ATTACK_CONFIG[combo_step])
			_spawn_laser_projectile(LIGHT_ATTACK_CONFIG[combo_step], 0.0)
	
	# ==========================================
	# 🌌 大招 (80) - 4 連擊與時停巨砲特寫
	# ==========================================
	elif combo_step == 80:
		var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * 5.0 * (speed_mult * speed_mult) * delta)
		new_y = 0.0 
		
		if anim_time >= 0.05 and not is_time_stop_triggered:
			is_time_stop_triggered = true 
			if player.has_method("trigger_time_stop"):
				player.trigger_time_stop(3.0, 0.001) 
			player.animation_player.speed_scale = 1.0 / 0.001 
			
		if anim_time >= 0.05 and _tsubame_zoom_phase == 0:
			_tsubame_zoom_phase = 1
			_apply_charge_zoom(Vector2(1.2, 1.2), 0.3) 
			
		# 🌟 大挪移核心：在 1.82 秒時觸發終極巨砲！
		if anim_time >= 1.82 and not is_tower_spawned:
			is_tower_spawned = true # 鎖死，避免重複發射
			
			_tsubame_zoom_phase = 2
			if CombatManager.has_method("apply_camera_shake"):
				# 使用 70.0 的狂暴震動，匹配巨砲後座力
				CombatManager.apply_camera_shake(100.0, 0.4)
				
			# 追加激光噴發瞬間的 A6 爆發特效
			_spawn_weapon_vfx({"vfx_anim": "a6"})
			
			# 🌟 正式向前方轟出巨型雷射！
			_spawn_laser_projectile(SKILL_CONFIG[combo_step], 0.0)
	
	# ==========================================
	# 🌟 變奏技能 (90) - 時停入場與 50 號雷射噴發
	# ==========================================
	elif combo_step == 90:
		var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * 2.0 * (speed_mult * speed_mult) * delta)
		
		# 空戰緩降感 (完美支援空中切人變奏！)
		if not player.is_on_floor():
			if anim_time < 0.1: new_y = air_thrust_force * 0.5
			else: new_y += (player.default_gravity * air_skill_gravity_rate) * delta
			
		# 🌟 0.02s 觸發魔女時間與逆時停特效
		if anim_time >= 0.02 and not is_time_stop_triggered:
			is_time_stop_triggered = true
			
			if player.has_method("trigger_time_stop"):
				player.trigger_time_stop(0.8, 0.05)
				
			player.animation_player.speed_scale = 4.0 
			player.invincible_time_left = 2.0
			
			# ==========================================
			# 🌟 新增：變奏入場逆時停特效與音效
			# ==========================================
			# 呼叫音效 (這裡暫時填 "wind"，你可以換成 action_sfx_bank 裡喜歡的標籤)
			AudioManager.play_action_sfx("ult", -2.0)
			
			if player.has_method("spawn_anim_vfx"):
				player.spawn_anim_vfx("Aggregation ring", 0, -20, Vector2(2.5, 2.5), 0, Color(0.8, 0.3, 1.0, 1.0), Color(0.0, 0.5, 1.0, 1.0), false, 2, 1.0)
				
		# 🎥 鏡頭推進特寫
		if anim_time >= 0.02 and _tsubame_zoom_phase == 0:
			_tsubame_zoom_phase = 1
			_apply_charge_zoom(Vector2(1.15, 1.15), 1.2)
			
		# 🌟 0.7 秒：同 50 號招式噴發激光與震動！
		if anim_time >= 0.7 and not is_vfx_fired:
			is_vfx_fired = true
			_spawn_weapon_vfx(SKILL_CONFIG[combo_step])
			
			if not player.name.begins_with("Phantom"): 
				if CombatManager.has_method("apply_camera_shake"): 
					CombatManager.apply_camera_shake(40.0) 
			
			var num_lasers = clamp(int(current_talisman_charge / 10), 1, 5)
			var angles = []
			match num_lasers:
				1: angles = [0.0]
				2: angles = [deg_to_rad(-10.0), deg_to_rad(10.0)]
				3: angles = [deg_to_rad(-15.0), 0.0, deg_to_rad(15.0)]
				4: angles = [deg_to_rad(-20.0), deg_to_rad(-7.0), deg_to_rad(7.0), deg_to_rad(20.0)]
				5: angles = [deg_to_rad(-30.0), deg_to_rad(-15.0), 0.0, deg_to_rad(15.0), deg_to_rad(30.0)]
				
			print("🌟 [變奏出場] 根據靈符值 ", current_talisman_charge, "，發射了 ", num_lasers, " 條激光！")
			for angle in angles:
				_spawn_laser_projectile(SKILL_CONFIG[combo_step], angle)
				
	return Vector2(new_x, new_y)

func _spawn_weapon_vfx(config: Dictionary) -> void:
	if not TALISMAN_VFX_SCENE: return
	
	var vfx = TALISMAN_VFX_SCENE.instantiate()
	
	# ==========================================
	# 🌟 核心防呆：先給座標、方向和圖層，再加入場景樹！
	# ==========================================
	vfx.global_position = player.global_position + Vector2(30 * player.direction, -30)
	vfx.scale.x = player.direction
	vfx.z_index = player.z_index + 1
	
	get_tree().current_scene.add_child(vfx) # 🌟 移到賦值後面！
	
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	
	var vfx_anim_name = config.get("vfx_anim", "")
	if vfx.has_method("play_and_free") and vfx_anim_name != "":
		vfx.play_and_free(vfx_anim_name, speed_mult)
	
	var fly_dist = config.get("vfx_fly_dist", 0.0)
	if fly_dist > 0.0:
		var target_pos = vfx.global_position + Vector2(fly_dist * player.direction, 0)
		var tween = create_tween()
		tween.set_speed_scale(speed_mult) 
		tween.tween_property(vfx, "global_position", target_pos, 0.3).set_ease(Tween.EASE_OUT)

func _spawn_healing_tower() -> void:
	if not HEALING_TOWER_SCENE: return
	
	var tower = HEALING_TOWER_SCENE.instantiate()
	
	# ==========================================
	# 🌟 核心修復：先給座標、面向與圖層，再加入場景樹！
	# ==========================================
	tower.global_position = player.global_position + Vector2(player.direction, 0)
	
	if "direction" in tower:
		tower.direction = player.direction   # 傳遞面向數值給塔內部
	tower.scale.x = player.direction         # 🌟 直接翻轉整個塔的外觀與動畫！
	
	tower.z_index = 1
	
	get_tree().current_scene.add_child(tower)
	
	print("✨ [符咒] 釋放中立戰技，已生成回血塔！")

# ==========================================
# ⚙️ 內部實作與 Hitbox 屬性灌注 (對齊長槍防呆寫法)
# ==========================================
func _play_attack(config: Dictionary) -> void:
	_is_hitbox_locked = false 
	disable_hitbox()
	
	current_action_type = config.get("action_type", Weapon.ActionType.NONE)
	
	var target_hitbox_name = config.get("hitbox_name", "Hitbox")
	var hitbox := get_node_or_null(target_hitbox_name) as Hitbox
	
	if hitbox:
		hitbox.damage_amount = config.get("base_dmg", 100)
		hitbox.max_hits = config.get("max_hits", 1)
		hitbox.hit_sfx_type = config.get("hit_sfx_type", "hit")
		
		if "hit_interval" in hitbox: hitbox.hit_interval = config.get("interval", 0.0)
		if "knockback_force" in hitbox: hitbox.knockback_force = config.get("knockback", Vector2.ZERO)
		if "attack_type" in hitbox: hitbox.attack_type = config.get("type", Damage.Type.LIGHT)
		if "sticky_multi_hit" in hitbox: hitbox.sticky_multi_hit = config.get("sticky", false)
		if "shake_intensity" in hitbox: hitbox.shake_intensity = config.get("shake", 2.5) 
		if "shake_on_hit_only" in hitbox: hitbox.shake_on_hit_only = config.get("shake_on_hit_only", true)
		
		if "energy_reward" in hitbox: hitbox.energy_reward = float(config.get("energy", 0))
		if "switch_reward" in hitbox: hitbox.switch_reward = float(config.get("switch", 0))
		
		hitbox.spark_type = 0
		hitbox.spark_scale = 0.3
		hitbox.spark_color = Color(0.8, 0.3, 1.0, 1.0)
		hitbox.aura_color = Color(0.0, 0.5, 1.0, 1.0)
		
		hitbox.hit_targets.clear()
		
		_current_energy_reward = float(config.get("energy", 0))
		_current_switch_reward = float(config.get("switch", 0))
		_current_charge_reward = int(config.get("charge_reward", 0)) 
		_multi_hit_energy = config.get("multi_hit_energy", false)
		_has_granted_resources_this_step = false
		
		if current_active_hitbox and current_active_hitbox.hit.is_connected(_on_hitbox_hit):
			current_active_hitbox.hit.disconnect(_on_hitbox_hit)
			
		current_active_hitbox = hitbox 
		
		if not current_active_hitbox.hit.is_connected(_on_hitbox_hit):
			current_active_hitbox.hit.connect(_on_hitbox_hit)
			
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _on_hitbox_hit(hurtbox: Node) -> void:
	if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: 
		return

	if _multi_hit_energy or not _has_granted_resources_this_step:
		if _current_charge_reward > 0:
			gain_talisman_charge(_current_charge_reward)
			
		if _current_energy_reward > 0 or _current_switch_reward > 0:
			if player.has_method("add_weapon_resource"):
				player.add_weapon_resource(WEAPON_ID, _current_energy_reward, _current_switch_reward)
				
		_has_granted_resources_this_step = true

# ==========================================
# 🎬 狀態機防呆與收招結算 (對齊收刀邏輯)
# ==========================================
func is_handling_gravity() -> bool:
	# 🌟 當玩家在空中打出強化普攻 (4,5)、切換型態 (40,50) 或常態空戰 (60) 時，接管重力！
	if not player.is_on_floor() and combo_step in [4, 5, 40, 50, 60, 90]:
		return true
	if combo_step == 80: return true 
	return false

func is_attack_finished() -> bool:
	if not is_attacking: return true
	if not player.animation_player.is_playing():
		
		# 🌟 統一使用 begins_with 對齊太刀
		if combo_step == 20 and not player.name.begins_with("Phantom"):
			if player.invincible_timer.time_left == 0:
				player.invincible_time_left = 0.0
				
		player.is_input_locked = false
		is_attacking = false
		step_cooldown = 0.0
		last_attack_time = Time.get_ticks_msec() / 1000.0
		
		if combo_step == 60:
			air_attack_locked = true 
		
		_is_hitbox_locked = true 
		disable_hitbox()
		
		var p_scabbard = player.get("scabbard")
		if not requires_sheath() and p_scabbard:
			p_scabbard.fade_in()
			
		# 🌟 大招收尾：啟動 15 秒脫手 Buff 並歸位鏡頭
		if combo_step == 80:
			is_ult_buff_active = true
			ult_buff_duration_timer = 15.0
			ult_heal_timer = 2.0  # 💚 設定為 2 秒一跳
			ult_laser_timer = 1.0 # ⚔️ 設定為 1 秒一跳
			
			# ==========================================
			# 🌟 新增：生成持續性 Buff VFX 並「掛在玩家身上」
			# ==========================================
			if TALISMAN_VFX_SCENE:
				active_ult_buff_vfx = TALISMAN_VFX_SCENE.instantiate()
				player.add_child(active_ult_buff_vfx) # 關鍵：加給 player，而不是自己！
				active_ult_buff_vfx.position = Vector2(0, -30) # 微調高度，對齊身體中心
				active_ult_buff_vfx.z_index = 1
				
				# 假設你在 TalismanVFX 裡面有做一個叫 "ult_buff_loop" 的持續播放動畫
				# (如果你的節點名稱不同，請自行把 AnimationPlayer 替換成對應名稱)
				if active_ult_buff_vfx.has_node("AnimationPlayer"):
					active_ult_buff_vfx.get_node("AnimationPlayer").play("ult_buff_loop")
			
			_tsubame_zoom_phase = 0
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.4)
			player.animation_player.speed_scale = 1.0 
			if player.has_method("clear_time_stop"): player.clear_time_stop()
			print("🔥 [符咒] 大招連擊結束！正式進入 15 秒 Buff 狀態！")
		
		return true
	return false

func cancel_attack() -> void:
	if not player.is_on_floor() and combo_step == 60:
		air_attack_locked = true
	
	if combo_step == 20 and is_attacking and not player.name.begins_with("Phantom"):
		if player.invincible_timer.time_left == 0:
			player.invincible_time_left = 0.0

	player.is_input_locked = false
	is_attacking = false
	combo_step = 0
	step_cooldown = 0.0
	is_vfx_fired = false
	is_tower_spawned = false 
	_is_hitbox_locked = true 
	# 🌟 打斷時強制解除時停與鏡頭特寫
	if is_time_stop_triggered or _tsubame_zoom_phase > 0:
		is_time_stop_triggered = false
		_tsubame_zoom_phase = 0
		_apply_charge_zoom(ZOOM_LEVELS[0], 0.0)
		player.animation_player.speed_scale = 1.0
		if player.has_method("clear_time_stop"): player.clear_time_stop()
	
	disable_hitbox()
	
	var p_scabbard = player.get("scabbard")
	if p_scabbard: 
		p_scabbard.fade_in()

func requires_sheath() -> bool:
	if combo_step == 0:
		return false
	return combo_step not in no_sheath_steps

# ==========================================
# 🌟 激光投射物生成器 (完全對齊太刀與長槍投射物標準工法)
# ==========================================
func _spawn_laser_projectile(config: Dictionary, angle_offset: float) -> void:
	if not LASER_SCENE: return
	
	var laser = LASER_SCENE.instantiate()
	
	var offset_x = config.get("laser_offset", Vector2(30.0, -30.0)).x * player.direction
	var offset_y = config.get("laser_offset", Vector2(30.0, -30.0)).y
	laser.global_position = player.global_position + Vector2(offset_x, offset_y)
	var base_dir = Vector2(player.direction, 0.0)
	laser.fly_direction = base_dir.rotated(angle_offset)
	laser.direction = player.direction 
	laser.thrower = player 
	
	# ==========================================
	# 🌟 動態設定巨型與追蹤 (預設為 1.0 倍且開啟追蹤)
	# ==========================================
	laser.scale = Vector2.ONE * config.get("laser_scale", 1.0)
	laser.is_tracking = config.get("laser_tracking", true)
	
	# 裝備發放完畢，正式加入場景樹！
	get_tree().current_scene.add_child(laser)
	
	# 等待一影格，確保內部的 hitbox 已經 ready 完畢
	await get_tree().process_frame
	if not is_instance_valid(laser) or not laser.hitbox: return
	
	# ==========================================
	# 🌟 完全解耦：優先讀取 laser_ 專屬屬性，若無則降級讀取 base 屬性
	# (這樣 A4, A5 的普通雷射不用改字典，照樣能讀到原本的屬性)
	# ==========================================
	laser.hitbox.damage_amount = config.get("laser_dmg", config.get("base_dmg", 160))
	laser.hitbox.hit_sfx_type = config.get("hit_sfx_type", "hit")
	laser.hitbox.max_hits = 1
	laser.hitbox.sticky_multi_hit = false
	
	laser.hitbox.attack_type = config.get("laser_type", config.get("type", Damage.Type.LIGHT))
	
	if "knockback_force" in laser.hitbox:
		laser.hitbox.knockback_force = config.get("laser_knockback", config.get("knockback", Vector2.ZERO))
		
	# 🌟 新增：獨立配置激光命中時的畫面震動
	if "shake_intensity" in laser.hitbox:
		laser.hitbox.shake_intensity = config.get("laser_shake", config.get("shake", 0.0))
		laser.hitbox.shake_on_hit_only = true
	
	# 套用符咒專屬色系火花
	laser.hitbox.spark_type = 0
	laser.hitbox.spark_scale = 0.3
	laser.hitbox.spark_color = Color(0.8, 0.3, 1.0, 1.0) 
	laser.hitbox.aura_color = Color(0.0, 0.5, 1.0, 1.0)
	
	# 對接武器資源獲取監聽器
	var w_energy = float(config.get("energy", 0))
	var w_switch = float(config.get("switch", 0))
	var wave_state = [false]
	
	laser.hitbox.hit.connect(func(hurtbox: Node):
		if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: return
		
		if not wave_state[0]:
			if (w_energy > 0 or w_switch > 0) and player.has_method("add_weapon_resource"):
				player.add_weapon_resource(WEAPON_ID, w_energy, w_switch)
			wave_state[0] = true
	)
	
# ==========================================
# 🎥 鏡頭特寫控制 (對接 CombatManager 仲裁系統)
# ==========================================
func _apply_charge_zoom(target_zoom: Vector2, duration: float = 0.2) -> void:
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
				if CombatManager.get("is_close_up_active") != null:
					CombatManager.is_close_up_active = false
			)
		else:
			if CombatManager.get("is_close_up_active") != null:
				CombatManager.is_close_up_active = true
			_camera_tween.tween_property(camera, "zoom", target_zoom, duration)
			
# ==========================================
# 🛡️ 狀態機防護名單 (The Bouncer's List)
# ==========================================
func can_air_light() -> bool:
	if air_attack_locked or _get_ground_distance() < min_air_attack_height: return false
	return true

func can_use_heavy() -> bool:
	if not player.is_on_floor(): 
		# 🌟 允許空中施放戰技下 (型態切換)
		if Input.is_action_pressed("move_down"):
			if skill_3_timer > 0:
				print("⏳ [防護網攔截] 符咒戰技下(型態切換)冷卻中！")
				return false
			return true
		return false
	
	if Input.is_action_pressed("move_up"):
		if skill_2_timer > 0:
			print("⏳ [防護網攔截] 符咒戰技上(挑飛)冷卻中！")
			return false
	elif Input.is_action_pressed("move_down"):
		# 🌟 攔責戰技下的冷卻
		if skill_3_timer > 0:
			print("⏳ [防護網攔截] 符咒戰技下(型態切換)冷卻中！")
			return false
	else:
		if skill_1_timer > 0:
			print("⏳ [防護網攔截] 符咒中立戰技冷卻中！")
			return false
			
	return true

func can_use_ultimate() -> bool:
	if ult_timer > 0: return false 
	if not player.is_on_floor(): return false 
	
	if player.has_method("get_weapon_energy"):
		if player.get_weapon_energy(WEAPON_ID) < ult_energy_cost:
			print("⚠️ [", WEAPON_ID, "] 大招能量不足！需要: ", ult_energy_cost)
			return false 
			
	return true

# ==========================================
# 💾 輔助工具與儲存
# ==========================================
func _get_ground_distance() -> float:
	var space_state = player.get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(player.global_position, player.global_position + Vector2(0, 1000))
	query.collision_mask = 1 
	var result = space_state.intersect_ray(query)
	if result: return player.global_position.distance_to(result.position)
	return 1000.0 

func export_weapon_data() -> Dictionary:
	return {
		"current_talisman_charge": current_talisman_charge,
		"is_enhanced_mode": is_enhanced_mode, # 🌟 納入備份
		"skill_1_timer": skill_1_timer if "skill_1_timer" in self else 0.0,
		"skill_2_timer": skill_2_timer if "skill_2_timer" in self else 0.0,
		"skill_3_timer": skill_3_timer if "skill_3_timer" in self else 0.0,
		"ult_timer": ult_timer if "ult_timer" in self else 0.0,
		
		# 🌟 新增：將大招的脫手 Buff 狀態與所有計時器全部打包
		"is_ult_buff_active": is_ult_buff_active,
		"ult_buff_duration_timer": ult_buff_duration_timer,
		"ult_heal_timer": ult_heal_timer,
		"ult_laser_timer": ult_laser_timer
	}

func import_weapon_data(data: Dictionary) -> void:
	current_talisman_charge = data.get("current_talisman_charge", 0)
	is_enhanced_mode = data.get("is_enhanced_mode", false) # 🌟 納入還原
	if "skill_1_timer" in self: skill_1_timer = data.get("skill_1_timer", 0.0)
	if "skill_2_timer" in self: skill_2_timer = data.get("skill_2_timer", 0.0)
	if "skill_3_timer" in self: skill_3_timer = data.get("skill_3_timer", 0.0)
	if "ult_timer" in self: ult_timer = data.get("ult_timer", 0.0)
	
	# 🌟 新增：還原大招 Buff 狀態與計時器
	is_ult_buff_active = data.get("is_ult_buff_active", false)
	ult_buff_duration_timer = data.get("ult_buff_duration_timer", 0.0)
	ult_heal_timer = data.get("ult_heal_timer", 0.0)
	ult_laser_timer = data.get("ult_laser_timer", 0.0)
	
	# 🌟 神級細節：跨場景重建特效
	# 如果讀檔發現 Buff 還在，但身上的 VFX 已經因為過地圖而被清除了，就立刻重新生成一個掛回去！
	if is_ult_buff_active and not is_instance_valid(active_ult_buff_vfx):
		if TALISMAN_VFX_SCENE and is_instance_valid(player):
			active_ult_buff_vfx = TALISMAN_VFX_SCENE.instantiate()
			player.add_child(active_ult_buff_vfx)
			active_ult_buff_vfx.position = Vector2(0, -30)
			active_ult_buff_vfx.z_index = 1
			
			if active_ult_buff_vfx.has_node("AnimationPlayer"):
				active_ult_buff_vfx.get_node("AnimationPlayer").play("ult_buff_loop")
			print("✨ [符咒] 跨場景重建大招 Buff 光環特效成功！")
	
func enable_hitbox(shape_name: String = "") -> void:
	if _is_hitbox_locked: return
	if current_active_hitbox:
		for child in current_active_hitbox.get_children():
			if child is CollisionShape2D:
				if shape_name == "" or child.name == shape_name:
					child.set_deferred("disabled", false)

func disable_hitbox(shape_name: String = "") -> void:
	if current_active_hitbox:
		for child in current_active_hitbox.get_children():
			if child is CollisionShape2D:
				if shape_name == "" or child.name == shape_name:
					child.set_deferred("disabled", true)
