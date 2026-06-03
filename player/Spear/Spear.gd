class_name Spear
extends Weapon
## 武器腳本：長槍 (Spear) - 四段連擊版

const WEAPON_ID: String = "spear"

const SPEAR_WAVE_SCENE = preload("res://player/Spear/ult_wave.tscn") 
const ZOOM_LEVELS = { 0: Vector2(1.0, 1.0), 1: Vector2(1.05, 1.05), 2: Vector2(1.1, 1.1), 3: Vector2(1.15, 1.15) }

# ==========================================
# 📖 招式數據庫 (Data-Driven Combat Config)
# ==========================================
const LIGHT_ATTACK_CONFIG = {
	1: {"anim": "spear/attack_1", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(50.0, 0.0), "base_dmg": 300, "energy": 500, "switch": 500, "pozhen": 10,"hit_sfx_type": "hit"},
	2: {"anim": "spear/attack_2", "hitbox_name": "Hitbox", "max_hits": 2, "interval": 0.1, "knockback": Vector2(50.0, 0.0), "base_dmg": 350, "energy": 5, "switch": 5, "pozhen": 10,"hit_sfx_type": "hit"},
	3: {"anim": "spear/attack_3", "hitbox_name": "Hitbox", "max_hits": 3, "interval": 0.1, "knockback": Vector2(20.0, 0.0), "base_dmg": 150, "energy": 5, "switch": 4, "pozhen": 10,"hit_sfx_type": "hit"},
	4: {"anim": "spear/attack_4", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(600.0, 0.0), "shake": 20.0, "base_dmg": 600, "energy": 10, "switch": 15, "pozhen": 10,"hit_sfx_type": "hit"}
}

const SKILL_CONFIG = {
	# 戰技 20：迴旋絞殺 (傷害由飛行物造成，故 base_dmg 為 0)
	20: {"anim": "spear/c1", "hitbox_name": "None", "max_hits": 1, "interval": 0.0, "knockback": Vector2.ZERO, "base_dmg": 0, "energy": 0, "switch": 0,"hit_sfx_type": "hit"},
	# 戰技 21：大範圍聚怪 (多次判定、輕微上浮與強烈橫向拉力)
	21: {"anim": "spear/c2", "hitbox_name": "C2", "type": Damage.Type.LIGHT, "max_hits": 4, "interval": 0.12, "knockback": Vector2(220.0, -30.0), "pull": true, "shake": 15.0, "base_dmg": 50, "energy": 3, "switch": 3, "pozhen": 10, "sticky": true,"hit_sfx_type": "hit"},
	# 戰技 22：向上挑飛 (Skill 2)
	22: {"anim": "spear/c3", "hitbox_name": "C3", "type": Damage.Type.HEAVY, "max_hits": 1, "interval": 0.0, "knockback": Vector2(0.0, -600.0), "shake": 60.0, "base_dmg": 500, "energy": 10, "switch": 15, "pozhen": 10,"hit_sfx_type": "hit_2"},
	# 強化普攻 (30)：消耗 40 點破陣值發動
	30: {"anim": "spear/attack_enhanced", "hitbox_name": "attack_enhanced", "type": Damage.Type.HEAVY, "max_hits": 4, "interval": 0.1, "knockback": Vector2(100.0, -100.0), "shake": 15.0, "base_dmg": 800, "energy": 10, "switch": 20, "pozhen": 0, "sticky": true,"hit_sfx_type": "hit"},
	# 新增：大招啟動演出 (80)
	80: {"anim": "spear/attack_ult", "hitbox_name": "None", "max_hits": 1, "interval": 0.0, "knockback": Vector2.ZERO, "base_dmg": 0, "energy": 0, "switch": 0},
	# 大招氣刃發射與後搖 (81)
	81: {"anim": "spear/attack_ult_end", "hitbox_name": "None", "max_hits": 1, "interval": 0.0, "knockback": Vector2.ZERO, "base_dmg": 0, "energy": 0, "switch": 0},
	
	# 🌟 補上缺失的拼圖：變奏技能前搖 (90) - 純演出，無傷害
	90: {"anim": "spear/90", "hitbox_name": "None", "type": Damage.Type.LIGHT, "knockback": Vector2.ZERO, "shake": 0.0, "shake_on_hit_only": true, "base_dmg": 0, "energy": 0, "switch": 0, "pozhen": 0 }
}

