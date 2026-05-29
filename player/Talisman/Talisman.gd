class_name Talisman
extends Weapon
## 武器腳本：符咒 (Talisman)

const WEAPON_ID: String = "talisman"

# ==========================================
# 🎛️ 1. 武器核心參數與資源
# ==========================================
@export_group("武器核心參數")
@export var combo_timeout: float = 0.3      
@export var no_sheath_steps: Array[int] = [] 
@export var ult_energy_cost: float = 100.0  

const TALISMAN_VFX_SCENE = preload("res://player/Talisman/TalismanVFX.tscn")
const HEALING_TOWER_SCENE = preload("res://player/Talisman/HealingTower.tscn") 
const TRUE_PROJ_SCENE = preload("res://player/Talisman/TrueProjectile.tscn") 

# ==========================================
# 📖 2. 招式數據庫 (Data-Driven Combat Config)
# ==========================================
const LIGHT_ATTACK_CONFIG = {
	1: {
		"anim": "talisman/attack_1", "hitbox_name": "Hitbox", 
		"base_dmg": 100, "energy": 5, "switch": 5, "charge_reward": 0,
		"vfx_anim": "a1", "vfx_fly_dist": 0.0 
	},
	2: {
		"anim": "talisman/attack_2", "hitbox_name": "Hitbox", 
		"base_dmg": 120, "energy": 5, "switch": 5, "charge_reward": 0,
		"vfx_anim": "a2", "vfx_fly_dist": 0.0 
	},
	3: {
		"anim": "talisman/attack_3", "hitbox_name": "Hitbox", 
		"base_dmg": 40, "energy": 2, "switch": 2,        
		"max_hits": 3, "interval": 0.1, "sticky": true, 
		"vfx_anim": "a3", "shake": 7.0,
		"charge_reward": 10,    
		"vfx_fly_dist": 0.0 
	}
}

