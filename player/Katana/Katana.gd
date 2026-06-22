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

const WEAPON_ID: String = "katana"          
const DIMENSIONAL_SLASH_SCENE = preload("res://Explod/tscn/Dimensional Slash.tscn")
const SWORD_WAVE_SCENE = preload("res://player/Katana/c_3_wave.tscn")

# ==========================================
# 🥋 專屬武藝系統 (Martial Arts Loadout)
# ==========================================
@export var equipped_martial_arts: Array[String] = [
	"res://player/MartialArts/Katana/Art_Katana_11.gd", 
	"res://player/MartialArts/Katana/Art_Katana_22.gd", 
	""
]

# ==========================================
# ⚙️ 初始化與延遲載入
# ==========================================
func _ready() -> void:
	super._ready() 
	call_deferred("_delayed_load_arts")

func _delayed_load_arts() -> void:
	load_martial_arts(equipped_martial_arts)

const ZOOM_LEVELS = { 0: Vector2(1.0, 1.0), 1: Vector2(1.01, 1.01), 2: Vector2(1.02, 1.02), 3: Vector2(1.03, 1.03) }

# ==========================================
# 🌀 2. 共鳴迴路 (Resonance Circuit) 變數
# ==========================================
var current_iai: int = 0                    
var current_tsubame: int = 0                
const MAX_IAI: int = 60                     
const MAX_TSUBAME: int = 60                 
var is_tsubame_ready: bool = false          