# [空戰字典] (數值與動畫名稱你可以後續再微調)
const AIR_ATTACK_CONFIG = {
	61: { "anim": "spear/air_attack_1", "hitbox_name": "Air_J", "max_hits": 4, "interval": 0.15, "shake": 10.0, "type": Damage.Type.LIGHT, "knockback": Vector2(10.0, -150.0), "base_dmg": 50, "energy": 1, "switch": 2, "pozhen": 10, "sticky": true,"hit_sfx_type": "hit"},
	62: { "anim": "spear/air_attack_2", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "shake": 50.0, "type": Damage.Type.HEAVY, "knockback": Vector2(300.0, 600.0), "base_dmg": 300, "energy": 2, "switch": 4, "pozhen": 10,"hit_sfx_type": "hit"},
}
# ==========================================
# 🎛️ 內部狀態變數
# ==========================================
@export_group("空戰設定 (Air Combat)")
@export var min_air_attack_height: float = 40.0 
@export var air_thrust_force: float = -150.0    
var air_attack_locked: bool = false # 空中打完一套的鎖死標記

var is_spear_thrown: bool = false # 防止重複發射的防呆鎖
const BOOMERANG_SCENE = preload("res://player/Spear/SpearBoomerang.tscn")

var is_time_stop_triggered: bool = false 
var _ult_zoom_phase: int = 0 
var _camera_tween: Tween
var is_wave_fired: bool = false 
# 長按計時器
var light_hold_timer: float = 0.0

# ==========================================
# 🌟 專屬資源記憶體 (解耦 Hitbox 用)
# ==========================================
var _current_energy_reward: float = 0.0
var _current_switch_reward: float = 0.0
var _current_pozhen_reward: int = 0
var _multi_hit_energy: bool = false
var _has_granted_resources_this_step: bool = false

# ==========================================
# 🌀 破陣迴路 (Po-Zhen System)
# ==========================================
var current_pozhen: int = 0
const MAX_POZHEN: int = 40

# ==========================================
# 🚀 戰技上 (挑飛) 設定
# ==========================================
@export var launch_start_time: float = 0.4
	  # 動畫播到幾秒時起飛 (可依長槍動畫微調)
@export var launch_duration: float = 0.06        # 推進力持續時間
@export var vertical_launch_speed: float = -650.0 # 升空速度

var is_launch_triggered: bool = false
var launch_timer: float = 0.0

# ==========================================
# 🌌 大招系統 (Ultimate Buff)
# ==========================================
@export var ult_energy_cost: float = 100.0  # 大招能量成本
const ULT_DURATION: float = 30.0            # 大招狀態持續時間
const MAX_ULT_ATTACKS: int = 24             # 大招狀態下的強化普攻次數

var is_ult_active: bool = false             # 標記大招狀態是否開啟
var ult_buff_timer: float = 0.0             # 大招剩餘時間
var ult_attack_count: int = 0               # 已打出的強化普攻次數

@export var no_sheath_steps: Array[int] = [22]

var combo_step: int = 0
var is_attacking: bool = false
var step_cooldown: float = 0.0

@export var combo_timeout: float = 0.3 
var last_attack_time: float = 0.0

var current_active_hitbox: Hitbox = null
var _is_hitbox_locked: bool = false

func start_light_attack() -> void:
	if step_cooldown > 0: return
	
	# ==========================================
	# 🪽 空戰攔截與處理 (Air Combat)
	# ==========================================
	if not player.is_on_floor():
		# 檢查鎖死狀態或高度限制
		if air_attack_locked or _get_ground_distance() < min_air_attack_height:
			is_attacking = false
			return
			
		# 🌟 終極防護網：絕對不允許在空中從強普 (30) 派生回 61！
		if combo_step == 30:
			is_attacking = false
			return
			
		# 🌟 長槍的空中連段：只能打 61 -> 62，打完就鎖死！
		if combo_step == 61:
			combo_step = 62
			air_attack_locked = true # 打出第二段後，宣告這趟空中旅程結束，鎖死！
		else:
			combo_step = 61
			
		step_cooldown = 0.15
		is_attacking = true
		
		# 賦予極限轉向
		var input_dir = Input.get_axis("move_left", "move_right")
		if input_dir != 0:
			player.direction = 1 if input_dir > 0 else -1
			
		_play_air_step(combo_step)
		return
	
	step_cooldown = 0.15
	
	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time > combo_timeout:
			combo_step = 0
			
	# ==========================================
	# 🌟 大招狀態攔截 (A3 無限連刺迴圈)
	# ==========================================
	if is_ult_active:
		combo_step = 3 # 永遠強制指定為 A3 
		ult_attack_count += 1
		print("🔥 大招強化連刺！剩餘次數: ", MAX_ULT_ATTACKS - ult_attack_count)
		
		# 檢查次數是否耗盡
		if ult_attack_count >= MAX_ULT_ATTACKS:
			is_ult_active = false
			ult_buff_timer = 0.0
	else:
		# --- 正常狀態下的四段普攻 (目前空中也會播這個) ---
		combo_step += 1
		if not LIGHT_ATTACK_CONFIG.has(combo_step): 
			combo_step = 1
	
	is_attacking = true
	_play_attack(LIGHT_ATTACK_CONFIG[combo_step])
	
	# --- 蓄力預輸入補償 ---
	if Input.is_action_pressed("attack"): light_hold_timer = 0.15
	else: light_hold_timer = 0.0
	