const SKILL_CONFIG = {
	20: {
		"anim": "talisman/c1", "hitbox_name": "C0", 
		"base_dmg": 50, "energy": 5, "switch": 10, "charge_reward": 10, 
		"max_hits": 5, "interval": 0.1, "sticky": true,                 
		"vfx_anim": "c0", "vfx_fly_dist": 0.0 
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
var air_attack_locked: bool = false 

var combo_step: int = 0
var last_attack_time: float = 0.0
var is_attacking: bool = false
var step_cooldown: float = 0.0

var is_vfx_fired: bool = false 
var is_tower_spawned: bool = false 

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
	
	combo_step += 1
	if not LIGHT_ATTACK_CONFIG.has(combo_step): combo_step = 1
	
	_play_attack(LIGHT_ATTACK_CONFIG[combo_step])

func start_heavy_attack() -> void:
	if is_attacking and combo_step >= 20: return 
	
	if step_cooldown > 0:
		is_attacking = false
		return
		
	step_cooldown = 0.15
	is_attacking = true
	is_vfx_fired = false 
	is_tower_spawned = false 
	
	combo_step = 0 
	
	if player.is_on_floor():
		if Input.is_action_pressed("move_up"):
			pass # 預留戰技上
		elif Input.is_action_pressed("move_down"):
			pass # 預留戰技下
		else:
			combo_step = 20
			_play_attack(SKILL_CONFIG[combo_step])
			skill_1_timer = skill_1_cd

func update_timers_only(delta: float) -> void:
	if step_cooldown > 0: step_cooldown -= delta
	if skill_1_timer > 0: skill_1_timer -= delta 
	if skill_2_timer > 0: skill_2_timer -= delta 
	if skill_3_timer > 0: skill_3_timer -= delta 
	if ult_timer > 0: ult_timer -= delta
	
	if player.is_on_floor():
		air_attack_locked = false 

# ==========================================
# 🏃 物理與特效場控核心
# ==========================================
func get_current_velocity(delta: float) -> Vector2:
	if not is_attacking: return player.velocity
	
	if player.is_on_floor(): air_attack_locked = false
	
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	
	var anim_time = player.animation_player.current_animation_position
	
	# ----------------------------------------
	# 物理摩擦力分流 (對齊太刀與長槍)
	# ----------------------------------------
	if combo_step in [1, 2, 3]:
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		
		if anim_time >= 0.1 and not is_vfx_fired:
			is_vfx_fired = true
			_spawn_weapon_vfx(LIGHT_ATTACK_CONFIG[combo_step]) # 🌟 拔除防護網，殘影必須發射特效！
				
	elif combo_step == 20:
		new_x = move_toward(new_x, 0.0, player.FLOOR_ACCELERATION * delta)
		
		if anim_time >= 0.1 and not is_vfx_fired:
			is_vfx_fired = true
			_spawn_weapon_vfx(SKILL_CONFIG[combo_step]) # 🌟 拔除防護網，殘影必須發射特效！
				
		if anim_time >= 1.15 and not is_tower_spawned:
			is_tower_spawned = true
			
			# 🌟 鏡頭震動防護 (完全對齊太刀劍氣寫法，殘影不准震動鏡頭)
			if not player.name.begins_with("Phantom"): 
				if CombatManager.has_method("apply_camera_shake"): 
					CombatManager.apply_camera_shake(50.0)
			
			_spawn_healing_tower() # 🌟 拔除防護網，讓代打的殘影把塔蓋出來！
				
		# 🌟 玩家無敵防護 (只有本體才需要無敵，殘影不需要)
		if not player.name.begins_with("Phantom"):
			if anim_time >= 0.0 and anim_time <= 1.0:
				player.invincible_time_left = max(player.invincible_time_left, 0.1) 
			elif anim_time > 1.0 and anim_time < 1.1:
				if player.invincible_timer.time_left == 0:
					player.invincible_time_left = 0.0
					
	return Vector2(new_x, new_y)

func _spawn_weapon_vfx(config: Dictionary) -> void:
	if not TALISMAN_VFX_SCENE: return
	
	var vfx = TALISMAN_VFX_SCENE.instantiate()
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = player.global_position + Vector2(30 * player.direction, -30)
	vfx.scale.x = player.direction
	vfx.z_index = player.z_index + 1
	
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
	get_tree().current_scene.add_child(tower)
	tower.global_position = player.global_position + Vector2(40 * player.direction, 0)
	tower.z_index = 1
	print("✨ [符咒] 釋放中立戰技，已生成回血塔！")

# ==========================================
# ⚙️ 內部實作與 Hitbox 屬性灌注 (對齊長槍防呆寫法)
# ==========================================
func _play_attack(config: Dictionary) -> void:
	_is_hitbox_locked = false 
	disable_hitbox()
	
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
		hitbox.spark_color = Color(0.2, 0.8, 1.5, 1.0)
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
		
		_is_hitbox_locked = true 
		disable_hitbox()
		
		var p_scabbard = player.get("scabbard")
		if not requires_sheath() and p_scabbard:
			p_scabbard.fade_in()
			
		return true
	return false

func cancel_attack() -> void:
	# 🌟 統一使用 begins_with 對齊太刀
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
	disable_hitbox()
	
	var p_scabbard = player.get("scabbard")
	if p_scabbard: 
		p_scabbard.fade_in()

func requires_sheath() -> bool:
	if combo_step == 0:
		return false
	return combo_step not in no_sheath_steps

# ==========================================
# 🛡️ 狀態機防護名單 (The Bouncer's List)
# ==========================================
func can_air_light() -> bool:
	if air_attack_locked or _get_ground_distance() < min_air_attack_height: return false
	return true

func can_use_heavy() -> bool:
	if not player.is_on_floor(): return false
	
	if Input.is_action_pressed("move_up"):
		pass 
	elif Input.is_action_pressed("move_down"):
		pass 
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
		"skill_1_timer": skill_1_timer if "skill_1_timer" in self else 0.0,
		"skill_2_timer": skill_2_timer if "skill_2_timer" in self else 0.0,
		"skill_3_timer": skill_3_timer if "skill_3_timer" in self else 0.0,
		"ult_timer": ult_timer if "ult_timer" in self else 0.0
	}

func import_weapon_data(data: Dictionary) -> void:
	current_talisman_charge = data.get("current_talisman_charge", 0)
	if "skill_1_timer" in self: skill_1_timer = data.get("skill_1_timer", 0.0)
	if "skill_2_timer" in self: skill_2_timer = data.get("skill_2_timer", 0.0)
	if "skill_3_timer" in self: skill_3_timer = data.get("skill_3_timer", 0.0)
	if "ult_timer" in self: ult_timer = data.get("ult_timer", 0.0)
	
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
