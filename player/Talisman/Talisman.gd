class_name Talisman
extends Weapon
## 武器腳本：符咒 (Talisman) - 武藝組件重構版

const WEAPON_ID: String = "talisman"

# ==========================================
# 🥋 專屬武藝系統 (Martial Arts Loadout)
# ==========================================
@export var equipped_martial_arts: Array[String] = [
	"res://player/MartialArts/Talisman/Art_Talisman_20.gd", 
	"res://player/MartialArts/Talisman/Art_Talisman_30.gd", 
	"res://player/MartialArts/Talisman/Art_Talisman_31.gd"
]

func _ready() -> void:
	super._ready()
	call_deferred("_delayed_load_arts")

func _delayed_load_arts() -> void:
	# 🌟 終極護盾：如果持有人是殘影，代表這是由殘影完美複製的武器，絕對不准重載卡帶！
	if player != null and player.name.begins_with("Phantom"):
		return
		
	# 此時 player 絕對已經有值了，安心派發給武藝組件！
	load_martial_arts(equipped_martial_arts)

# ==========================================
# 🎛️ 1. 武器核心參數與資源
# ==========================================
@export_group("武器核心參數")
@export var combo_timeout: float = 0.3      
@export var no_sheath_steps: Array[int] = [30,31,40,50,80,81] 
@export var ult_energy_cost: float = 100.0  

const TALISMAN_VFX_SCENE = preload("res://player/Talisman/TalismanVFX.tscn")
const HEALING_TOWER_SCENE = preload("res://player/Talisman/HealingTower.tscn") 
const LASER_SCENE = preload("res://player/Talisman/TalismanLaser.tscn")

# ==========================================
# 📖 2. 招式數據庫 (Data-Driven Combat Config)
# ==========================================
const LIGHT_ATTACK_CONFIG = {
	1: {"anim": "talisman/attack_1", "hitbox_name": "Hitbox", "base_dmg": 100, "energy": 5, "charge_reward": 0, "vfx_anim": "a1", "vfx_fly_dist": 0.0, "action_type": Weapon.ActionType.NORMAL},
	2: {"anim": "talisman/attack_2", "hitbox_name": "Hitbox", "base_dmg": 120, "energy": 5, "charge_reward": 0, "vfx_anim": "a2", "vfx_fly_dist": 0.0, "action_type": Weapon.ActionType.NORMAL},
	3: {"anim": "talisman/attack_3", "hitbox_name": "Hitbox", "base_dmg": 40, "energy": 2, "max_hits": 3, "interval": 0.1, "sticky": true, "vfx_anim": "a3", "charge_reward": 10, "vfx_fly_dist": 0.0, "action_type": Weapon.ActionType.NORMAL},
	4: {"anim": "talisman/attack_4", "hitbox_name": "Hitbox", "base_dmg": 160, "energy": 6, "charge_reward": 0, "heal_amount": 3, "vfx_fly_dist": 0.0, "vfx_anim": "a5", "action_type": Weapon.ActionType.NORMAL},
	5: {"anim": "talisman/attack_5", "hitbox_name": "Hitbox", "base_dmg": 180, "energy": 6, "charge_reward": 0, "heal_amount": 3, "vfx_fly_dist": 0.0, "vfx_anim": "a6", "action_type": Weapon.ActionType.NORMAL},
	60: {"anim": "talisman/air_attack_1", "hitbox_name": "None", "base_dmg": 100, "energy": 5, "charge_reward": 10, "vfx_fly_dist": 0.0, "vfx_anim": "a5", "action_type": Weapon.ActionType.NORMAL}
}