func start_heavy_attack() -> void:
	if step_cooldown > 0: return
	
	if not player.is_on_floor():
		is_attacking = false
		return
	
	step_cooldown = 0.15
	
	is_launch_triggered = false
	
	# 極限轉向特權！
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0:
		player.direction = 1 if input_dir > 0 else -1
	
	is_attacking = true
	is_spear_thrown = false 
	
	if Input.is_action_pressed("move_down"): 
		# 【按下 + 重擊】發動大範圍聚怪 (21)
		combo_step = 21 
		skill_3_timer = skill_3_cd 
		_play_attack(SKILL_CONFIG[combo_step])
		print("🌪️ 發動大範圍聚怪技能 (Skill 3)！")
		
	elif Input.is_action_pressed("move_up"):
		# 🌟 【按上 + 重擊】發動挑飛 (22)
		combo_step = 22 
		skill_2_timer = skill_2_cd 
		_play_attack(SKILL_CONFIG[combo_step])
		print("🚀 發動向上挑飛 (Skill 2)！")
		
	else:
		# 【單按重擊】發動迴旋鏢 (20)
		combo_step = 20 
		skill_1_timer = skill_1_cd # 🌟 讓迴旋鏢觸發技能一的冷卻！
		_play_attack(SKILL_CONFIG[combo_step])
		print("🪃 丟出迴旋鏢 (Skill 1)！")
	
func start_intro_skill() -> void:
	step_cooldown = 0.15
	is_attacking = true
	
	is_spear_thrown = false 
	# 🌟 核心修正：這裡必須是 90！才會跑特寫與時停！
	combo_step = 90 
	
	_play_attack(SKILL_CONFIG[combo_step])
	print("🌪️ [長槍] 變奏技能發動")
	
func start_ultimate() -> void:
	if player.has_method("consume_weapon_energy"):
		player.consume_weapon_energy(WEAPON_ID, ult_energy_cost)
		
	step_cooldown = 0.15
	is_attacking = true
	combo_step = 80
	
	# 🌟 核心防護 2：大招啟動的第 0 幀立刻賦予無敵！
	# 防止剛從受擊狀態恢復，就被殘留的怪物判定框再次打斷吞招！
	player.invincible_time_left = 3.0 
	
	# 重置大招特寫與劍氣變數
	is_time_stop_triggered = false 
	_ult_zoom_phase = 0 
	is_wave_fired = false
	
	# 啟動大招狀態
	is_ult_active = true
	ult_buff_timer = ULT_DURATION
	ult_attack_count = 0
	print("💥 [長槍] 領域展開！獲得 30 秒內 16 次強化 A3 連刺！")
	
	_play_attack(SKILL_CONFIG[combo_step])
	player.is_input_locked = true # 播放大招動畫時鎖死輸入

# ==========================================
# 🌪️ 長槍戰技 2：大範圍聚怪 (Skill 2)
# ==========================================
func start_skill_2() -> void:
	if step_cooldown > 0 or skill_2_timer > 0: return
	
	if not player.is_on_floor():
		is_attacking = false
		return
		
	# 進入冷卻
	skill_2_timer = skill_2_cd
	step_cooldown = 0.15
	is_attacking = true
	combo_step = 21 
	
	# 極限轉向特權！
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0:
		player.direction = 1 if input_dir > 0 else -1
		
	_play_attack(SKILL_CONFIG[combo_step])
	print("🌪️ 發動大範圍聚怪技能！")
	
func can_use_ultimate() -> bool:
		
	if not player.is_on_floor(): return false 
	if player.has_method("get_weapon_energy"):
		if player.get_weapon_energy(WEAPON_ID) < ult_energy_cost:
			print("⚠️ [", WEAPON_ID, "] 大招能量不足！需要: ", ult_energy_cost)
			return false 
	return true
	
# ==========================================
# 💾 武器狀態保存與繼承 (Save / Load)
# ==========================================
func export_weapon_data() -> Dictionary:
	return {
		"current_pozhen": current_pozhen,
		"is_ult_active": is_ult_active,
		"ult_buff_timer": ult_buff_timer,
		"ult_attack_count": ult_attack_count,
		"skill_1_timer": skill_1_timer,
		"skill_2_timer": skill_2_timer,
		"skill_3_timer": skill_3_timer,
	}

func import_weapon_data(data: Dictionary) -> void:
	current_pozhen = data.get("current_pozhen", 0)
	is_ult_active = data.get("is_ult_active", false)
	ult_buff_timer = data.get("ult_buff_timer", 0.0)
	ult_attack_count = data.get("ult_attack_count", 0)
	skill_3_timer = data.get("skill_3_timer", 0.0)
