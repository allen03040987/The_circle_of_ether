class_name Sickle
extends Weapon
## 武器腳本：鎖鏈鐮刀 (Chain Sickle) 
## 負責處理鐮刀的連段派生 (無雙 C 技系統)、共鳴資源 (鏈心值)，與專屬獨立 VFX 系統。

# ==========================================
# 🎛️ 1. 武器核心參數與資源
# ==========================================
@export_group("武器核心參數")
@export var combo_timeout: float = 0.3      
@export var no_sheath_steps: Array[int] = [4, 11, 12, 20, 21, 22, 41, 80, 81] 
@export var ult_energy_cost: float = 100.0  

const WEAPON_ID: String = "sickle"          
# 🌟 鎖鏈鐮刀專屬獨立特效場景 (當作備用工具保留)
const SICKLE_VFX_SCENE = preload("res://player/Sickle/SickleVFX.tscn") 
# 🌟 修改這行！把它指向你真正會飛的鐮刀投射物場景
const SICKLE_HOOK_SCENE = preload("res://player/Sickle/SickleHook.tscn")


const HOOK_OFFSET = Vector2(10.0, -30.0)

# 🌟 新增：根據玩家當前面向，動態計算鏡像翻轉後的胸口發射點
func _get_player_hook_offset() -> Vector2:
	return Vector2(HOOK_OFFSET.x * player.direction, HOOK_OFFSET.y)
	
const ZOOM_LEVELS = { 0: Vector2(1.0, 1.0), 1: Vector2(1.01, 1.01), 2: Vector2(1.02, 1.02), 3: Vector2(1.03, 1.03) }

# ==========================================
# 🌀 2. 共鳴迴路 (Resonance Circuit) 變數
# ==========================================
var current_chain_link: int = 0             
const MAX_CHAIN_LINK: int = 100                     
var is_enhanced_ready: bool = false         