const SKILL_CONFIG = {
	20: {"anim": "talisman/c1", "hitbox_name": "C1", "base_dmg": 50, "energy": 5, "charge_reward": 0, "max_hits": 5, "interval": 0.1, "sticky": true, "vfx_anim": "c0", "vfx_fly_dist": 0.0, "laser_scale": 0.8, "laser_tracking": true, "laser_dmg": 200, "laser_type": Damage.Type.LIGHT, "laser_offset": Vector2(0.0, -30.0), "laser_shake": 30.0},
	30: {"anim": "talisman/c2", "hitbox_name": "C2", "type": Damage.Type.HEAVY, "base_dmg": 80, "energy": 5, "charge_reward": 0, "max_hits": 4, "interval": 0.1, "sticky": true, "shake": 10.0, "knockback": Vector2(0.0, -300.0), "vfx_anim": "c2", "vfx_fly_dist": 0.0, "action_type": Weapon.ActionType.SKILL},
	31: {"anim": "talisman/c2_2", "hitbox_name": "C2_2", "type": Damage.Type.HEAVY, "base_dmg": 990, "energy": 5, "charge_reward": 0, "max_hits": 1, "interval": 0.1, "sticky": true, "shake": 15.0, "vfx_anim": "c2_2", "vfx_fly_dist": 0.0,"knockback": Vector2(0.0, 1000.0), "action_type": Weapon.ActionType.SKILL,"hit_sfx_type": "hit_6"},
	40: {"anim": "talisman/c3_2", "hitbox_name": "None", "base_dmg": 0, "energy": 0, "charge_reward": 0},
	50: {"anim": "talisman/c3", "hitbox_name": "None", "base_dmg": 120, "energy": 5, "charge_reward": 0, "vfx_anim": "a5"},
	80: {"anim": "talisman/attack_ult", "hitbox_name": "UltHitbox", "type": Damage.Type.HEAVY, "base_dmg": 150, "energy": 0, "charge_reward": 0, "max_hits": 10, "interval": 0.1, "sticky": true, "shake": 5.0, "knockback": Vector2(100.0, -100.0), "action_type": Weapon.ActionType.ULTIMATE, "laser_scale": 4.0, "laser_tracking": false, "laser_dmg": 1550, "laser_type": Damage.Type.HEAVY, "laser_knockback": Vector2(600.0, -500.0), "laser_shake": 70.0 , "hit_sfx_type": "hit"},
	81: {"anim": "talisman/attack_ult_end", "hitbox_name": "None", "base_dmg": 0, "energy": 0, "action_type": Weapon.ActionType.ULTIMATE}
}

# ==========================================
# 🌀 3. 共鳴迴路變數
# ==========================================
var current_talisman_charge: int = 0      
const MAX_TALISMAN_CHARGE: int = 50     

func gain_talisman_charge(amount: int) -> void:
	if amount <= 0: return
	if try_forward_resource("gain_talisman_charge", amount): return
	current_talisman_charge = mini(current_talisman_charge + amount, MAX_TALISMAN_CHARGE)
	print("🟢 命中！獲得靈符值: ", amount, " | 目前靈符: ", current_talisman_charge, "/", MAX_TALISMAN_CHARGE)
	
# ==========================================
# 🎛️ 內部狀態變數
# ==========================================
@export_group("空戰設定 (Air Combat)")
@export var min_air_attack_height: float = 40.0 
@export var air_thrust_force: float = -150.0    
@export var air_skill_gravity_rate: float = 0.95 
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
var _phantom_flags_synced: bool = false
var is_enhanced_mode: bool = false

var is_ult_buff_active: bool = false 
var ult_buff_duration_timer: float = 0.0
var ult_heal_timer: float = 0.0  
var ult_laser_timer: float = 0.0 
var active_ult_buff_vfx: Node = null

var current_active_hitbox: Hitbox = null
var _is_hitbox_locked: bool = false

var _current_energy_reward: float = 0.0
var _current_charge_reward: int = 0       
var _multi_hit_energy: bool = false       
var _has_granted_resources_this_step: bool = false

