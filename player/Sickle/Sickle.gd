class_name Sickle
extends Weapon
## 武器腳本：鎖鏈鐮刀 (Chain Sickle) 
## 負責處理鐮刀的連段派生 (無雙 C 技系統) 與共鳴資源 (鏈心值)。

# ==========================================
# 🎛️ 1. 武器核心參數與資源
# ==========================================
@export_group("武器核心參數")
@export var combo_timeout: float = 0.3      # 普攻連段超時重置時間
@export var no_sheath_steps: Array[int] = [4, 11, 12, 20, 21, 22, 41, 80, 81] # 不需播收刀動畫的黑名單招式
@export var ult_energy_cost: float = 100.0  # 大招能量成本

const WEAPON_ID: String = "sickle"          
const SICKLE_HOOK_SCENE = preload("res://Explod/tscn/Dimensional Slash.tscn") # 預留給飛索或鏈刃特效
const SICKLE_WAVE_SCENE = preload("res://player/Katana/c_3_wave.tscn") # 預留給鐮刀橫掃特效

const ZOOM_LEVELS = { 0: Vector2(1.0, 1.0), 1: Vector2(1.01, 1.01), 2: Vector2(1.02, 1.02), 3: Vector2(1.03, 1.03) }

# ==========================================
# 🌀 2. 共鳴迴路 (Resonance Circuit) 變數
# ==========================================
var current_chain_link: int = 0             # 當前鏈心值
const MAX_CHAIN_LINK: int = 100                     
var is_enhanced_ready: bool = false         # 強化戰技是否就緒