# ==========================================
# ⏱️ 物理與系統計時器 
# ==========================================
func update_timers_only(delta: float) -> void:
	if step_cooldown > 0: 
		step_cooldown -= delta
	
	# 🌟 三大戰技的冷卻倒數
	if skill_1_timer > 0: skill_1_timer -= delta
	if skill_2_timer > 0: skill_2_timer -= delta
	if skill_3_timer > 0: skill_3_timer -= delta
		
	# 處理大招時間倒數
	if ult_buff_timer > 0:
		ult_buff_timer -= delta
		if ult_buff_timer <= 0 and is_ult_active:
			is_ult_active = false
			print("⏳ 大招 30 秒時效已過，狀態強制解除。")
	
	if player.is_on_floor(			):
		air_attack_locked = false # 確保落地立刻解除一套鎖死
		
		# 如果你現在沒有在攻擊，而且腦袋裡還記著空戰的段數，馬上忘掉！
		if not is_attacking and combo_step in [61, 62]:
			combo_step = 0
			
func get_current_velocity(delta: float) -> Vector2:
	if not is_attacking: return player.velocity
	
	if player.is_on_floor(): air_attack_locked = false # 落地強制解鎖空戰！
	
	var new_x = player.velocity.x
	var new_y = player.velocity.y

	if Input.is_action_pressed("attack"):
		light_hold_timer += delta
	else:
		light_hold_timer = 0.0
	
	# ----------------------------------------
	# ⏳ 長按普攻轉強化普攻 (Hold to Enhanced Attack)
	# ----------------------------------------
	if combo_step in [1, 2, 3, 4, 61, 62]:
		# 只有滿 40 點，且確實長按超過 0.35 秒才允許觸發
		if current_pozhen >= 40 and light_hold_timer >= 0.35:
			
			# 🌟 核心手感優化：拔除 50% 強制打斷，改為「只在可以連段的時刻」才允許派生！
			if player.can_combo:
				
				# 🌟 派生瞬間極限轉向
				var input_dir = Input.get_axis("move_left", "move_right")
				if input_dir != 0:
					player.direction = 1 if input_dir > 0 else -1
				
				current_pozhen -= 40 
				combo_step = 30 
				light_hold_timer = 0.0
				
				# 🌟 核心防護：如果是在空中發動強普，立刻沒收空戰特權！不給任何偷渡機會！
				if not player.is_on_floor():
					air_attack_locked = true
					
				_play_attack(SKILL_CONFIG[30])
				print("🔥 消耗 40 點破陣值，轉向並發動強化普攻！")

	# --- 摩擦力減速邏輯 ---
	if combo_step in [1, 2, 3, 4, 21, 30]:
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		
	# 🌟 空戰慣性滑行與微浮空
	elif combo_step in [61, 62]:
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		
		# 🌟 針對 61 加入專屬微浮空邏輯
		if combo_step == 61 and not player.is_on_floor():
			# 瞬間煞車：消除高速下墜慣性
			if new_y > 0:
				new_y = 0.0
			# 套用 15% 微重力
			new_y += (player.default_gravity * 0.6) * delta
			# 限制最大緩降速度
			if new_y > 50.0:
				new_y = 50.0
				
	# 22挑飛與滯空 (Launch & Aerial Hold)
	elif combo_step == 22:
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
			# 🌟 核心修復：這就是那缺失的 0.5 秒前搖！在還沒起飛前，必須用力踩煞車！
			new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
			
	# 戰技 20：丟出迴旋鏢
	elif combo_step == 20:
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		
		var anim_time = player.animation_player.current_animation_position
		if anim_time >= 0.15 and not is_spear_thrown:
			is_spear_thrown = true
			
			spawn_boomerang()
			
	# ----------------------------------------
	# 🌟 變奏技能前搖 (90) - 全局時停、玩家特寫緩速與震動
	# ----------------------------------------
	elif combo_step == 90:
		var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * 2.0 * (speed_mult * speed_mult) * delta)
		
		var anim_time = player.animation_player.current_animation_position
		
		if anim_time >= 0.02 and not is_time_stop_triggered:
			is_time_stop_triggered = true
			
			# 觸發時停 (流速 0.05，持續 0.8 秒)
			if player.has_method("trigger_time_stop"):
				player.trigger_time_stop(0.8, 0.05)
				
			# 玩家自身進入 0.2 倍速慢動作特寫
			player.animation_player.speed_scale = 4.0 
			player.invincible_time_left = 1.5
			
			# ==========================================
			# 🌟 新增：變奏入場逆時停特效與音效
			# ==========================================
			# 呼叫音效 (這裡暫時填 "wind"，你可以換成 action_sfx_bank 裡喜歡的標籤)
			AudioManager.play_action_sfx("ult", -2.0)
			
			# 呼叫特效 (因為在 trigger_time_stop 之後呼叫，它會自動抓取 0.05 的時停倍率並進行逆時停！)
			player.spawn_anim_vfx(
				"Aggregation ring", 
				0, -20,           
				Vector2(2.5, 2.5),
				0,                 
				Color(1.0, 0.4, 0.2, 1.0),      
				Color(1.0, 0.6, 0.2, 1.0),     
				false,             
				2,                 
				1.0                
			)
		# 🎥 [鏡頭特寫]
		if anim_time >= 0.02 and _ult_zoom_phase == 0:
			_ult_zoom_phase = 1
			_apply_charge_zoom(Vector2(1.15, 1.15), 1.2)
			
				
	# ----------------------------------------
	# 🌌 大招前半段 (80) - 領域展開與準備特寫
	# ----------------------------------------
	elif combo_step == 80: 
		var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * 5.0 * (speed_mult * speed_mult) * delta)
		new_y = 0.0 
		
		var anim_time = player.animation_player.current_animation_position
		
		# [領域展開] 0.05s 瞬間進入全屏時停與無敵
		if anim_time >= 0.05 and not is_time_stop_triggered:
			is_time_stop_triggered = true 
			if player.has_method("trigger_time_stop"):
				player.trigger_time_stop(3.0, 0.001) 
			player.animation_player.speed_scale = 1.0 / 0.001 
			player.invincible_time_left = 3.0 # 賦予 80 期間的無敵
			
		# 🎥 [鏡頭 1] 0.05s 推進特寫 (主角準備動作)
		if anim_time >= 0.05 and _ult_zoom_phase == 0:
			_ult_zoom_phase = 1
			_apply_charge_zoom(Vector2(1.5, 1.5), 0.3) 
			
		if anim_time >= 0.70 and _ult_zoom_phase == 1:
			_ult_zoom_phase = 2
			if CombatManager.has_method("apply_camera_shake"):
				# 給予一個輕微但有感的震動 (強度 30.0，持續 0.1 秒)
				CombatManager.apply_camera_shake(30.0, 0.1)

	# ----------------------------------------
	# 🌌 大招後半段 (81) - 時間恢復、發射氣刃與收招
	# ----------------------------------------
	elif combo_step == 81: 
		# 時間已經恢復，不再需要 time_scale 補償
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * 5.0 * delta)
		new_y = 0.0 
		
		# 🌟 動態刷新無敵時間，確保 81 收招全程安全
		player.invincible_time_left = 0.5 
		
		var anim_time = player.animation_player.current_animation_position
		
		# 💥 0.05s 時間開始流動的瞬間，發射巨型劍氣與強烈震動！
		if anim_time >= 0.05 and not is_wave_fired:
			is_wave_fired = true
			
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(150.0, 0.15) # 給予極強的釋放震動
				
			spawn_spear_wave("ult_wave")
			
	return Vector2(new_x, new_y)