# ==========================================
# 📖 3. 招式數據庫 (Data-Driven Combat Config)
# ==========================================
# [普攻字典]
const LIGHT_ATTACK_CONFIG = {
	1: {"anim": "katana/attack_1", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(100.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit_3", "energy": 200, "switch": 500, "iai_reward": 2, "action_type": Weapon.ActionType.NORMAL},
	2: {"anim": "katana/attack_2", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(150.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5, "iai_reward": 2, "action_type": Weapon.ActionType.NORMAL},
	3: {"anim": "katana/attack_3", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(200.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5,"iai_reward": 2, "action_type": Weapon.ActionType.NORMAL},
	4: {"anim": "katana/attack_4", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(200.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5,"iai_reward": 2, "action_type": Weapon.ActionType.NORMAL},
	5: {"anim": "katana/attack_5", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(400.0, 0.0), "shake": 30.0, "hit_sfx_type": "hit_5", "base_dmg": 645, "energy": 2, "switch": 5, "iai_reward": 2, "action_type": Weapon.ActionType.NORMAL },
}

# [戰技與大招字典] 
const SKILL_CONFIG = {
	30: { "anim": "katana/attack_c0_charge_start", "hitbox_name": "None", "type": Damage.Type.LIGHT, "knockback": Vector2.ZERO, "shake": 0.0, "shake_on_hit_only": true, "base_dmg": 0, "energy": 0, "switch": 0, "iai_reward": 0 },
	34: { "anim": "katana/attack_c0_release", "hitbox_name": "C0", "type": Damage.Type.LIGHT, "knockback": Vector2(50.0, 0.0), "shake": 6.0, "shake_on_hit_only": true, "base_dmg": 200,"hit_sfx_type": "hit", "energy": 1, "switch": 2, "iai_reward": 0 },
	32: { "anim": "katana/attack_c0_release", "hitbox_name": "C0", "type": Damage.Type.LIGHT, "knockback": Vector2.ZERO, "shake": 2.0, "shake_on_hit_only": true, "base_dmg": 325,"hit_sfx_type": "hit", "energy": 1, "switch": 2, "iai_reward": 0, },
	33: { "anim": "katana/attack_c0_release", "hitbox_name": "C0", "type": Damage.Type.LIGHT, "knockback": Vector2.ZERO, "shake": 3.0, "shake_on_hit_only": true, "base_dmg": 325,"hit_sfx_type": "hit", "energy": 1, "switch": 2, "iai_reward": 0,  },
	
	41: { "anim": "katana/skill_down", "hitbox_name": "C2", "type": Damage.Type.LIGHT, "knockback": Vector2(100.0, 0.0), "shake": 2.0, "shake_on_hit_only": true, "base_dmg": 200,"hit_sfx_type": "hit", "energy": 10, "switch": 15, "iai_reward": 10 },
	
	42: { "anim": "katana/attack_tsubame", "hitbox_name": "attack_tsubame", "type": Damage.Type.HEAVY, "knockback": Vector2(0.0, -80.0), "shake": 0.0, "shake_on_hit_only": true, 
		"base_dmg": 200,"hit_sfx_type": "hit", "energy": 25, "switch": 30, "iai_reward": 0, 
		"max_hits": 12, "interval": 0.1, "sticky": true },
	
	80: { "anim": "katana/attack_ult", "hitbox_name": "UltHitbox", "type": Damage.Type.HEAVY, "knockback": Vector2(10.0, -100.0), "shake": 5.0, "shake_on_hit_only": true, "base_dmg": 150, "energy": 0, "switch": 0, "iai_reward": 0, 
		"max_hits": 20,"hit_sfx_type": "hit", "interval": 0.1, "sticky": true },
	81: { "anim": "katana/attack_ult_end", "hitbox_name": "None", "type": Damage.Type.LIGHT, "knockback": Vector2.ZERO, "shake": 0.0, "shake_on_hit_only": true, "base_dmg": 0, "energy": 0, "switch": 0, "iai_reward": 0 },
}

# [空戰字典]
const AIR_ATTACK_CONFIG = {
	61: { "anim": "katana/air_attack_1", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "type": Damage.Type.LIGHT, "knockback": Vector2(20.0, -200.0), "base_dmg": 300,"hit_sfx_type": "hit", "energy": 2, "switch": 4, "iai_reward": 2, "action_type": Weapon.ActionType.NORMAL},
	62: { "anim": "katana/air_attack_2", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "type": Damage.Type.LIGHT, "knockback": Vector2(20.0, -300.0), "base_dmg": 300,"hit_sfx_type": "hit", "energy": 2, "switch": 4, "iai_reward": 2, "action_type": Weapon.ActionType.NORMAL},
}

# ==========================================
# 🚀 4. 物理運算與手感參數
# ==========================================
@export_group("重擊(蓄力拔刀)設定")
@export var charge_time_per_tier: float = 0.4   
@export var max_charge_tiers: int = 3           
@export var thrust_speed: float = 200.0         

@export_group("戰技中立 (死亡切割) 設定")
@export var skill_neutral_friction_rate: float = 0.2 

@export_group("空戰設定 (Air Combat)")
@export var min_air_attack_height: float = 40.0 
@export var air_thrust_force: float = -150.0    
@export var air_skill_gravity_rate: float = 0.25 

# --- 內部狀態 ---
var current_active_hitbox: Hitbox = null

var _current_energy_reward: float = 0.0
var _current_switch_reward: float = 0.0
var _current_iai_reward: int = 0
var _multi_hit_energy: bool = false
var _has_granted_resources_this_step: bool = false

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
# 🎨 太刀專屬動態圖標
# ==========================================
@export_group("太刀動態圖標")
@export var skill_1_tsubame_icon: Texture2D


# ==========================================
# 🌀 5. 共鳴迴路邏輯
# ==========================================
func gain_iai(amount: int) -> void:
	if amount <= 0: return
	if try_forward_resource("gain_iai", amount): return
	current_iai = mini(current_iai + amount, MAX_IAI)
	print("🟢 命中！獲得居合值: ", amount, " | 目前居合: ", current_iai, "/", MAX_IAI)

func consume_iai_for_charge() -> void:
	current_iai = maxi(current_iai - 10, 0)
	current_tsubame = mini(current_tsubame + 10, MAX_TSUBAME)
	if current_tsubame >= MAX_TSUBAME and not is_tsubame_ready:
		is_tsubame_ready = true
		skill_1_timer = 0.0 

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

	if combo_step == 30 or SKILL_CONFIG.has(combo_step):
		combo_step = 0

	combo_step += 1
	if not LIGHT_ATTACK_CONFIG.has(combo_step):
		combo_step = 1

	is_attacking = true
	_play_light_step(combo_step)
	
	if Input.is_action_pressed("attack"): light_hold_timer = 0.15
	else: light_hold_timer = 0.0

func start_heavy_attack() -> void:
	if step_cooldown > 0:
		is_attacking = false
		return
	
	step_cooldown = 0.15
	air_attack_locked = false
	
	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time > combo_timeout:
			combo_step = 0
			
	is_attacking = true
	is_launch_triggered = false
	is_wave_fired = false
	is_time_stop_triggered = false 

	if not player.is_on_floor():
		if is_tsubame_ready:
			_play_skill_step(42) 
			is_tsubame_ready = false
			current_tsubame = 0
		else:
			is_attacking = false 
		return

	if is_tsubame_ready:
		_play_skill_step(42) 
		is_tsubame_ready = false
		current_tsubame = 0 
	else:
		_play_skill_step(41)
		skill_1_timer = skill_1_cd
			
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
	player.invincible_time_left = 3.0
	
	_play_skill_step(combo_step)
	player.is_input_locked = true

func update_timers_only(delta: float) -> void:
	if step_cooldown > 0: step_cooldown -= delta 
	if skill_1_timer > 0: skill_1_timer -= delta
	if ult_timer > 0: ult_timer -= delta
			
	if player.is_on_floor():
		air_attack_locked = false 
		if not is_attacking and combo_step in [61, 62]:
			combo_step = 0

# ==========================================
# 🏃 物理與特效場控核心
# ==========================================
func get_current_velocity(delta: float) -> Vector2:
	if is_instance_valid(active_martial_art) and active_martial_art.is_active:
		return active_martial_art.get_current_velocity(delta)
		
	if not is_attacking:
		return player.velocity

	if player.is_on_floor(): air_attack_locked = false

	var new_x = player.velocity.x
	var new_y = player.velocity.y

	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# --- 蓄力邏輯 ---
	if combo_step in [1, 2, 3, 4, 61, 62]: 
		if current_iai >= 10 and Input.is_action_pressed("attack"):
			light_hold_timer += delta
			if light_hold_timer >= 0.35:
				var anim_len = player.animation_player.current_animation_length
				var anim_pos = player.animation_player.current_animation_position
				
				if anim_len > 0.0 and (anim_pos / anim_len) >= 0.5:
					if current_iai >= 10:
						combo_step = 30 
						current_charge_timer = 0.0
						current_charge_tier = 0
						_play_skill_step(30)
					else: light_hold_timer = 0.0
		else: light_hold_timer = 0.0

	if combo_step == 30:
		var move_dir := Input.get_axis("move_left", "move_right")
		if not is_zero_approx(move_dir) and player is Player:
			player.direction = player.Direction.LEFT if move_dir < 0 else player.Direction.RIGHT
			
		new_x = move_toward(new_x, 0.0, base_friction * 2.0)
		
		var is_holding = Input.is_action_pressed("attack")
		if not (player is Player): is_holding = false
		
		if is_holding:
			current_charge_timer += delta
			var new_tier = min(max_charge_tiers, floori(current_charge_timer / charge_time_per_tier))
			
			if new_tier > current_charge_tier:
				if current_iai >= 10:
					current_charge_tier = new_tier
					consume_iai_for_charge()
					
					player.spawn_anim_vfx("Aggregation ring", 0, -20, Vector2(1.5, 1.5), 0, Color.WHITE, Color.WHITE, false, 2, 1.0)
					if CombatManager.has_method("apply_camera_shake"):
						CombatManager.apply_camera_shake(2.0 + current_charge_tier * 1.5)
					_apply_charge_zoom(ZOOM_LEVELS[current_charge_tier])
				else:
					current_charge_timer = current_charge_tier * charge_time_per_tier
					
			if not player.animation_player.is_playing():
				player.play_safe_anim("katana/attack_c0_charge_loop")
		else:
			_apply_charge_zoom(ZOOM_LEVELS[0])
			if current_charge_tier == 0:
				is_attacking = false; combo_step = 0; current_charge_timer = 0.0; light_hold_timer = 0.0
				player.is_input_locked = false 
				var p_scabbard = player.get("scabbard")
				if p_scabbard: p_scabbard.fade_in()
			else:
				var release_step = 34 
				if current_charge_tier == 2: release_step = 32
				elif current_charge_tier == 3: release_step = 33
				_play_skill_step(release_step)

	elif combo_step in [32, 33, 34]:
		var anim_time = player.animation_player.current_animation_position
		if anim_time < 0.05:
			var speed_multiplier = 4.5 if combo_step == 34 else (6.5 if combo_step == 32 else 8.0)
			new_x = player.direction * (thrust_speed * speed_multiplier)
		else: new_x = move_toward(new_x, 0.0, base_friction)
	
	elif combo_step == 41: 
		new_x = move_toward(new_x, 0.0, base_friction * skill_neutral_friction_rate)
		
	elif combo_step == 42: 
		new_x = move_toward(new_x, 0.0, base_friction * 5.0)
		new_y = 0.0 if player.is_on_floor() else player.default_gravity * air_skill_gravity_rate * delta 
		
		var anim_time = player.animation_player.current_animation_position
		if anim_time >= 0.08 and not is_time_stop_triggered:
			is_time_stop_triggered = true 
			if player is Player: player.invincible_time_left = 2.0 
			
		if anim_time >= 0.10 and _tsubame_zoom_phase == 0:
			_tsubame_zoom_phase = 1
			_apply_charge_zoom(Vector2(0.75, 0.75), 1.6) 
				
		if anim_time >= 1.76 and not is_wave_fired:
			is_wave_fired = true 
			if CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(60.0) 
				
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
			enable_hitbox("CollisionShape2D2")
			
	elif combo_step == 80: 
		new_x = move_toward(new_x, 0.0, base_friction * 5.0)
		new_y = 0.0 
		var anim_time = player.animation_player.current_animation_position
		if anim_time >= 0.05 and not is_time_stop_triggered:
			is_time_stop_triggered = true 
			if player.has_method("trigger_time_stop"): player.trigger_time_stop(3.0, 0.001) 
			player.animation_player.speed_scale = 1.0 / 0.001 
			player.invincible_time_left = 3.0
			
		if anim_time >= 0.05 and _tsubame_zoom_phase == 0:
			_tsubame_zoom_phase = 1
			_apply_charge_zoom(Vector2(1.2, 1.2), 0.3) 
			
		if anim_time >= 0.70 and _tsubame_zoom_phase == 1:
			_tsubame_zoom_phase = 2
			if CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(100.0, 0.07) 
			_apply_charge_zoom(Vector2(0.85, 0.85), 0.1) 
		
		if anim_time >= 0.82 and _tsubame_zoom_phase == 2:
			_tsubame_zoom_phase = 3
			_apply_charge_zoom(Vector2(0.65, 0.65), 1.8) 
			
		if anim_time >= 2.80 and _tsubame_zoom_phase == 3:
			_tsubame_zoom_phase = 4
			if CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(180.0, 0.15) 
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.2)

	elif combo_step in [61, 62]:
		new_x = move_toward(new_x, 0.0, base_friction)
	else:
		new_x = move_toward(new_x, 0.0, base_friction)

	return Vector2(new_x, new_y)
	
func is_handling_gravity() -> bool:
	if is_instance_valid(active_martial_art) and active_martial_art.is_active:
		if active_martial_art.has_method("is_handling_gravity"): return active_martial_art.is_handling_gravity()
			
	if not player.is_on_floor() and combo_step == 42: return true
	if combo_step == 80: return true
	return false

# ==========================================
# 🎬 招式結束判定
# ==========================================
func is_attack_finished() -> bool:
	if not is_attacking: return true
	
	if not player.animation_player.is_playing():
		if combo_step == 80:
			combo_step = 81
			_play_skill_step(81) 
			player.invincible_time_left = 0.5 
			return false
			
		if Input.is_action_pressed("attack"):
			if combo_step in [1, 2, 3, 4, 12, 21, 32, 33, 34, 41, 61, 62]:
				if current_iai >= 10:
					combo_step = 30; current_charge_timer = 0.0; current_charge_tier = 0
					_play_skill_step(30)
					return false

		player.is_input_locked = false 
		if combo_step in [61, 62]: air_attack_locked = true
			
		last_attack_time = Time.get_ticks_msec() / 1000.0
		is_attacking = false; step_cooldown = 0.0
		
		if combo_step in [42, 80] or _tsubame_zoom_phase > 0:
			_tsubame_zoom_phase = 0
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.4)
			if player.has_method("clear_time_stop"): player.clear_time_stop()
				
		_is_hitbox_locked = true 
		disable_hitbox()
		
		if is_instance_valid(active_martial_art):
			active_martial_art.is_active = false
			active_martial_art = null
		
		var p_scabbard = player.get("scabbard")
		if not requires_sheath() and p_scabbard: p_scabbard.fade_in()
			
		return true
	return false

# ==========================================
# 💥 強制打斷處理 
# ==========================================
func cancel_attack() -> void:
	if not player.is_on_floor() and combo_step in [30, 61, 62]: air_attack_locked = true
		
	player.is_input_locked = false 
	_apply_charge_zoom(ZOOM_LEVELS[0])
	is_attacking = false; combo_step = 0; step_cooldown = 0.0; is_launch_triggered = false
	current_charge_tier = 0; current_charge_timer = 0.0; light_hold_timer = 0.0; is_wave_fired = false; _tsubame_zoom_phase = 0
	
	if is_instance_valid(active_martial_art):
		active_martial_art.cancel()
		active_martial_art = null
	
	if is_time_stop_triggered:
		is_time_stop_triggered = false
		if player.has_method("clear_time_stop"): player.clear_time_stop() 
	else: is_time_stop_triggered = false 
	
	_is_hitbox_locked = true 
	disable_hitbox()
	var p_scabbard = player.get("scabbard")
	if p_scabbard: p_scabbard.fade_in()
		
func requires_sheath() -> bool:
	if combo_step == 0: return false
	return combo_step not in no_sheath_steps
	
# ==========================================
# ⚙️ 內部實作與接口
# ==========================================
func _play_light_step(step: int) -> void:
	disable_hitbox()
	var config: Dictionary = LIGHT_ATTACK_CONFIG[step]
	_apply_hitbox_config(config)
	
	if config.has("sfx") and config["sfx"] != null: AudioManager.play_sfx(config["sfx"], -8.0)
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _play_skill_step(step: int) -> void:
	disable_hitbox()
	var config: Dictionary = SKILL_CONFIG[step]
	_apply_hitbox_config(config)
	
	if config.has("sfx") and config["sfx"] != null: AudioManager.play_sfx(config["sfx"], -5.0)
	
	if current_active_hitbox:
		if step == 41: current_active_hitbox.max_hits = 5; current_active_hitbox.hit_interval = 0.1; current_active_hitbox.sticky_multi_hit = true
		elif step == 34: current_active_hitbox.max_hits = 2; current_active_hitbox.hit_interval = 0.1; current_active_hitbox.sticky_multi_hit = true
		elif step == 32: current_active_hitbox.max_hits = 4; current_active_hitbox.hit_interval = 0.1; current_active_hitbox.sticky_multi_hit = true
		elif step == 33: current_active_hitbox.max_hits = 7; current_active_hitbox.hit_interval = 0.1; current_active_hitbox.sticky_multi_hit = true; current_active_hitbox.spark_scale = 0.6; current_active_hitbox.spark_color = Color(1.0, 0.0, 0.0, 1.0); current_active_hitbox.aura_color = Color(1.0, 0.0, 0.0, 1.0)  
		elif step == 42: current_active_hitbox.spark_scale = 0.6
		elif step == 80: current_active_hitbox.spark_scale = 1.0
	
	if not player.is_on_floor() and step == 42: player.velocity.y = air_thrust_force * 0.5
		
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

## 🌟 外部武藝專屬發招接口
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
		if "iai_reward" in hitbox: hitbox.iai_reward = int(config.get("iai_reward", 0))
		
		hitbox.spark_type = 0; hitbox.spark_scale = 0.3; hitbox.spark_color = Color(0.7, 1.5, 0.5, 1.0); hitbox.aura_color = Color(0, 1, 1, 1)
		hitbox.hit_targets.clear() 
		
		_current_energy_reward = float(config.get("energy", 0))
		_current_iai_reward = int(config.get("iai_reward", 0))
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
		if _current_iai_reward > 0: gain_iai(_current_iai_reward)
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
	if not player.is_on_floor(): return is_tsubame_ready 
	if is_tsubame_ready: return true
	if skill_1_timer > 0: return false
	return true

func can_use_ultimate() -> bool:
	if ult_timer > 0: return false 
	if not player.is_on_floor(): return false 
	if player.has_method("get_weapon_energy"):
		if player.get_weapon_energy(WEAPON_ID) < ult_energy_cost: return false 
	return true

func get_dynamic_skill_icon(slot: int) -> Texture2D:
	match slot:
		1: if is_tsubame_ready and skill_1_tsubame_icon: return skill_1_tsubame_icon
	return super.get_dynamic_skill_icon(slot)

func export_weapon_data() -> Dictionary:
	return {
		"current_iai": current_iai, "current_tsubame": current_tsubame, "is_tsubame_ready": is_tsubame_ready,
		"skill_1_timer": skill_1_timer if "skill_1_timer" in self else 0.0, "ult_timer": ult_timer if "ult_timer" in self else 0.0
	}

func import_weapon_data(data: Dictionary) -> void:
	current_iai = data.get("current_iai", 0)
	current_tsubame = data.get("current_tsubame", 0)
	is_tsubame_ready = data.get("is_tsubame_ready", false)
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