# ==========================================
# 📖 3. 招式數據庫 (Data-Driven Combat Config)
# ==========================================
const LIGHT_ATTACK_CONFIG = {
	1: {"anim": "sickle/attack_1", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(100.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 200, "switch": 500, "link_reward": 5, "action_type": Weapon.ActionType.NORMAL},
	2: {"anim": "sickle/attack_2", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(150.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5, "link_reward": 5, "action_type": Weapon.ActionType.NORMAL},
	3: {"anim": "sickle/attack_3", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(200.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5,"link_reward": 5, "action_type": Weapon.ActionType.NORMAL},
	4: {"anim": "sickle/attack_4", "hitbox_name": "Hitbox", "max_hits": 2, "interval": 0.1, "knockback": Vector2(200.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5,"link_reward": 5, "action_type": Weapon.ActionType.NORMAL},
}

const SKILL_CONFIG = {
	# 預留 C2：戰技上
	11: { "anim": "sickle/attack_c1", "hitbox_name": "C1", "type": Damage.Type.HEAVY, "knockback": Vector2(0.0, -400.0), "shake": 30.0, "base_dmg": 200, "hit_sfx_type": "hit", "energy": 10, "switch": 15, "link_reward": 5, "vfx_anim": "c0" },
	
	# 預留 C3：戰技中立
	41: { "anim": "katana/attack_c2", "hitbox_name": "C2", "base_dmg": 250, "energy": 10, "switch": 15, "link_reward": 5 },
	
	# 預留 C4：戰技下
	20: { "anim": "katana/attack_c3", "hitbox_name": "C3", "interval": 0.0, "type": Damage.Type.HEAVY, "knockback": Vector2(0.0, -500.0), "base_dmg": 300,"hit_sfx_type": "hit", "energy": 2, "switch": 4, "link_reward": 2,},
	
	# 強化戰技 (滿鏈心值)
	42: { "anim": "sickle/attack_enhanced", "hitbox_name": "attack_enhanced", "base_dmg": 400, "energy": 25, "switch": 30 },
	
	# 大招與變奏 (保留基礎結構)
	80: { "anim": "sickle/attack_ult", "hitbox_name": "UltHitbox", "type": Damage.Type.HEAVY, "base_dmg": 150, "energy": 0, "switch": 0, "max_hits": 20, "interval": 0.1, "sticky": true },
	81: { "anim": "sickle/attack_ult_end", "hitbox_name": "None", "base_dmg": 0, "energy": 0, "switch": 0 },
	90: { "anim": "sickle/attack_c0_charge_start", "hitbox_name": "None", "base_dmg": 0, "energy": 0, "switch": 0 },
}

const AIR_ATTACK_CONFIG = {
	61: { "anim": "sickle/air_attack_1", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "type": Damage.Type.LIGHT, "knockback": Vector2(20.0, -200.0), "base_dmg": 300,"hit_sfx_type": "hit", "energy": 2, "switch": 4, "link_reward": 2, "action_type": Weapon.ActionType.NORMAL},
	62: { "anim": "sickle/air_attack_2_start", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "type": Damage.Type.HEAVY, "knockback": Vector2(20.0, -300.0), "base_dmg": 300,"hit_sfx_type": "hit", "energy": 2, "switch": 4, "link_reward": 2, "action_type": Weapon.ActionType.NORMAL},
}

# ==========================================
# 🚀 4. 物理運算與手感參數
# ==========================================        
@export_group("戰技上 (飛索/挑飛) 設定")
@export var launch_start_time: float = 0.2      
@export var launch_duration: float = 0.06       
@export var vertical_launch_speed: float = -650.0 

@export_group("戰技中立 設定")
@export var skill_neutral_friction_rate: float = 0.2 

@export_group("空戰設定 (Air Combat)")
@export var min_air_attack_height: float = 40.0 
@export var air_thrust_force: float = -150.0    
@export var air_skill_gravity_rate: float = 0.25 

# --- 內部狀態 ---
var current_active_hitbox: Hitbox = null

var _current_energy_reward: float = 0.0
var _current_switch_reward: float = 0.0
var _current_link_reward: int = 0
var _multi_hit_energy: bool = false
var _has_granted_resources_this_step: bool = false

var combo_step: int = 0
var last_attack_time: float = 0.0
var is_attacking: bool = false
var step_cooldown: float = 0.0                  

var is_launch_triggered: bool = false
var launch_timer: float = 0.0

var is_wave_fired: bool = false                 
var air_attack_locked: bool = false

var has_used_air_hook: bool = false             

var is_time_stop_triggered: bool = false 
var _tsubame_zoom_phase: int = 0 
var _camera_tween: Tween 

var _is_hitbox_locked: bool = false

var is_vfx_fired: bool = false 
var _phantom_flags_synced: bool = false

var is_hooking: bool = false
var hook_target_node: Node2D = null

var pull_delay_timer: float = 0.0  # 🌟 新增：飛索拉拽前的停頓計時器
var active_hook: Node2D = null
var hook_pull_dir: Vector2 = Vector2.ZERO
# ==========================================
# 🌟 多段戰技連段系統 (Combo Skill Cooldown)
# ==========================================
var skill_2_combo_timer: float = 0.0
var skill_2_current_step: int = 11  

var skill_3_combo_timer: float = 0.0
var skill_3_current_step: int = 20  

# ==========================================
# 🎨 動態圖標
# ==========================================
@export_group("動態圖標")
@export var skill_1_enhanced_icon: Texture2D
@export var skill_2_step2_icon: Texture2D
@export var skill_3_step2_icon: Texture2D
@export var skill_3_step3_icon: Texture2D

# ==========================================
# 🌀 5. 共鳴迴路邏輯 (Resonance Circuit)
# ==========================================
func gain_chain_link(amount: int) -> void:
	if amount <= 0: return
	if try_forward_resource("gain_chain_link", amount): return
		
	current_chain_link = mini(current_chain_link + amount, MAX_CHAIN_LINK)
	print("🟢 命中！獲得鏈心值: ", amount, " | 目前鏈心: ", current_chain_link, "/", MAX_CHAIN_LINK)
	
	if current_chain_link >= 50 and not is_enhanced_ready:
		is_enhanced_ready = true

func consume_chain_link(amount: int) -> void:
	current_chain_link = maxi(current_chain_link - amount, 0)
	print("消耗鏈心值，目前剩餘: ", current_chain_link, "/", MAX_CHAIN_LINK)

# ==========================================
# 🎬 實作 Weapon.gd 合約接口
# ==========================================
func start_light_attack() -> void:
	if step_cooldown > 0: return 
	step_cooldown = 0.15
	
	is_vfx_fired = false
	_phantom_flags_synced = false
	is_wave_fired = false # 🌟 核心修復：每次按普攻都要重置震動與波浪特效開關！

	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time > combo_timeout:
			combo_step = 0

	if not player.is_on_floor():
		if air_attack_locked or _get_ground_distance() < min_air_attack_height:
			return
			
		# 🌟 核心升級：只要這趟升空丟過鐮刀 (61)，下一次按攻擊絕對是下砸 (62)！
		if has_used_air_hook:
			combo_step = 62
			air_attack_locked = true # 下砸完才真正鎖死空攻權限
			
			# 🌟 核心修復：提早派生 62 砸地時，立刻強制清空還插在怪身上的鐮刀！
			is_hooking = false
			hook_target_node = null
			if is_instance_valid(active_hook):
				if active_hook.has_method("fade_and_die"):
					active_hook.fade_and_die()
				else:
					active_hook.queue_free()
				active_hook = null
				
		else:
			combo_step = 61
			has_used_air_hook = true 
			is_hooking = false
			hook_target_node = null
			hook_pull_dir = Vector2.ZERO # 🌟 核心新增：每次新發射時，清空上一次的方向鎖
			
			var launch_dir = Vector2(player.direction, 0.0) 
			# 🌟 恢復機制：優先檢查玩家是否輸入了方向鍵
			var move_dir = Input.get_axis("move_left", "move_right")
			
			if not is_zero_approx(move_dir):
				# ➡️ 玩家按著方向鍵：絕對優先！強制手動平射，不啟動自動索敵
				player.direction = 1 if move_dir > 0 else -1
				launch_dir = Vector2(player.direction, 0.0)
				print("➡️ [鎖鐮] 手動輸入方向！強制朝前方直線發射！")
			else:
				# 🎯 玩家沒按方向鍵（中立狀態）：啟動自動索敵雷達（已過濾殘影）
				var target = _get_auto_target(400.0)
				if target:
					var diff_x = target.global_position.x - player.global_position.x
					if abs(diff_x) > 5.0:
						player.direction = 1 if diff_x > 0 else -1
					
					var true_start = player.global_position + Vector2(0.0, HOOK_OFFSET.y)
					var true_end = target.global_position + Vector2(0.0, HOOK_OFFSET.y)
					
					if true_start.is_equal_approx(true_end):
						launch_dir = Vector2(player.direction, 0.0)
					else:
						launch_dir = true_start.direction_to(true_end)
					print("🎯 [鎖鐮] 自動鎖定並瞄準敵人：", target.name)
				else:
					# ➡️ 沒按鍵也沒敵人：往預設前方平射
					launch_dir = Vector2(player.direction, 0.0)
					print("➡️ [鎖鐮] 無目標且無輸入，朝預設前方發射！")
			
			spawn_sickle_hook(launch_dir)
			
		is_attacking = true
		_play_air_step(combo_step)
		return

	if SKILL_CONFIG.has(combo_step):
		combo_step = 0

	combo_step += 1
	if not LIGHT_ATTACK_CONFIG.has(combo_step):
		combo_step = 1

	is_attacking = true
	_play_light_step(combo_step)

func start_heavy_attack() -> void:
	if step_cooldown > 0:
		is_attacking = false
		return
	step_cooldown = 0.15
	air_attack_locked = false
	
	is_vfx_fired = false
	_phantom_flags_synced = false
	
	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time > combo_timeout: combo_step = 0
			
	is_attacking = true
	is_launch_triggered = false
	is_wave_fired = false
	is_time_stop_triggered = false 

	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	if not player.is_on_floor():
		is_attacking = false 
		return

	match combo_step:
		1:
			combo_step = 11 
			skill_2_timer = skill_2_cd
			_play_skill_step(combo_step)
		2:
			combo_step = 41
			skill_1_timer = skill_1_cd
			_play_skill_step(combo_step)
		3:
			combo_step = 20
			skill_3_timer = skill_3_cd
			_play_skill_step(combo_step)
		0:
			if is_enhanced_ready:
				combo_step = 42 
				is_enhanced_ready = false
				consume_chain_link(50)
				_play_skill_step(combo_step)
			else:
				is_attacking = false
		_:
			is_attacking = false

func start_ultimate() -> void:
	if player.has_method("consume_weapon_energy"):
		player.consume_weapon_energy(WEAPON_ID, ult_energy_cost)
		
	step_cooldown = 0.15
	is_attacking = true
	is_vfx_fired = false
	_phantom_flags_synced = false
	is_time_stop_triggered = false 
	_tsubame_zoom_phase = 0 
	
	ult_timer = ult_cd 
	combo_step = 80
	player.invincible_time_left = 3.0
	
	_play_skill_step(combo_step)
	player.is_input_locked = true

func start_intro_skill() -> void:
	step_cooldown = 0.15
	is_attacking = true
	is_vfx_fired = false
	_phantom_flags_synced = false
	is_time_stop_triggered = false 
	_tsubame_zoom_phase = 0 
	
	if is_instance_valid(player):
		player.invincible_time_left = 1.5
	
	gain_chain_link(50)
	
	combo_step = 90 
	_play_skill_step(combo_step)
	
	player.is_input_locked = true 

func update_timers_only(delta: float) -> void:
	if step_cooldown > 0: step_cooldown -= delta 
	if skill_1_timer > 0: skill_1_timer -= delta
	if skill_2_timer > 0: skill_2_timer -= delta 
	if skill_3_timer > 0: skill_3_timer -= delta 
	if ult_timer > 0: ult_timer -= delta

	if skill_2_combo_timer > 0:
		skill_2_combo_timer -= delta
		if skill_2_combo_timer <= 0:
			skill_2_timer = skill_2_cd     
			skill_2_current_step = 11      

	if skill_3_combo_timer > 0:
		skill_3_combo_timer -= delta
		if skill_3_combo_timer <= 0:
			skill_3_timer = skill_3_cd     
			skill_3_current_step = 20      
			
	# 🌟 核心升級：落地 (is_on_floor) 或摸牆 (is_on_wall) 時，皆能解鎖空攻權限與重置飛索！
	if player.is_on_floor() or player.is_on_wall():
		air_attack_locked = false 
		has_used_air_hook = false 
		if not is_attacking and combo_step in [61, 62]:
			combo_step = 0

# ==========================================
# 🏃 物理與特效場控核心
# ==========================================
func get_current_velocity(delta: float) -> Vector2:
	if not is_attacking:
		return player.velocity

	if player.is_on_floor() or player.is_on_wall(): air_attack_locked = false

	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var anim_time = player.animation_player.current_animation_position

	# ==========================================
	# 🌟 殘影接管的旗標同步防呆 (預留區塊)
	# ==========================================
	if not (player is Player) and not _phantom_flags_synced:
		_phantom_flags_synced = true
		if combo_step == 22 and anim_time >= 0.32:
			is_wave_fired = true

	# ==========================================
	# 🚨 終極防爆衝基底：統一套用 M平方定律
	# ==========================================
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# ----------------------------------------
	# 常規普攻 (1~4)
	# ----------------------------------------
	if combo_step in [1, 2, 3, 4]:
		new_x = move_toward(new_x, 0.0, base_friction)

	# ----------------------------------------
	# C2 戰技上 (11) - 挑飛與 VFX
	# ----------------------------------------
	elif combo_step == 11:
		# 1. 觸發特效 (假設在 0.1 秒處觸發)
		if anim_time >= 0.2 and not is_vfx_fired:
			is_vfx_fired = true
			_spawn_weapon_vfx(SKILL_CONFIG[combo_step])

		# 2. 挑飛物理邏輯
		if anim_time >= launch_start_time and not is_launch_triggered:
			is_launch_triggered = true
			launch_timer = launch_duration
			
		if is_launch_triggered:
			if launch_timer > 0: 
				launch_timer -= delta
				new_y = vertical_launch_speed
				new_x = 0.0 
			else: 
				new_x = 0.0
				if new_y < 0:
					# 到達最高點前減速，給予接招時間
					new_y = move_toward(new_y, 0.0, player.default_gravity * 2.0 * delta)
				else:
					new_y += player.default_gravity * delta
		else:
			# 起飛前的前搖，使用 M 平方基底摩擦力煞車！
			new_x = move_toward(new_x, 0.0, base_friction)

	# ----------------------------------------
	# ⛓️ 其他預留 C 技區塊 (20, 41, 42)
	# ----------------------------------------
	elif combo_step in [20, 41, 42]:
		new_x = move_toward(new_x, 0.0, base_friction)
		
			
	# ----------------------------------------
	# 大招 (80)
	# ----------------------------------------
	elif combo_step == 80: 
		new_x = move_toward(new_x, 0.0, base_friction * 5.0)
		new_y = 0.0 
		
		if anim_time >= 0.05 and not is_time_stop_triggered:
			is_time_stop_triggered = true 
			if player.has_method("trigger_time_stop"):
				player.trigger_time_stop(3.0, 0.001) 
			player.animation_player.speed_scale = 1.0 / 0.001 
			player.invincible_time_left = 3.0
			
		if anim_time >= 0.05 and _tsubame_zoom_phase == 0:
			_tsubame_zoom_phase = 1
			_apply_charge_zoom(Vector2(1.2, 1.2), 0.3) 
			
		if anim_time >= 0.70 and _tsubame_zoom_phase == 1:
			_tsubame_zoom_phase = 2
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(100.0, 0.07) 
			_apply_charge_zoom(Vector2(0.85, 0.85), 0.1) 
		
		if anim_time >= 0.82 and _tsubame_zoom_phase == 2:
			_tsubame_zoom_phase = 3
			_apply_charge_zoom(Vector2(0.65, 0.65), 1.8) 
			
		if anim_time >= 2.80 and _tsubame_zoom_phase == 3:
			_tsubame_zoom_phase = 4
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(180.0, 0.15) 
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.2)

	# ----------------------------------------
	# 大招結尾 (81)
	# ----------------------------------------
	elif combo_step == 81:
		new_x = move_toward(new_x, 0.0, base_friction)

	# ----------------------------------------
	# 變奏 (90)
	# ----------------------------------------
	elif combo_step == 90:
		new_x = move_toward(new_x, 0.0, base_friction * 2.0)
		
		if anim_time >= 0.02 and not is_time_stop_triggered:
			is_time_stop_triggered = true
			if player.has_method("trigger_time_stop"): player.trigger_time_stop(0.8, 0.05)
			player.animation_player.speed_scale = 4.0 
			player.invincible_time_left = 1.5
			AudioManager.play_action_sfx("ult", -2.0)
			player.spawn_anim_vfx("Aggregation ring", 0, -20, Vector2(2.5, 2.5), 0, Color(0.7, 1.5, 0.5, 1.0), Color.WHITE, false, 2, 1.0)
			
		if anim_time >= 0.02 and _tsubame_zoom_phase == 0:
			_tsubame_zoom_phase = 1
			_apply_charge_zoom(Vector2(1.15, 1.15), 1.2)
			
		if anim_time >= 0.18 and _tsubame_zoom_phase == 1:
			_tsubame_zoom_phase = 2

	# ----------------------------------------
	# 空戰 61: 飛索突進 (丟鉤 -> 連續飛行 -> 抵達彈起)
	# ----------------------------------------
	elif combo_step == 61:
		if is_hooking and is_instance_valid(hook_target_node):
			
			if pull_delay_timer > 0.0:
				pull_delay_timer -= delta
				new_x = 0.0
				new_y = 0.0
			else:
				# 停頓結束，正式收線飛過去！
				var target_pos = hook_target_node.global_position
				if not hook_target_node is SickleHook:
					# 🌟 修改：怪物端保持置中，不吃 X 軸偏移
					target_pos += Vector2(0.0, HOOK_OFFSET.y)
				
				# 🌟 修改：使用統一的動態鏡像胸口座標來計算剩餘距離
				var current_chest_pos = player.global_position + _get_player_hook_offset()
				
				var is_wall = (hook_target_node is SickleHook)
				# 🌟 核心修復：牆壁的停止距離必須壓縮到極小 (10.0)！
				# 強迫玩家繼續飛，直到肉體真正撞上牆壁觸發 player.is_on_wall() 為止
				var stop_distance = 15.0 if is_wall else 60.0
				
				# 🌟 核心修復 2：先判斷到了沒！
				var has_arrived = false
				if current_chest_pos.distance_to(target_pos) < stop_distance:
					has_arrived = true
				# 🚨 終極物理防線：無論目標是怪還是牆，只要肉體撞到「任何地形」(地板/牆壁/天花板)
				# 就代表物理軌跡已被強制切斷，必須立刻判定抵達終點！
				elif player.is_on_wall() or player.is_on_floor() or player.is_on_ceiling():
					has_arrived = true
				
				if has_arrived:
					# ========================================
					# ✅ 已經抵達終點 (或貼臉發射) 的結算
					# ========================================
					is_hooking = false
					hook_target_node = null 
					hook_pull_dir = Vector2.ZERO
					
					# 讓留在目標身上的鐮刀漸變消失
					if is_instance_valid(active_hook) and active_hook.has_method("fade_and_die"):
						active_hook.fade_and_die()
						active_hook = null
					
					if is_wall:
						# 🧱 撞到牆：大道至簡！瞬間煞車並收招，把物理控制權還給基礎狀態機！
						new_x = 0.0
						new_y = 0.0
						cancel_attack() 
						return Vector2(new_x, new_y)
					else:
						# 👾 撞到怪：保留些微往前慣性，並賦予向上彈跳推力
						new_x = move_toward(new_x, 0.0, base_friction * 2.0)
						new_y = -250.0 * speed_mult 
						# 離開飛行動畫，播一個短暫的滯空動作
						player.play_safe_anim("sickle/air_fly_end")
				
				else:
					# ========================================
					# ✈️ 還沒抵達，繼續賦予飛行速度與動畫！
					# ========================================
					# 🌟 完美修復 4：捨棄靜態死板的角度，改為「每一幀動態追蹤」！
					# 確保不論玩家掉落多少、或是怪物怎麼移動，永遠朝著目標精準飛過去！
					var true_start = player.global_position + Vector2(0.0, HOOK_OFFSET.y)
					var dir = true_start.direction_to(target_pos)
					
					# 近距離防抖 (防止重疊時小數點浮動導致上下亂竄)
					if true_start.distance_to(target_pos) < 30.0:
						dir = Vector2(player.direction, 0.0)
					
					if player.animation_player.current_animation != "sickle/air_fly":
						player.play_safe_anim("sickle/air_fly")
					
					var pull_speed = 1100.0 
					new_x = dir.x * pull_speed * speed_mult
					new_y = dir.y * pull_speed * speed_mult
		else:
			# 未命中、或已經撞完彈起時的物理處理
			new_x = move_toward(new_x, 0.0, base_friction)
			
			# 🌟 核心修復 B：只在「剛丟出鐮刀 (air_attack_1)」的前 0.15 秒沒收 Y 軸動能！
			# 絕對不可以影響「撞擊彈起後」的推力！
			if player.animation_player.current_animation == "sickle/air_attack_1" and anim_time < 0.15:
				new_y = 0.0
			else:
				new_y += (player.default_gravity * air_skill_gravity_rate) * delta

		if anim_time >= 0.1 and not is_vfx_fired:
			is_vfx_fired = true
			# 🌟 核心修復：傳送門打斷可能導致 combo_step 突變為 0，必須先檢查字典裡有沒有這個招式！
			if AIR_ATTACK_CONFIG.has(combo_step):
				_spawn_weapon_vfx(AIR_ATTACK_CONFIG[combo_step])
			
	# ----------------------------------------
	# 空戰 62: 下墜砸地 (分拆為：起手 -> 下墜 -> 落地)
	# ----------------------------------------
	elif combo_step == 62:
		var current_anim = player.animation_player.current_animation
		var start_anim = AIR_ATTACK_CONFIG[62]["anim"] # 抓取配置裡的起手動畫
		
		# 🌟 核心修復：利用 is_wave_fired 當作「絕對狀態鎖」！
		# 一旦落地 (is_wave_fired = true)，就不管 is_on_floor 怎麼閃爍，死死扣在落地階段！
		if not is_wave_fired and not player.is_on_floor():
			new_x = move_toward(new_x, 0.0, base_friction * 0.5) # 允許微幅水平位移
			
			# ✈️ 階段 1：起手滯空前搖 (前 0.4 秒)
			if current_anim == start_anim and anim_time < 0.4:
				new_y = air_thrust_force * 0.5 # 砸地前搖稍微抬升
			else:
				# ✈️ 階段 2：無限下墜途中
				new_y = 1200.0 * speed_mult
				# 如果還沒切換到下墜動畫，或動畫被 Godot 清空，就確保維持下墜姿勢
				if current_anim != "sickle/air_attack_2_fall":
					player.play_safe_anim("sickle/air_attack_2_fall")
					
		else:
			# 💥 階段 3：觸地瞬間與落地硬直 (已觸發過落地，或正在落地)
			if not is_wave_fired:
				is_wave_fired = true
				player.play_safe_anim("sickle/air_attack_2_land")
				
				# 觸地瞬間震動螢幕
				if player is Player and CombatManager.has_method("apply_camera_shake"):
					CombatManager.apply_camera_shake(30.0, 0.15)
					
			# 🌟 物理修復：給予一個微小的向下重力 (10.0) 壓住地板
			# 防止 Godot 在速度為 0 時誤判「離開地面」導致狀態機崩潰！
			new_x = 0.0
			new_y = 10.0 
			
			# 觸地特效 (在落地動畫播到 0.1 秒時爆發)
			if anim_time >= 0.1 and not is_vfx_fired:
				is_vfx_fired = true
				if AIR_ATTACK_CONFIG.has(combo_step):
					_spawn_weapon_vfx(AIR_ATTACK_CONFIG[combo_step])

	else:
		new_x = move_toward(new_x, 0.0, base_friction)

	return Vector2(new_x, new_y)

# ==========================================
# 🧹 生命週期管理 (自動清理與絕對解耦)
# ==========================================
func _exit_tree() -> void:
	# 當這把武器被銷毀 (例如殘影壽命結束、或者玩家切換場景) 時
	# 自己負責把自己產生的外部投射物清乾淨，絕不依賴父節點的呼叫！
	if is_instance_valid(active_hook):
		if active_hook.has_method("fade_and_die"):
			active_hook.fade_and_die()
		else:
			active_hook.queue_free()
		active_hook = null

func is_handling_gravity() -> bool:
	if combo_step == 11 and is_launch_triggered: return true
	# 🌟 核心修復：必須把 61 (飛索) 和 62 (下砸) 加進來，這兩招由武器完全接管 Y 軸！
	if not player.is_on_floor() and combo_step in [20, 21, 22, 42, 61, 62]: return true
	if combo_step == 80: return true
	return false

# ==========================================
# 🌟 武器專屬 VFX 獨立生成系統 (供手動呼叫)
# ==========================================
func _spawn_weapon_vfx(config: Dictionary) -> void:
	if not SICKLE_VFX_SCENE: return
	
	var vfx_anim_name = config.get("vfx_anim", "")
	if vfx_anim_name == "": return
	
	var vfx = SICKLE_VFX_SCENE.instantiate()
	
	vfx.global_position = player.global_position + Vector2(10 * player.direction, -25)
	vfx.scale.x = player.direction
	vfx.z_index = player.z_index + 1
	
	get_tree().current_scene.add_child(vfx) 
	
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	
	if vfx.has_method("play_and_free"):
		vfx.play_and_free(vfx_anim_name, speed_mult)
	else:
		printerr("⚠️ [Sickle] SICKLE_VFX_SCENE 缺少 play_and_free() 函數！")

# ==========================================
# 🎬 招式結束判定 (Cut!)
# ==========================================
func is_attack_finished() -> bool:
	if not is_attacking: 
		return true
	
	if not player.animation_player.is_playing():
		if combo_step == 80:
			combo_step = 81
			_play_skill_step(81) 
			player.invincible_time_left = 0.5 
			return false
		
		if combo_step == 90:
			combo_step = 1
			_play_skill_step(combo_step)
			_tsubame_zoom_phase = 0
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.2)
			player.animation_player.speed_scale = 1.0 
			if player.has_method("clear_time_stop"): player.clear_time_stop()
			return false

		player.is_input_locked = false 
		
		if combo_step == 20 and player is Player:
			if player.invincible_timer.time_left == 0:
				player.invincible_time_left = 0.0
		
		# 🌟 核心修復：如果 61 號出鉤動畫自然播完了，玩家卻還沒貼臉，強制收回/消失鐮刀！
		if combo_step == 61:
			# 🚨 核心攔截：如果此時「還在飛行突進中 (is_hooking)」，絕對不能收招，直接返回 false 繼續飛！
			if is_hooking: 
				return false
				
			# 只有在揮空、沒勾到任何東西且動畫播完時，才走常規收招
			is_hooking = false
			hook_target_node = null
			hook_pull_dir = Vector2.ZERO
			if is_instance_valid(active_hook):
				if active_hook.has_method("fade_and_die"):
					active_hook.fade_and_die()
				else:
					active_hook.queue_free()
				active_hook = null
		
		if combo_step == 62: 
			air_attack_locked = true
			
		last_attack_time = Time.get_ticks_msec() / 1000.0
		is_attacking = false
		is_vfx_fired = false 
		step_cooldown = 0.0
		
		if combo_step in [42, 80] or _tsubame_zoom_phase > 0:
			_tsubame_zoom_phase = 0
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.4)
			if player.has_method("clear_time_stop"): player.clear_time_stop()
				
		_is_hitbox_locked = true 
		disable_hitbox()
		
		var p_scabbard = player.get("scabbard")
		if not requires_sheath() and p_scabbard:
			p_scabbard.fade_in()
			
		return true
	return false

func cancel_attack() -> void:
	if not player.is_on_floor() and combo_step == 62:
		air_attack_locked = true
		
	player.is_input_locked = false 
	_apply_charge_zoom(ZOOM_LEVELS[0])
	is_attacking = false
	combo_step = 0
	step_cooldown = 0.0
	is_launch_triggered = false
	is_wave_fired = false 
	is_vfx_fired = false 
	is_hooking = false
	hook_target_node = null
	
	# 🌟 新增：如果操作被打斷，強制讓還在場上的飛索漸變消失
	if is_instance_valid(active_hook):
		if active_hook.has_method("fade_and_die"):
			active_hook.fade_and_die()
		else:
			active_hook.queue_free()
		active_hook = null
		
	_tsubame_zoom_phase = 0
	
	if is_time_stop_triggered:
		is_time_stop_triggered = false
		if player.has_method("clear_time_stop"): player.clear_time_stop() 
	else:
		is_time_stop_triggered = false 
	
	_is_hitbox_locked = true 
	disable_hitbox()
	
	var p_scabbard = player.get("scabbard")
	if p_scabbard: p_scabbard.fade_in()

# ==========================================
# 👻 殘影系統合約接口 (解耦設計)
# ==========================================
func can_spawn_phantom() -> bool:
	# 飛索突進 (61) 期間，屬於特殊幾何位移，嚴禁生成殘影
	# 直接回傳 false 讓主系統知道這招必須純粹地被打斷
	if combo_step == 61:
		return false
	return true

func get_phantom_lifespan() -> float:
	# 🌟 核心升級：62 是三階段下墜攻擊，可能從很高的地方掉下來！
	# 強烈要求殘影系統給予長達 5.0 秒的保險壽命，確保它能活著砸到地面！
	# (等它順利落地播完 _land 後，自然會提早觸發 animation_finished 優雅死亡)
	if combo_step == 62:
		return 5.0 
		
	# 回傳 -1.0 代表不干涉，讓殘影系統使用預設的短暫壽命
	return -1.0

func should_phantom_keep_alive(anim_name: String) -> bool:
	# 🌟 核心升級：62 號招式是「三階段連鎖狀態機」！
	# 絕對不准在「起手 (_start)」或「下墜 (_fall)」播完時銷毀殘影！
	# 只有當「落地 (_land)」播完時，才允許殘影自然死亡！
	if combo_step == 62:
		var start_anim = AIR_ATTACK_CONFIG[62]["anim"]
		if anim_name == start_anim or anim_name == "sickle/air_attack_2_fall":
			return true
			
	return false
	
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
		AudioManager.play_sfx(config["sfx"], -8.0)
		
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _play_skill_step(step: int) -> void:
	disable_hitbox()
	var config: Dictionary = SKILL_CONFIG[step]
	_apply_hitbox_config(config)
	
	if config.has("sfx") and config["sfx"] != null:
		AudioManager.play_sfx(config["sfx"], -5.0)
		
	if current_active_hitbox:
		if step in [11, 12]: current_active_hitbox.spark_type = 1; current_active_hitbox.spark_scale = 0.8
		elif step == 41: current_active_hitbox.max_hits = 5; current_active_hitbox.hit_interval = 0.1; current_active_hitbox.sticky_multi_hit = true
		elif step == 80: current_active_hitbox.spark_scale = 1.0
	
	if not player.is_on_floor() and step in [20, 21, 22, 42]:
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
		if "link_reward" in hitbox: hitbox.link_reward = int(config.get("link_reward", 0))
		
		hitbox.spark_type = 0; hitbox.spark_scale = 0.3; hitbox.spark_color = Color(0.6, 0.1, 0.2, 1.0); hitbox.aura_color = Color(1, 0.1, 0.4, 1)
		hitbox.hit_targets.clear() 
		
		_current_energy_reward = float(config.get("energy", 0))
		_current_switch_reward = float(config.get("switch", 0))
		_current_link_reward = int(config.get("link_reward", 0))
		_multi_hit_energy = config.get("multi_hit_energy", false)
		_has_granted_resources_this_step = false
		
		if current_active_hitbox and current_active_hitbox.hit.is_connected(_on_hitbox_hit):
			current_active_hitbox.hit.disconnect(_on_hitbox_hit)
			
		current_active_hitbox = hitbox
		
		if not current_active_hitbox.hit.is_connected(_on_hitbox_hit):
			current_active_hitbox.hit.connect(_on_hitbox_hit)

func _on_hitbox_hit(hurtbox: Node) -> void:
	if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: 
		return

	# 🌟 攔截 61 號招式的飛索命中
	if combo_step == 61 and not is_hooking:
		is_hooking = true
		hook_target_node = hurtbox.owner
		if player is Player:
			player.invincible_time_left = 0.5 # 飛索期間給予短暫無敵，防止被斷
		print("🔗 [鎖鐮] 命中目標！啟動飛索突進！")

	if _multi_hit_energy or not _has_granted_resources_this_step:
		if _current_link_reward > 0:
			gain_chain_link(_current_link_reward)
			
		if _current_energy_reward > 0 or _current_switch_reward > 0:
			if player.has_method("add_weapon_resource"):
				player.add_weapon_resource(WEAPON_ID, _current_energy_reward, _current_switch_reward)
				
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
				if CombatManager.get("is_close_up_active") != null:
					CombatManager.is_close_up_active = false
			)
		else:
			if CombatManager.get("is_close_up_active") != null:
				CombatManager.is_close_up_active = true
				
			_camera_tween.tween_property(camera, "zoom", target_zoom, duration)