# ==========================================
# 🎬 總監標準接口實作
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
	
	if is_enhanced_mode:
		if current_talisman_charge < 10:
			is_enhanced_mode = false
			combo_step = 1 
		else:
			if combo_step < 4 or combo_step > 5: combo_step = 4
			else:
				combo_step += 1
				if combo_step > 5: combo_step = 4
				
			current_talisman_charge -= 10
			
			var current_config = LIGHT_ATTACK_CONFIG[combo_step]
			var heal_val = current_config.get("heal_amount", 0)
			if heal_val > 0 and player.get("stats") and "health" in player.stats:
				player.stats.health += heal_val
				if player.has_method("spawn_anim_vfx"): player.spawn_anim_vfx("heal_flash", 0, -30)
			
			if current_talisman_charge < 10: is_enhanced_mode = false
	else:
		if not player.is_on_floor():
			if air_attack_locked or _get_ground_distance() < min_air_attack_height:
				is_attacking = false
				return
			combo_step = 60
			air_attack_locked = true 
		else:
			combo_step += 1
			if combo_step > 3 or combo_step < 1: combo_step = 1
			
	if is_enhanced_mode:
		var config = LIGHT_ATTACK_CONFIG[combo_step].duplicate()
		if not player.is_on_floor():
			if combo_step == 4: config["anim"] = "talisman/air_attack_1"
			elif combo_step == 5: config["anim"] = "talisman/air_attack_2"
		_play_attack(config)
	else:
		_play_attack(LIGHT_ATTACK_CONFIG[combo_step])

func start_heavy_attack() -> void:
	# 🌟 扶正：50 號動作正式成為常規「中立戰技」！
	if step_cooldown > 0: return
	if not player.is_on_floor():
		is_attacking = false
		return
		
	step_cooldown = 0.15
	is_attacking = true
	is_vfx_fired = false 
	is_tower_spawned = false 
	air_attack_locked = false
	
	if is_enhanced_mode:
		combo_step = 40
		_play_attack(SKILL_CONFIG[combo_step])
		skill_1_timer = skill_1_cd
		is_enhanced_mode = false
		print("🔮 [戰技中立] 退出強化型態 (40)")
	else:
		if current_talisman_charge >= 10:
			combo_step = 50
			_play_attack(SKILL_CONFIG[combo_step])
			skill_1_timer = skill_1_cd
			is_enhanced_mode = true
			print("🔮 [戰技中立] 進入強化型態 (50)")
		else:
			is_attacking = false 

func start_ultimate() -> void:
	if is_instance_valid(active_ult_buff_vfx):
		active_ult_buff_vfx.queue_free()
		active_ult_buff_vfx = null
	
	if player.has_method("consume_weapon_energy"):
		player.consume_weapon_energy(WEAPON_ID, ult_energy_cost)
		
	step_cooldown = 0.15
	is_attacking = true
	is_vfx_fired = false 
	is_tower_spawned = false 
	is_time_stop_triggered = false 
	_tsubame_zoom_phase = 0
	
	ult_timer = ult_cd 
	air_attack_locked = false 
	combo_step = 80 
	player.invincible_time_left = 3.0 
	
	_play_attack(SKILL_CONFIG[combo_step])
	player.is_input_locked = true 

func update_timers_only(delta: float) -> void:
	if step_cooldown > 0: step_cooldown -= delta
	if skill_1_timer > 0: skill_1_timer -= delta 
	if ult_timer > 0: ult_timer -= delta
	
	if player.is_on_floor(): air_attack_locked = false 
	
	if is_ult_buff_active:
		if ult_buff_duration_timer > 0:
			ult_buff_duration_timer -= delta
			
			if ult_heal_timer > 0: ult_heal_timer -= delta
			if ult_heal_timer <= 0.0:
				ult_heal_timer = 2.0
				if player.get("stats") and "health" in player.stats:
					player.stats.health += 3
					if player.has_method("spawn_anim_vfx"): player.spawn_anim_vfx("heal_flash", 0, -30)
						
			if ult_laser_timer > 0: ult_laser_timer -= delta
			if ult_laser_timer <= 0.0:
				var current_state = player.state_machine.current_state.name.to_lower() if is_instance_valid(player.state_machine.current_state) else ""
				if current_state == "weaponattack" and is_instance_valid(player.current_weapon):
					if player.current_weapon.current_action_type == Weapon.ActionType.NORMAL:
						ult_laser_timer = 1.0
						_trigger_ult_lasers()
		else:
			is_ult_buff_active = false
			if is_instance_valid(active_ult_buff_vfx):
				active_ult_buff_vfx.queue_free()
				active_ult_buff_vfx = null