# 武器是否接管重力 (True 時總監不干涉 Y 軸)
func is_handling_gravity() -> bool:
	if combo_step == 22 and is_launch_triggered: return true
	
	# 
	if combo_step in [30, 61] and not player.is_on_floor(): return true 
	
	# 讓大招期間完全無視重力懸空
	if combo_step in [80, 81]: return true
	
	return false
	
func requires_sheath() -> bool:
	# 如果根本不在攻擊狀態(0)，當然不用收刀
	if combo_step == 0:
		return false
	# 如果目前的招式「不在」黑名單裡面，就代表需要收刀！
	return combo_step not in no_sheath_steps

func gain_pozhen(amount: int) -> void:
	if amount > 0:
		current_pozhen = mini(current_pozhen + amount, MAX_POZHEN)
		print("🟢 命中！獲得破陣值: ", amount, " | 目前破陣: ", current_pozhen, "/", MAX_POZHEN)
		
# ==========================================
# ⚙️ 內部實作與 Hitbox 屬性灌注
# ==========================================
func _play_attack(config: Dictionary) -> void:
	_is_hitbox_locked = false 
	disable_hitbox()
	
	var target_hitbox_name = config.get("hitbox_name", "Hitbox")
	var hitbox := get_node_or_null(target_hitbox_name) as Hitbox
	
	if hitbox:
		hitbox.damage_amount = config.get("base_dmg", 100)
		hitbox.max_hits = config.get("max_hits", 1)
		hitbox.hit_sfx_type = config.get("hit_sfx_type", "")
		
		if "hit_interval" in hitbox: hitbox.hit_interval = config.get("interval", 0.0)
		if "knockback_force" in hitbox: hitbox.knockback_force = config.get("knockback", Vector2.ZERO)
		
		if "attack_type" in hitbox: hitbox.attack_type = config.get("type", Damage.Type.LIGHT)
		if "sticky_multi_hit" in hitbox: hitbox.sticky_multi_hit = config.get("sticky", false)
		
		if "pull_towards_owner" in hitbox: hitbox.pull_towards_owner = config.get("pull", false)
		
		if "shake_intensity" in hitbox: hitbox.shake_intensity = config.get("shake", 2.5) 
		if "shake_on_hit_only" in hitbox: hitbox.shake_on_hit_only = config.get("shake_on_hit_only", true)
		
		# ==========================================
		# 🌟 核心解耦 1：由長槍自己記住這招的獎勵
		# ==========================================
		_current_energy_reward = float(config.get("energy", 0))
		_current_switch_reward = float(config.get("switch", 0))
		_current_pozhen_reward = int(config.get("pozhen", 0))
		_multi_hit_energy = config.get("multi_hit_energy", false)
		_has_granted_resources_this_step = false
		
		# --- 長槍專屬大地色系火花 (RAW HDR) ---
		hitbox.spark_type = 0
		hitbox.spark_scale = 0.3
		hitbox.spark_color = Color(1.0, 0.4, 0.2, 1.0)
		hitbox.aura_color = Color(1.0, 0.6, 0.2, 1.0)
		
		hitbox.hit_targets.clear()
		
		# ==========================================
		# 🌟 核心解耦 2：切斷舊信號，接管新信號
		# ==========================================
		if current_active_hitbox and current_active_hitbox.hit.is_connected(_on_hitbox_hit):
			current_active_hitbox.hit.disconnect(_on_hitbox_hit)
			
		current_active_hitbox = hitbox 
		
		if not current_active_hitbox.hit.is_connected(_on_hitbox_hit):
			current_active_hitbox.hit.connect(_on_hitbox_hit)
			
		if "energy_reward" in hitbox: hitbox.energy_reward = float(config.get("energy", 0))
		if "switch_reward" in hitbox: hitbox.switch_reward = float(config.get("switch", 0))
		
		# 將破陣值獎勵灌注給 Hitbox
		if "pozhen_reward" in hitbox: hitbox.pozhen_reward = int(config.get("pozhen", 0))
		
		# --- 長槍專屬大地色系火花 (RAW HDR) ---
		hitbox.spark_type = 0
		hitbox.spark_scale = 0.3
		hitbox.spark_color = Color(1.0, 0.4, 0.2, 1.0)
		hitbox.aura_color = Color(1.0, 0.6, 0.2, 1.0)
		
		hitbox.hit_targets.clear()
		current_active_hitbox = hitbox 
	
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])
	