func can_air_light() -> bool:
	if air_attack_locked or _get_ground_distance() < min_air_attack_height: return false
	return true

func can_use_heavy() -> bool:
	if not player.is_on_floor(): return false
	match combo_step:
		1: 
			if skill_2_timer > 0: return false
			return true
		2: 
			if skill_1_timer > 0: return false
			return true
		3: 
			if skill_3_timer > 0: return false
			return true
		0:
			if is_enhanced_ready: return true
			return false
	return false

func can_use_ultimate() -> bool:
	if ult_timer > 0: return false 
	if not player.is_on_floor(): return false 
	
	if player.has_method("get_weapon_energy"):
		if player.get_weapon_energy(WEAPON_ID) < ult_energy_cost:
			return false 
			
	return true

func get_dynamic_skill_icon(slot: int) -> Texture2D:
	match slot:
		1:
			if is_enhanced_ready and skill_1_enhanced_icon: return skill_1_enhanced_icon
		2:
			if skill_2_current_step == 12 and skill_2_step2_icon: return skill_2_step2_icon
		3:
			if skill_3_current_step == 21 and skill_3_step2_icon: return skill_3_step2_icon
			if skill_3_current_step == 22 and skill_3_step3_icon: return skill_3_step3_icon
			
	return super.get_dynamic_skill_icon(slot)