func _trigger_ult_lasers() -> void:
	if not is_instance_valid(player): return
	_spawn_weapon_vfx({"vfx_anim": "a5"})
	var pulse_config = {
		"laser_dmg": 160, "laser_scale": 1.0, "laser_tracking": true, "laser_type": Damage.Type.LIGHT,
		"laser_offset": Vector2(-40.0, -50.0), "energy": 0
	}
	var angles = [deg_to_rad(-10.0), deg_to_rad(10.0)]
	for angle in angles: _spawn_laser_projectile(pulse_config, angle)

# ==========================================
# 🏃 物理更新攔截器
# ==========================================
func get_current_velocity(delta: float) -> Vector2:
	if is_instance_valid(active_martial_art) and active_martial_art.is_active:
		return active_martial_art.get_current_velocity(delta)

	if not is_attacking: return player.velocity
	if player.is_on_floor(): air_attack_locked = false
	
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var anim_time = player.animation_player.current_animation_position
	
	if not (player is Player) and not _phantom_flags_synced:
		_phantom_flags_synced = true
		if combo_step in [1, 2, 3, 4, 5] and anim_time >= 0.1: is_vfx_fired = true
		if combo_step == 50 and anim_time >= 0.7: is_vfx_fired = true

	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta
	
	if combo_step in [1, 2, 3, 4, 5]:
		new_x = move_toward(new_x, 0.0, base_friction)
		if not player.is_on_floor() and combo_step in [4, 5]:
			if anim_time < 0.1: new_y = air_thrust_force * 0.5 
			else: new_y += (player.default_gravity * air_skill_gravity_rate) * delta
				
		if anim_time >= 0.1 and not is_vfx_fired:
			is_vfx_fired = true
			_spawn_weapon_vfx(LIGHT_ATTACK_CONFIG[combo_step])
			if combo_step in [4, 5]:
				var angles = []
				if combo_step == 4: angles = [deg_to_rad(-10.0), 0.0, deg_to_rad(-20.0)]
				elif combo_step == 5: angles = [deg_to_rad(10.0), 0.0, deg_to_rad(20.0)]
				for angle in angles: _spawn_laser_projectile(LIGHT_ATTACK_CONFIG[combo_step], angle)
				
	elif combo_step == 40 or combo_step == 50:
		new_x = move_toward(new_x, 0.0, base_friction)
		if not player.is_on_floor():
			if anim_time < 0.1: new_y = air_thrust_force * 0.5
			else: new_y += (player.default_gravity * air_skill_gravity_rate) * delta
		
		if combo_step == 50 and anim_time >= 0.7 and not is_vfx_fired:
			is_vfx_fired = true
			_spawn_weapon_vfx(SKILL_CONFIG[50])
			if player is Player and CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(40.0) 
			
			var num_lasers = clamp(int(current_talisman_charge / 10), 1, 5)
			var angles = []
			match num_lasers:
				1: angles = [0.0]
				2: angles = [deg_to_rad(-10.0), deg_to_rad(10.0)]
				3: angles = [deg_to_rad(-15.0), 0.0, deg_to_rad(15.0)]
				4: angles = [deg_to_rad(-20.0), deg_to_rad(-7.0), deg_to_rad(7.0), deg_to_rad(20.0)]
				5: angles = [deg_to_rad(-20.0), deg_to_rad(-10.0), 0.0, deg_to_rad(10.0), deg_to_rad(20.0)]
			for angle in angles: _spawn_laser_projectile(SKILL_CONFIG[50], angle)
		
	elif combo_step == 60:
		new_x = move_toward(new_x, 0.0, base_friction)
		if anim_time < 0.1: new_y = air_thrust_force 
		else: new_y += (player.default_gravity * air_skill_gravity_rate) * delta 
			
		if anim_time >= 0.1 and not is_vfx_fired:
			is_vfx_fired = true
			_spawn_weapon_vfx(LIGHT_ATTACK_CONFIG[60])
			_spawn_laser_projectile(LIGHT_ATTACK_CONFIG[60], 0.0)
	
	elif combo_step == 80:
		new_x = move_toward(new_x, 0.0, base_friction * 5.0)
		new_y = 0.0 
		
		if anim_time >= 0.05 and not is_time_stop_triggered:
			is_time_stop_triggered = true 
			if player.has_method("trigger_time_stop"): player.trigger_time_stop(3.0, 0.001) 
			player.animation_player.speed_scale = 1.0 / 0.001 
			
		if anim_time >= 0.05 and _tsubame_zoom_phase == 0:
			_tsubame_zoom_phase = 1
			_apply_charge_zoom(Vector2(1.2, 1.2), 0.1) 
		
		if anim_time >= 0.1 and not is_vfx_fired:
			is_vfx_fired = true
			_spawn_weapon_vfx({"vfx_anim": "ult"})
			
		if anim_time >= 0.15 and _tsubame_zoom_phase == 1:
			_tsubame_zoom_phase = 2
			_apply_charge_zoom(ZOOM_LEVELS[0], 1.55)
			
		if anim_time >= 1.82 and not is_tower_spawned:
			is_tower_spawned = true 
			if player.has_method("clear_time_stop"): player.clear_time_stop()
			player.animation_player.speed_scale = 1.0 
			_spawn_weapon_vfx({"vfx_anim": "a6"})
			_spawn_laser_projectile(SKILL_CONFIG[80], 0.0)

		if anim_time >= 1.83 and _tsubame_zoom_phase == 2:
			_tsubame_zoom_phase = 3
			if CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(70.0, 0.2)
	
	elif combo_step == 81:
		new_x = move_toward(new_x, 0.0, base_friction)
				
	return Vector2(new_x, new_y)