# ==========================================
# 📖 3. 招式數據庫 (Data-Driven Combat Config)
# ==========================================
# [普攻字典]
const LIGHT_ATTACK_CONFIG = {
	1: {"anim": "sickle/attack_1", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(100.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 200, "switch": 500, "link_reward": 5, "action_type": Weapon.ActionType.NORMAL},
	2: {"anim": "sickle/attack_2", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(150.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5, "link_reward": 5, "action_type": Weapon.ActionType.NORMAL},
	3: {"anim": "sickle/attack_3", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(200.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5,"link_reward": 5, "action_type": Weapon.ActionType.NORMAL},
	4: {"anim": "sickle/attack_4", "hitbox_name": "Hitbox", "max_hits": 2, "interval": 0.1, "knockback": Vector2(200.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5,"link_reward": 5, "action_type": Weapon.ActionType.NORMAL},
}

# [戰技與大招字典] (已修正為 sickle 路徑)
const SKILL_CONFIG = {
	# C4：戰技下 (20, 21, 22)
	20: { "anim": "katana/attack_c3", "hitbox_name": "C3", "type": Damage.Type.LIGHT,"max_hits": 3, "interval": 0.1, "knockback": Vector2(-100.0, -200.0), "shake": 15.0, "shake_on_hit_only": true, "base_dmg": 300, "energy": 5, "switch": 5, "link_reward": 5,"hit_sfx_type": "hit" },
	21: { "anim": "sickle/attack_c3_2", "hitbox_name": "C3", "type": Damage.Type.LIGHT,"max_hits": 6, "interval": 0.1,"sticky": true, "knockback": Vector2(100.0, -100.0), "shake": 20.0, "shake_on_hit_only": true, "base_dmg": 450, "energy": 5, "switch": 5, "link_reward": 5,"hit_sfx_type": "hit" },
	22: { "anim": "sickle/attack_c3_3", "hitbox_name": "None", "type": Damage.Type.HEAVY, "knockback": Vector2.ZERO, "shake": 30.0, "shake_on_hit_only": true, "base_dmg": 932, "energy": 15, "switch": 20, "link_reward": 10 },
	
	# C2：戰技上 (11, 12)
	11: { "anim": "katana/attack_c1", "hitbox_name": "C1", "type": Damage.Type.HEAVY, "knockback": Vector2(0.0, -400.0), "shake": 20.0, "shake_on_hit_only": false, "base_dmg": 560,"hit_sfx_type": "hit_2", "energy": 10, "switch": 15, "link_reward": 5 },
	12: { "anim": "sickle/attack_c1_2", "hitbox_name": "C1", "type": Damage.Type.HEAVY, "knockback": Vector2(0.0, -400.0), "shake": 30.0, "shake_on_hit_only": true, "base_dmg": 720,"hit_sfx_type": "hit", "energy": 10, "switch": 15, "link_reward": 5 },
	
	# C3：戰技中立 (41)
	41: { "anim": "katana/skill_down", "hitbox_name": "C2", "type": Damage.Type.LIGHT, "knockback": Vector2(100.0, 0.0), "shake": 2.0, "shake_on_hit_only": true, "base_dmg": 200,"hit_sfx_type": "hit", "energy": 10, "switch": 15, "link_reward": 10 },
	
	80: { "anim": "sickle/attack_ult", "hitbox_name": "UltHitbox", "type": Damage.Type.HEAVY, "knockback": Vector2(10.0, -100.0), "shake": 5.0, "shake_on_hit_only": true, "base_dmg": 150, "energy": 0, "switch": 0, "link_reward": 0, 
		"max_hits": 20,"hit_sfx_type": "hit", "interval": 0.1, "sticky": true },
	81: { "anim": "sickle/attack_ult_end", "hitbox_name": "None", "type": Damage.Type.LIGHT, "knockback": Vector2.ZERO, "shake": 0.0, "shake_on_hit_only": true, "base_dmg": 0, "energy": 0, "switch": 0, "link_reward": 0 },
	90: { "anim": "sickle/attack_c0_charge_start", "hitbox_name": "None", "type": Damage.Type.LIGHT, "knockback": Vector2.ZERO, "shake": 0.0, "shake_on_hit_only": true, "base_dmg": 0, "energy": 0, "switch": 0, "link_reward": 0 },
}

# [空戰字典]
const AIR_ATTACK_CONFIG = {
	61: { "anim": "sickle/air_attack_1", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "type": Damage.Type.LIGHT, "knockback": Vector2(20.0, -200.0), "base_dmg": 300,"hit_sfx_type": "hit", "energy": 2, "switch": 4, "link_reward": 2, "action_type": Weapon.ActionType.NORMAL},
	62: { "anim": "sickle/air_attack_2", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "type": Damage.Type.LIGHT, "knockback": Vector2(20.0, -300.0), "base_dmg": 300,"hit_sfx_type": "hit", "energy": 2, "switch": 4, "link_reward": 2, "action_type": Weapon.ActionType.NORMAL},
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

var is_time_stop_triggered: bool = false 
var _tsubame_zoom_phase: int = 0 
var _camera_tween: Tween 

var _is_hitbox_locked: bool = false

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
		# 這裡你可以決定如果滿氣要觸發什麼，或者直接拿去強化 C 技

func consume_chain_link(amount: int) -> void:
	current_chain_link = maxi(current_chain_link - amount, 0)
	print("消耗鏈心值，目前剩餘: ", current_chain_link, "/", MAX_CHAIN_LINK)

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

	if not player.is_on_floor():
		if air_attack_locked or _get_ground_distance() < min_air_attack_height:
			return
		if combo_step == 61:
			combo_step = 62
			air_attack_locked = true 
		else:
			combo_step = 61
			
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

	# ⛓️ C 技專屬派生樞紐
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
		_:
			is_attacking = false

func start_ultimate() -> void:
	if player.has_method("consume_weapon_energy"):
		player.consume_weapon_energy(WEAPON_ID, ult_energy_cost)
		
	step_cooldown = 0.15
	is_attacking = true
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
	is_time_stop_triggered = false 
	_tsubame_zoom_phase = 0 
	
	if is_instance_valid(player):
		player.invincible_time_left = 1.5
	
	gain_chain_link(50)
	
	combo_step = 90 
	_play_skill_step(combo_step)
	
	player.is_input_locked = true 
	print("🌪️ [鎖鏈鐮刀] 變奏技能發動！")

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
			
	if player.is_on_floor():
		air_attack_locked = false 
		if not is_attacking and combo_step in [61, 62]:
			combo_step = 0

# ==========================================
# 🏃 物理與特效場控核心
# ==========================================
func get_current_velocity(delta: float) -> Vector2:
	if not is_attacking:
		return player.velocity

	if player.is_on_floor(): air_attack_locked = false

	var new_x = player.velocity.x
	var new_y = player.velocity.y

	# 🚨 終極防爆衝基底：統一套用 M平方定律
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# ----------------------------------------
	# 物理摩擦力與重力分流
	# ----------------------------------------
	if combo_step == 12:
		if player.animation_player.current_animation_position >= launch_start_time and not is_launch_triggered:
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
					new_y = move_toward(new_y, 0.0, player.default_gravity * 2.0 * delta)
				else:
					new_y += player.default_gravity * delta
		else:
			new_x = move_toward(new_x, 0.0, base_friction)
	
	elif combo_step in [20, 21, 22]: 
		if combo_step == 22:
			var anim_time = player.animation_player.current_animation_position
			if anim_time >= 0.32 and not is_wave_fired:
				is_wave_fired = true
				if CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(20.0) 
				spawn_sword_wave("skill_down")
				
		new_x = move_toward(new_x, 0.0, base_friction)
		if not player.is_on_floor(): 
			new_y += (player.default_gravity * air_skill_gravity_rate) * delta

	elif combo_step == 41: 
		new_x = move_toward(new_x, 0.0, base_friction * skill_neutral_friction_rate)
	
	elif combo_step == 90:
		new_x = move_toward(new_x, 0.0, base_friction * 2.0)
		
		var anim_time = player.animation_player.current_animation_position
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
			
	elif combo_step == 80: 
		new_x = move_toward(new_x, 0.0, base_friction * 5.0)
		new_y = 0.0 
		
		var anim_time = player.animation_player.current_animation_position
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

	elif combo_step in [61, 62]:
		new_x = move_toward(new_x, 0.0, base_friction)

	else:
		new_x = move_toward(new_x, 0.0, base_friction)

	return Vector2(new_x, new_y)
	
func is_handling_gravity() -> bool:
	if combo_step == 12 and is_launch_triggered: return true
	if not player.is_on_floor() and combo_step in [20, 21, 22, 42]: return true
	if combo_step == 80: return true
	return false

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
			combo_step = 1 # 變奏後接普攻第一段
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
		
		if combo_step in [61, 62]: 
			air_attack_locked = true
			
		last_attack_time = Time.get_ticks_msec() / 1000.0
		is_attacking = false
		step_cooldown = 0.0
		
		if combo_step == 80 or _tsubame_zoom_phase > 0:
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
	if not player.is_on_floor() and combo_step in [61, 62]:
		air_attack_locked = true
		
	player.is_input_locked = false 
	_apply_charge_zoom(ZOOM_LEVELS[0])
	is_attacking = false
	combo_step = 0
	step_cooldown = 0.0
	is_launch_triggered = false
	is_wave_fired = false 
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
	
	if not player.is_on_floor() and step in [20, 21, 22]:
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

func spawn_sword_wave(wave_type: String) -> void:
	if not SICKLE_WAVE_SCENE: return
	var wave = SICKLE_WAVE_SCENE.instantiate() as SwordWave
	get_tree().current_scene.add_child(wave)
	
	wave.global_position = player.global_position + Vector2(30 * player.direction, -20)
	wave.direction = player.direction
	
	await get_tree().process_frame 
	if not is_instance_valid(wave) or not wave.hitbox: return
	
	wave.hitbox.spark_type = 0; wave.hitbox.spark_color = Color(0.7, 1.5, 0.5, 1.0); wave.hitbox.aura_color = Color(0, 1, 1, 1)
	
	match wave_type:
		"skill_down":
			var config = SKILL_CONFIG[21] 
			wave.speed = 1500.0; wave.max_distance = 1200.0; wave.scale = Vector2(2.0 * player.direction, 2.0)
			wave.hitbox.damage_amount = max(1, roundi(float(config["base_dmg"])))
			wave.hitbox.absolute_knockback = Vector2(400.0 * player.direction, 0.0)
			wave.hitbox.knockback_force = Vector2(400.0, -400.0)
			wave.hitbox.attack_type = Damage.Type.LIGHT
			wave.hitbox.spark_scale = 0.3
			wave.hitbox.hit_sfx_type = "hit_4"
			
			var w_energy = float(config.get("energy", 0))
			var w_switch = float(config.get("switch", 0))
			var w_link = int(config.get("link_reward", 0))
			var w_multi = config.get("multi_hit_energy", false)
			
			var wave_state = [false] 
			
			wave.hitbox.hit.connect(func(hurtbox: Node):
				if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: return
				
				if w_multi or not wave_state[0]:
					if w_link > 0: gain_chain_link(w_link)
					if (w_energy > 0 or w_switch > 0) and player.has_method("add_weapon_resource"):
						player.add_weapon_resource(WEAPON_ID, w_energy, w_switch)
					wave_state[0] = true
			)

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