func export_weapon_data() -> Dictionary:
	return {
		"current_chain_link": current_chain_link,
		"is_enhanced_ready": is_enhanced_ready,
		"skill_1_timer": skill_1_timer if "skill_1_timer" in self else 0.0,
		"skill_2_timer": skill_2_timer if "skill_2_timer" in self else 0.0,
		"skill_3_timer": skill_3_timer if "skill_3_timer" in self else 0.0,
		"ult_timer": ult_timer if "ult_timer" in self else 0.0
	}

func import_weapon_data(data: Dictionary) -> void:
	current_chain_link = data.get("current_chain_link", 0)
	is_enhanced_ready = data.get("is_enhanced_ready", false)
	
	if "skill_1_timer" in self: skill_1_timer = data.get("skill_1_timer", 0.0)
	if "skill_2_timer" in self: skill_2_timer = data.get("skill_2_timer", 0.0)
	if "skill_3_timer" in self: skill_3_timer = data.get("skill_3_timer", 0.0)
	if "ult_timer" in self: ult_timer = data.get("ult_timer", 0.0)

# ==========================================
# ⛓️ 實體投射物：發射鏈鐮飛索
# ==========================================
func spawn_sickle_hook(fly_direction: Vector2) -> void:
	if not SICKLE_HOOK_SCENE: return
	
	var hook = SICKLE_HOOK_SCENE.instantiate()
	# 🌟 修改：玩家生成點改用動態鏡像偏移
	hook.global_position = player.global_position + _get_player_hook_offset() 
	hook.z_index = player.z_index + 1
	
	if "fly_direction" in hook: hook.fly_direction = fly_direction
	if "direction" in hook: hook.direction = player.direction
	if "thrower" in hook: hook.thrower = player
	if "speed" in hook: hook.speed = 1100.0 
	if "max_distance" in hook: hook.max_distance = 300.0
	
	get_tree().current_scene.add_child(hook)
	active_hook = hook # 🌟 將發射的飛索記入口袋
	
	await get_tree().process_frame
	if not is_instance_valid(hook) or not hook.get_node_or_null("Hitbox"): return
	
	var hitbox = hook.get_node("Hitbox") as Hitbox
	hitbox.damage_amount = 120 
	hitbox.attack_type = Damage.Type.LIGHT
	hitbox.hit_targets.clear()
	
	# 🌟 賦予鎖鏈鐮刀專屬火花！(和波浪特效色系統一)
	hitbox.spark_type = 0
	hitbox.spark_scale = 0.4
	hitbox.spark_color = Color(0.6, 0.1, 0.2, 1.0) 
	hitbox.aura_color = Color(1, 0.1, 0.4, 1) 
	
	hitbox.hit.connect(func(hurtbox: Node):
		if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: return
		
		if not is_hooking:
			is_hooking = true
			hook_target_node = hurtbox.owner
			pull_delay_timer = 0.1 
			
			# 🌟 修改：計算拉扯方向時，玩家起點用動態偏移，怪物終點保持 X 置中 (0.0) 避免歪斜
			var start_pos = player.global_position + _get_player_hook_offset()
			var target_pos = hurtbox.owner.global_position + Vector2(0.0, HOOK_OFFSET.y)
			hook_pull_dir = start_pos.direction_to(target_pos)
			
			if player is Player:
				player.invincible_time_left = 0.9 
				
			print("🔗 [物理反饋] 鎖鐮咬住目標！鎖定軌跡向量：", hook_pull_dir)
			if is_instance_valid(hook) and hook.has_method("stick_to_target"):
				hook.stick_to_target(hurtbox.owner)
	)
	