func is_handling_gravity() -> bool:
	if is_instance_valid(active_martial_art) and active_martial_art.is_active:
		if active_martial_art.has_method("is_handling_gravity"): return active_martial_art.is_handling_gravity()
	if not player.is_on_floor() and combo_step in [4, 5, 40, 50, 60]: return true
	if combo_step == 80: return true 
	return false

func is_attack_finished() -> bool:
	# 如果根本不在攻擊狀態，直接放人
	if not is_attacking: return true
	
	# 🌟 核心修復：優先檢查動畫完結
	if not player.animation_player.is_playing():
		
		# ==========================================
		# 🌟 大招演出完後的「結尾接力」
		# ==========================================
		if combo_step == 80:
			combo_step = 81
			_play_attack(SKILL_CONFIG[81]) 
			player.invincible_time_left = 1 
			is_ult_buff_active = true
			ult_buff_duration_timer = 15.0
			ult_heal_timer = 2.0  
			ult_laser_timer = 1.0 
			
			if TALISMAN_VFX_SCENE:
				active_ult_buff_vfx = TALISMAN_VFX_SCENE.instantiate()
				player.add_child(active_ult_buff_vfx)
				active_ult_buff_vfx.position = Vector2(0, -30)
				if active_ult_buff_vfx.has_node("AnimationPlayer"): active_ult_buff_vfx.get_node("AnimationPlayer").play("ult_buff_loop")
			
			_tsubame_zoom_phase = 0
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.4)
			player.animation_player.speed_scale = 1.0 
			if player.has_method("clear_time_stop"): player.clear_time_stop()
			return false

		player.is_input_locked = false
		is_attacking = false
		step_cooldown = 0.0
		last_attack_time = Time.get_ticks_msec() / 1000.0
		
		if combo_step == 60: air_attack_locked = true 
		_is_hitbox_locked = true 
		disable_hitbox()
		
		# 🌟 核心修復：招式播完，沒收武藝卡帶控制權
		if is_instance_valid(active_martial_art):
			active_martial_art.is_active = false
			active_martial_art = null
			
		var p_scabbard = player.get("scabbard")
		if not requires_sheath() and p_scabbard: p_scabbard.fade_in()
		return true
		
	return false