# ==========================================
# 🎯 命中回饋處理 (由 Hitbox 信號觸發)
# ==========================================
func _on_hitbox_hit(hurtbox: Node) -> void:
	if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: 
		return

	if _multi_hit_energy or not _has_granted_resources_this_step:
		if _current_pozhen_reward > 0:
			gain_pozhen(_current_pozhen_reward)
			
		if _current_energy_reward > 0 or _current_switch_reward > 0:
			if player.has_method("add_weapon_resource"):
				player.add_weapon_resource(WEAPON_ID, _current_energy_reward, _current_switch_reward)
				
		_has_granted_resources_this_step = true
		

# 🌟 空戰專用發招與物理推進
func _play_air_step(step: int) -> void:
	var config: Dictionary = AIR_ATTACK_CONFIG[step]
	_play_attack(config) # 直接復用你寫得很棒的 _play_attack！
	player.velocity.y = air_thrust_force # 給予微小的浮空停滯力

# 🌟 射線測量對地距離
func _get_ground_distance() -> float:
	var space_state = player.get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(player.global_position, player.global_position + Vector2(0, 1000))
	query.collision_mask = 1 
	var result = space_state.intersect_ray(query)
	if result: return player.global_position.distance_to(result.position)
	return 1000.0
	
# ==========================================
# 🛡️ Hitbox 開關實作
# ==========================================
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