# ==========================================
# 🎯 鎖鏈鐮刀專屬：自動尋敵雷達
# ==========================================
func _get_auto_target(radius: float) -> Node2D:
	var nearest: Node2D = null
	var min_dist: float = radius
	var root = get_tree().current_scene
	
	# 抓取場景內所有包含 "Hurtbox" 關鍵字的節點 (相容你的架構)
	var hurtboxes = root.find_children("*", "Hurtbox", true, false)
	
	for hb in hurtboxes:
		var target_owner = hb.owner if hb.owner else hb.get_parent()
		if not is_instance_valid(target_owner) or target_owner == player: continue
		if target_owner.get("is_dead") == true: continue
		
		if target_owner.name.begins_with("Phantom"): continue
		
		# 🌟 局部新增：隔牆寻敵攔截網
		var space_state = player.get_world_2d().direct_space_state
		
		# 🌟 完美修復 3：雷達探測的發射源必須絕對置中！
		# 不要吃偏移量，防止背貼牆壁時射線起點卡進牆壁裡！
		var start_pos = player.global_position + Vector2(0.0, HOOK_OFFSET.y)
		var end_pos = target_owner.global_position + Vector2(0.0, HOOK_OFFSET.y)
		
		var query = PhysicsRayQueryParameters2D.create(start_pos, end_pos)
		
		# 🚨 注意：這裡的遮罩數值必須與你 Environment 的圖層對齊（見下方說明）
		query.collision_mask = 1 
		query.exclude = [player.get_rid()] # 排除玩家本體的碰撞，防止誤判
		
		var result = space_state.intersect_ray(query)
		if result:
			print("🚫 [雷達探測] 發現敵人在牆後：", target_owner.name, "，拒絕鎖定！")
			continue
			
		var dist = player.global_position.distance_to(target_owner.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = target_owner
			
	return nearest

# ==========================================
# 🧱 勾牆特權路由器
# ==========================================
func trigger_wall_hook(hook_instance: Node2D) -> void:
	if not is_hooking:
		is_hooking = true
		hook_target_node = hook_instance 
		pull_delay_timer = 0.1 
		
		# 🌟 修改：勾牆瞬間的方向計算起點
		var start_pos = player.global_position + _get_player_hook_offset()
		var target_pos = hook_instance.global_position
		hook_pull_dir = start_pos.direction_to(target_pos)
		
		if player is Player:
			player.invincible_time_left = 0.6
		print("🧱 [物理反饋] 鎖鐮抓住了牆體！鎖定軌跡向量：", hook_pull_dir)
		
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