func cancel_attack() -> void:
	if is_instance_valid(active_martial_art):
		active_martial_art.cancel()
		active_martial_art = null

	if not player.is_on_floor() and combo_step == 60: air_attack_locked = true
	player.is_input_locked = false
	is_attacking = false
	combo_step = 0
	step_cooldown = 0.0
	is_vfx_fired = false
	is_tower_spawned = false 
	_is_hitbox_locked = true 
	
	if is_time_stop_triggered or _tsubame_zoom_phase > 0:
		is_time_stop_triggered = false
		_tsubame_zoom_phase = 0
		_apply_charge_zoom(ZOOM_LEVELS[0], 0.0)
		player.animation_player.speed_scale = 1.0
		if player.has_method("clear_time_stop"): player.clear_time_stop()
	
	disable_hitbox()
	var p_scabbard = player.get("scabbard")
	if p_scabbard: p_scabbard.fade_in()

# ==========================================
# ⚙️ 特效與子彈生成器接口 (外包組件相容版)
# ==========================================
func _spawn_weapon_vfx(config: Dictionary) -> void:
	if not TALISMAN_VFX_SCENE: return
	var vfx = TALISMAN_VFX_SCENE.instantiate()
	vfx.global_position = player.global_position + Vector2(30 * player.direction, -30)
	vfx.scale.x = player.direction
	vfx.z_index = player.z_index + 1
	get_tree().current_scene.add_child(vfx) 
	
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var vfx_anim_name = config.get("vfx_anim", "")
	if vfx.has_method("play_and_free") and vfx_anim_name != "": vfx.play_and_free(vfx_anim_name, speed_mult)

func _spawn_healing_tower() -> void:
	if not HEALING_TOWER_SCENE: return
	var tower = HEALING_TOWER_SCENE.instantiate()
	tower.global_position = player.global_position + Vector2(player.direction, 0)
	if "direction" in tower: tower.direction = player.direction   
	tower.scale.x = player.direction
	
	# 🌟 就是少了這行！讓塔顯示在前景，不會被背景圖片吃掉
	tower.z_index = 1
	
	get_tree().current_scene.add_child(tower)

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
	laser.scale = Vector2.ONE * config.get("laser_scale", 1.0)
	laser.is_tracking = config.get("laser_tracking", true)
	get_tree().current_scene.add_child(laser)
	
	await get_tree().process_frame
	if not is_instance_valid(laser) or not laser.hitbox: return
	
	laser.hitbox.damage_amount = config.get("laser_dmg", config.get("base_dmg", 160))
	laser.hitbox.hit_sfx_type = "hit"
	laser.hitbox.max_hits = 1
	laser.hitbox.attack_type = config.get("laser_type", config.get("type", Damage.Type.LIGHT))
	if "knockback_force" in laser.hitbox: laser.hitbox.knockback_force = config.get("laser_knockback", config.get("knockback", Vector2.ZERO))
	if "shake_intensity" in laser.hitbox:
		laser.hitbox.shake_intensity = config.get("laser_shake", config.get("shake", 0.0))
		laser.hitbox.shake_on_hit_only = true
	
	laser.hitbox.spark_color = Color(0.8, 0.3, 1.0, 1.0) 
	laser.hitbox.aura_color = Color(0.0, 0.5, 1.0, 1.0)
	
	var w_energy = float(config.get("energy", 0))
	var wave_state = [false]
	laser.hitbox.hit.connect(func(hurtbox: Node):
		if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: return
		if not wave_state[0]:
			if w_energy > 0 and player.has_method("add_weapon_resource"): player.add_weapon_resource(WEAPON_ID, w_energy)
			wave_state[0] = true
	)

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
		
		# ==========================================
		# 🌟 被我偷刪的專屬紫色火花與清空判定，完璧歸趙！
		# ==========================================
		hitbox.spark_type = 0
		hitbox.spark_scale = 0.3
		hitbox.spark_color = Color(0.8, 0.3, 1.0, 1.0)
		hitbox.aura_color = Color(0.0, 0.5, 1.0, 1.0)
		hitbox.hit_targets.clear()
		
		_current_energy_reward = float(config.get("energy", 0))
		_current_charge_reward = int(config.get("charge_reward", 0)) 
		_multi_hit_energy = config.get("multi_hit_energy", false)
		_has_granted_resources_this_step = false
		
		if current_active_hitbox and current_active_hitbox.hit.is_connected(_on_hitbox_hit): current_active_hitbox.hit.disconnect(_on_hitbox_hit)
		current_active_hitbox = hitbox 
		if not current_active_hitbox.hit.is_connected(_on_hitbox_hit): current_active_hitbox.hit.connect(_on_hitbox_hit)
			
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