# ==========================================
# 🎬 招式結束與打斷 (Cut & Cancel)
# ==========================================
func is_attack_finished() -> bool:
	if not is_attacking: 
		return true
	
	if not player.animation_player.is_playing():
		# ==========================================
		# 🌟 大招接力：80 播完立刻切換 81 發射氣刃！
		# ==========================================
		if combo_step == 80:
			combo_step = 81
			
			# 🌟 核心改動：一進入 81，立刻打碎時停並恢復鏡頭！
			if player.has_method("clear_time_stop"): 
				player.clear_time_stop()
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.15)
			_ult_zoom_phase = 0 
			is_time_stop_triggered = false
			
			# 🌟 補上大招後搖的安全無敵時間！
			player.invincible_time_left = 1.0 
			
			_play_attack(SKILL_CONFIG[81])
			return false
		
		# --- 變奏無縫銜接 (長槍版) ---
		if combo_step == 90:
			combo_step = 30 # 長槍的變奏是接強化普攻！
			_play_attack(SKILL_CONFIG[combo_step])
			print("🌪️ 變奏前搖結束，長槍化作狂風連刺突進！")
			
			_ult_zoom_phase = 0
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.2)
			
			# 🌟 恢復正常速度並解除時停
			player.animation_player.speed_scale = 1.0 
			if player.has_method("clear_time_stop"):
				player.clear_time_stop()
				
			return false
		
		# ==========================================
		# 🌟 破陣值無縫預輸入 (Hold-to-Chain)
		# ==========================================
		if Input.is_action_pressed("attack"):
			if combo_step in [1, 2, 3, 4,20,21,22, 61, 62]:
				
				# 確保玩家「真的有按住一小段時間 (0.2秒)」，才允許在動畫結束時派生
				if current_pozhen >= 40 and light_hold_timer >= 0.2:
					
					var input_dir = Input.get_axis("move_left", "move_right")
					if input_dir != 0:
						player.direction = 1 if input_dir > 0 else -1
						
					current_pozhen -= 40
					combo_step = 30 
					light_hold_timer = 0.0
					
					# 🌟 核心防護：如果是在空中無縫接強普，立刻沒收空戰特權！
					if not player.is_on_floor():
						air_attack_locked = true
						
					_play_attack(SKILL_CONFIG[30])
					print("🔥 動畫結束無縫銜接！轉向並發動強化普攻！")
					return false # 告訴狀態機我還沒打完！
				
		# --- 真的打完要收招了 ---
		player.is_input_locked = false 
		if combo_step in [61, 62] or (combo_step == 30 and not player.is_on_floor()): 
			air_attack_locked = true
		
		# 🌟 確保 81 收招時，把運鏡歸零
		if combo_step == 81 or _ult_zoom_phase > 0:
			_ult_zoom_phase = 0
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.4)
			if player.has_method("clear_time_stop"): player.clear_time_stop()
			
		step_cooldown = 0.0
		last_attack_time = Time.get_ticks_msec() / 1000.0 
		
		_is_hitbox_locked = true 
		disable_hitbox()
		
		if not requires_sheath() and player.get("scabbard"):
			player.scabbard.fade_in()
		return true
		
	return false

func cancel_attack() -> void:
	if not player.is_on_floor() and combo_step in [30, 61, 62]:
		air_attack_locked = true
	player.is_input_locked = false
	is_attacking = false
	combo_step = 0
	step_cooldown = 0.0
	is_launch_triggered = false
	_is_hitbox_locked = true 
	disable_hitbox()
	
	is_wave_fired = false 
	_ult_zoom_phase = 0 # 🌟 重置運鏡
	
	if is_time_stop_triggered:
		is_time_stop_triggered = false
		if player.has_method("clear_time_stop"): player.clear_time_stop() 
	
	if player.get("scabbard"):
		player.scabbard.fade_in()
		
	_apply_charge_zoom(ZOOM_LEVELS[0])

# ==========================================
# 🛠️ 鏡頭特寫與氣刃生成
# ==========================================
func _apply_charge_zoom(target_zoom: Vector2, duration: float = 0.2) -> void:
	# 殘影不准控制鏡頭！
	if player.name.begins_with("Phantom"): return
	
	var camera = get_viewport().get_camera_2d()
	if camera:
		if _camera_tween and _camera_tween.is_valid(): _camera_tween.kill()
		_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
		var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
		_camera_tween.set_speed_scale(speed_mult)
		
		# ==========================================
		# 🌟 核心修復：對接 CombatManager 仲裁系統
		# ==========================================
		if target_zoom == ZOOM_LEVELS[0]:
			# 如果目標是 ZOOM_LEVELS[0] (代表要收招還原視野)
			# 我們不盲目回到 1.0，而是取用 CombatManager 記住的地圖/BOSS 基準視野！
			var final_zoom = CombatManager.base_zoom if CombatManager.get("base_zoom") != null else Vector2(1.0, 1.0)
			
			_camera_tween.tween_property(camera, "zoom", final_zoom, duration)
			
			# 收招還原完成後，把相機控制權還給世界
			_camera_tween.tween_callback(func():
				if CombatManager.get("is_close_up_active") != null:
					CombatManager.is_close_up_active = false
			)
		else:
			# 如果是放大特寫，告訴 CombatManager「我要暫時鎖死相機」
			if CombatManager.get("is_close_up_active") != null:
				CombatManager.is_close_up_active = true
				
			_camera_tween.tween_property(camera, "zoom", target_zoom, duration)

func spawn_spear_wave(wave_type: String) -> void:
	if not SPEAR_WAVE_SCENE: return
	var wave = SPEAR_WAVE_SCENE.instantiate()
	get_tree().current_scene.add_child(wave)
	
	wave.global_position = player.global_position + Vector2(30 * player.direction, -20)
	wave.direction = player.direction
	
	await get_tree().process_frame 
	if not is_instance_valid(wave) or not wave.hitbox: return
	
	match wave_type:
		"ult_wave":
			# 🌟 長槍大招氣刃專屬設定 (威力更大、速度更快、體積更巨)
			wave.speed = 800.0
			wave.max_distance = 800.0
			wave.scale = Vector2(3.0 * player.direction, 3.0) # 放得比太刀更大！
			
			wave.hitbox.damage_amount = 800 # 基礎傷害
			wave.hitbox.absolute_knockback = Vector2(800.0 * player.direction, 0.0)
			wave.hitbox.knockback_force = Vector2(0.0, -500.0)
			wave.hitbox.attack_type = Damage.Type.HEAVY
			
			wave.hitbox.spark_type = 0
			wave.hitbox.spark_scale = 1.0
			wave.hitbox.spark_color = Color(1.0, 0.8, 0.2, 1.0) # 長槍專屬金色/橘色火花
			wave.hitbox.aura_color = Color(1.0, 0.5, 0.0, 1.0)
			wave.hitbox.hit_sfx_type = "hit_4"
# ==========================================
# 🌪️ 長槍戰技：迴旋投射物發射
# ==========================================
func spawn_boomerang() -> void:
	if not BOOMERANG_SCENE: return
	var boomerang = BOOMERANG_SCENE.instantiate() as SpearBoomerang
	get_tree().current_scene.add_child(boomerang)
	
	boomerang.global_position = player.global_position + Vector2(30 * player.direction, -30)
	boomerang.direction = player.direction
	boomerang.thrower = player
	
	await get_tree().process_frame 
	if not is_instance_valid(boomerang) or not boomerang.hitbox: return
	
	boomerang.hitbox.damage_amount = 120
	boomerang.hitbox.attack_type = Damage.Type.HEAVY
	boomerang.hitbox.sticky_multi_hit = false
	boomerang.hitbox.max_hits = 1
	boomerang.hitbox.hit_interval = 0.15 
	boomerang.hitbox.knockback_force = Vector2(20.0, -300.0) 
	boomerang.hitbox.shake_intensity = 1.5
	boomerang.hitbox.shake_on_hit_only = true
	boomerang.hitbox.hit_sfx_type = "hit"
	
	var w_energy = 2.0
	var w_switch = 3.0
	var w_pozhen = 10
	var b_state = [false] # 利用陣列當作參照，確保 Lambda 內的布林值能正確被修改
	
	boomerang.hitbox.hit.connect(func(hurtbox: Node):
		if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: return
		
		# 如果迴旋鏢打到敵人，給予對應的破陣與能量
		if not b_state[0]:
			gain_pozhen(w_pozhen)
			if player.has_method("add_weapon_resource"):
				player.add_weapon_resource(WEAPON_ID, w_energy, w_switch)
			b_state[0] = true
	)
	
	boomerang.hitbox.spark_type = 0
	boomerang.hitbox.spark_scale = 0.4  
	boomerang.hitbox.spark_color = Color(1.2, 1.5, 0.5, 1.0)
	boomerang.hitbox.aura_color = Color(0.8, 0.5, 0.2, 1.0)
	
# ==========================================
# 🛡️ 狀態機防護名單 (The Bouncer's List)
# ==========================================
func can_air_light() -> bool: 
	# 強化大招特權放行 (滿氣瞬發空戰)
	if current_pozhen >= 40: return true 
	
	# 🌟 一般空戰攔截：如果已經打過一套被鎖死，或者離地太近，就攔截大腦指令！
	if air_attack_locked or _get_ground_distance() < min_air_attack_height: 
		return false
		
	return true
	
func can_air_skill() -> bool: return false

# 仿造太刀的智慧方向防護網
func can_use_heavy() -> bool:
	if not player.is_on_floor(): 
		return false
		
	# 檢查向下戰技 (Skill 3)
	if Input.is_action_pressed("move_down"):
		if skill_3_timer > 0:
			print("⏳ [防護網攔截] 聚怪戰技 (Skill 3) 冷卻中！")
			return false
			
	# 檢查向上戰技 (Skill 2)
	elif Input.is_action_pressed("move_up"):
		if skill_2_timer > 0:
			print("⏳ [防護網攔截] 向上戰技 (Skill 2) 冷卻中！")
			return false
			
	# 檢查中立戰技 (Skill 1)
	else:
		if skill_1_timer > 0:
			print("⏳ [防護網攔截] 迴旋鏢戰技 (Skill 1) 冷卻中！")
			return false
			
	return true