# ==========================================
# 🎯 命中回饋處理 (由 Hitbox 信號觸發)
# ==========================================
func _on_hitbox_hit(hurtbox: Node) -> void:
	# 防呆：確保不是打到玩家自己
	if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: 
		return

	# 判斷是否為多次給予，或者這招還沒給過資源
	if _multi_hit_energy or not _has_granted_resources_this_step:
		if _current_charge_reward > 0:
			gain_talisman_charge(_current_charge_reward)
			
		# 🌟 核心修復：只傳兩個參數 (WEAPON_ID, energy) 預防當機
		if _current_energy_reward > 0:
			if player.has_method("add_weapon_resource"):
				player.add_weapon_resource(WEAPON_ID, _current_energy_reward)
				
		_has_granted_resources_this_step = true
		
# ==========================================
# 🛡️ 狀態機防護網
# ==========================================
func can_use_heavy() -> bool:
	if not player.is_on_floor(): return false
	if skill_1_timer > 0:
		print("⏳ [防護網攔截] 符咒中立戰技冷卻中！")
		return false
	return true

func can_use_ultimate() -> bool:
	if ult_timer > 0: return false 
	if not player.is_on_floor(): return false 
	if player.has_method("get_weapon_energy"):
		if player.get_weapon_energy(WEAPON_ID) < ult_energy_cost: return false 
	return true

func _apply_charge_zoom(target_zoom: Vector2, duration: float = 0.2) -> void:
	if not (player is Player): return
	var camera = get_viewport().get_camera_2d()
	if camera:
		if _camera_tween and _camera_tween.is_valid(): _camera_tween.kill()
		_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if target_zoom == ZOOM_LEVELS[0]:
			var final_zoom = CombatManager.base_zoom if CombatManager.get("base_zoom") != null else Vector2(1.0, 1.0)
			_camera_tween.tween_property(camera, "zoom", final_zoom, duration)
			_camera_tween.tween_callback(func(): if CombatManager.get("is_close_up_active") != null: CombatManager.is_close_up_active = false)
		else:
			if CombatManager.get("is_close_up_active") != null: CombatManager.is_close_up_active = true
			_camera_tween.tween_property(camera, "zoom", target_zoom, duration)

func _get_ground_distance() -> float:
	var space_state = player.get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(player.global_position, player.global_position + Vector2(0, 1000))
	query.collision_mask = 1 
	var result = space_state.intersect_ray(query)
	return player.global_position.distance_to(result.position) if result else 1000.0 

func requires_sheath() -> bool:
	if combo_step == 0: return false
	return combo_step not in no_sheath_steps
	
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
