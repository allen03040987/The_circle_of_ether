class_name Spear
extends Weapon
## 武器腳本：長槍 (Spear) - 強化普攻(30)回歸版

const WEAPON_ID: String = "spear"

const SPEAR_WAVE_SCENE = preload("res://player/Spear/ult_wave.tscn") 
const ZOOM_LEVELS = { 0: Vector2(1.0, 1.0), 1: Vector2(1.05, 1.05), 2: Vector2(1.1, 1.1), 3: Vector2(1.15, 1.15) }

# ==========================================
# 🥋 專屬武藝系統 (Martial Arts Loadout)
# ==========================================
@export var equipped_martial_arts: Array[String] = [
	"res://player/MartialArts/Spear/Art_Spear_22.gd", 
	"res://player/MartialArts/Spear/Art_Spear_21.gd", 
	""
]

func _ready() -> void:
	super._ready()
	call_deferred("_delayed_load_arts")

func _delayed_load_arts() -> void:
	load_martial_arts(equipped_martial_arts)

# ==========================================
# 📖 招式數據庫 (Data-Driven Combat Config)
# ==========================================
const LIGHT_ATTACK_CONFIG = {
	1: {"anim": "spear/attack_1", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(50.0, 0.0), "base_dmg": 300, "energy": 500, "pozhen": 10, "action_type": Weapon.ActionType.NORMAL,"hit_sfx_type": "hit"},
	2: {"anim": "spear/attack_2", "hitbox_name": "Hitbox", "max_hits": 2, "interval": 0.1, "knockback": Vector2(50.0, 0.0), "base_dmg": 350, "energy": 5, "pozhen": 10, "action_type": Weapon.ActionType.NORMAL,"hit_sfx_type": "hit"},
	3: {"anim": "spear/attack_3", "hitbox_name": "Hitbox", "max_hits": 3, "interval": 0.1, "knockback": Vector2(20.0, 0.0), "base_dmg": 150, "energy": 5, "pozhen": 10, "action_type": Weapon.ActionType.NORMAL,"hit_sfx_type": "hit"},
	4: {"anim": "spear/attack_4", "hitbox_name": "Hitbox", "max_hits": 1, "interval": 0.0, "knockback": Vector2(600.0, 0.0), "shake": 20.0, "base_dmg": 600, "energy": 10, "pozhen": 10, "action_type": Weapon.ActionType.NORMAL,"hit_sfx_type": "hit"}
}

const SKILL_CONFIG = {
	20: {"anim": "spear/c1", "hitbox_name": "None", "max_hits": 1, "interval": 0.0, "knockback": Vector2.ZERO, "base_dmg": 0, "energy": 0, "hit_sfx_type": "hit"},
	21: {"anim": "spear/c2", "hitbox_name": "C2", "type": Damage.Type.HEAVY, "max_hits": 5, "interval": 0.15, "knockback": Vector2(220.0, -200.0), "pull": true, "shake": 15.0, "base_dmg": 50, "energy": 3, "pozhen": 10, "sticky": true,"hit_sfx_type": "hit"},
	22: {"anim": "spear/c3", "hitbox_name": "C3", "type": Damage.Type.HEAVY, "max_hits": 1, "interval": 0.0, "knockback": Vector2(0.0, -600.0), "shake": 60.0, "base_dmg": 500, "energy": 10, "pozhen": 10,"hit_sfx_type": "hit_2"},
	30: {"anim": "spear/attack_enhanced", "hitbox_name": "attack_enhanced", "type": Damage.Type.HEAVY, "max_hits": 4, "interval": 0.1, "knockback": Vector2(100.0, -100.0), "shake": 15.0, "base_dmg": 800, "energy": 10, "pozhen": 0, "action_type": Weapon.ActionType.NORMAL, "sticky": true,"hit_sfx_type": "hit"},
	80: {"anim": "spear/attack_ult", "hitbox_name": "None", "max_hits": 1, "interval": 0.0, "knockback": Vector2.ZERO, "base_dmg": 0, "energy": 0},
	81: {"anim": "spear/attack_ult_end", "hitbox_name": "None", "max_hits": 1, "interval": 0.0, "knockback": Vector2.ZERO, "base_dmg": 0, "energy": 0}
}

const AIR_ATTACK_CONFIG = {
	61: { "anim": "spear/air_attack_1", "hitbox_name": "Air_J", "max_hits": 4, "interval": 0.15, "shake": 10.0, "type": Damage.Type.LIGHT, "knockback": Vector2(10.0, -150.0), "base_dmg": 50, "energy": 1, "pozhen": 10, "action_type": Weapon.ActionType.NORMAL, "sticky": true,"hit_sfx_type": "hit"},
	62: { "anim": "spear/air_attack_2", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "shake": 50.0, "type": Damage.Type.HEAVY, "knockback": Vector2(300.0, 600.0), "base_dmg": 300, "energy": 2, "pozhen": 10, "action_type": Weapon.ActionType.NORMAL,"hit_sfx_type": "hit"},
}

# ==========================================
# 🎛️ 內部狀態變數
# ==========================================
@export_group("空戰設定 (Air Combat)")
@export var min_air_attack_height: float = 40.0 
@export var air_thrust_force: float = -150.0    
var air_attack_locked: bool = false 

var is_spear_thrown: bool = false 
const BOOMERANG_SCENE = preload("res://player/Spear/SpearBoomerang.tscn")

var is_time_stop_triggered: bool = false 
var _ult_zoom_phase: int = 0 
var _camera_tween: Tween
var is_wave_fired: bool = false 

# 🌟 裝回長按計時器
var light_hold_timer: float = 0.0

var _current_energy_reward: float = 0.0
var _current_pozhen_reward: int = 0
var _multi_hit_energy: bool = false
var _has_granted_resources_this_step: bool = false

var current_pozhen: int = 0
const MAX_POZHEN: int = 40

@export var ult_energy_cost: float = 100.0  
const ULT_DURATION: float = 30.0            
const MAX_ULT_ATTACKS: int = 24             

var is_ult_active: bool = false             
var ult_buff_timer: float = 0.0             
var ult_attack_count: int = 0               

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
	air_attack_locked = false
	
	if not player.is_on_floor():
		if air_attack_locked or _get_ground_distance() < min_air_attack_height:
			is_attacking = false
			return
			
		if combo_step == 30:
			is_attacking = false
			return
			
		if combo_step == 61:
			combo_step = 62
			air_attack_locked = true 
		else:
			combo_step = 61
			
		step_cooldown = 0.15
		is_attacking = true
		
		var input_dir = Input.get_axis("move_left", "move_right")
		if not is_zero_approx(input_dir) and player is Player:
			player.direction = 1 if input_dir > 0 else -1
			
		_play_air_step(combo_step)
		return
	
	step_cooldown = 0.15
	
	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time > combo_timeout:
			combo_step = 0
			
	if is_ult_active:
		combo_step = 3 
		ult_attack_count += 1
		
		if ult_attack_count >= MAX_ULT_ATTACKS:
			is_ult_active = false
			ult_buff_timer = 0.0
	else:
		combo_step += 1
		if not LIGHT_ATTACK_CONFIG.has(combo_step): 
			combo_step = 1
	
	is_attacking = true
	_play_attack(LIGHT_ATTACK_CONFIG[combo_step])
	
	# 🌟 裝回：蓄力預輸入補償
	if Input.is_action_pressed("attack"): light_hold_timer = 0.15
	else: light_hold_timer = 0.0
	
func start_heavy_attack() -> void:
	if step_cooldown > 0: return
	
	if not player.is_on_floor():
		is_attacking = false
		return
	
	step_cooldown = 0.15
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1
	
	is_attacking = true
	is_spear_thrown = false 
	
	combo_step = 20 
	_play_attack(SKILL_CONFIG[combo_step])
	print("🪃 丟出迴旋鏢 (Skill 1)！")
		
func start_ultimate() -> void:
	if player.has_method("consume_weapon_energy"):
		player.consume_weapon_energy(WEAPON_ID, ult_energy_cost)
		
	step_cooldown = 0.15
	is_attacking = true
	combo_step = 80
	air_attack_locked = false 
	
	player.invincible_time_left = 3.0 
	
	is_time_stop_triggered = false 
	_ult_zoom_phase = 0 
	is_wave_fired = false
	
	is_ult_active = true
	ult_buff_timer = ULT_DURATION
	ult_attack_count = 0
	
	_play_attack(SKILL_CONFIG[combo_step])
	player.is_input_locked = true 
	
func can_use_ultimate() -> bool:
	if is_ult_active: return false 
	if not player.is_on_floor(): return false 
	if player.has_method("get_weapon_energy"):
		if player.get_weapon_energy(WEAPON_ID) < ult_energy_cost:
			return false 
	return true
	
# ==========================================
# 💾 武器狀態保存與繼承
# ==========================================
func export_weapon_data() -> Dictionary:
	return {
		"current_pozhen": current_pozhen,
		"is_ult_active": is_ult_active,
		"ult_buff_timer": ult_buff_timer,
		"ult_attack_count": ult_attack_count,
	}

func import_weapon_data(data: Dictionary) -> void:
	current_pozhen = data.get("current_pozhen", 0)
	is_ult_active = data.get("is_ult_active", false)
	ult_buff_timer = data.get("ult_buff_timer", 0.0)
	ult_attack_count = data.get("ult_attack_count", 0)
	
# ==========================================
# ⏱️ 物理與系統計時器 
# ==========================================
func update_timers_only(delta: float) -> void:
	if step_cooldown > 0: 
		step_cooldown -= delta
		
	if ult_buff_timer > 0:
		ult_buff_timer -= delta
		if ult_buff_timer <= 0 and is_ult_active:
			is_ult_active = false
	
	if player.is_on_floor():
		air_attack_locked = false 
		if not is_attacking and combo_step in [61, 62]:
			combo_step = 0
			
func get_current_velocity(delta: float) -> Vector2:
	# 🌟 攔截器：如果有武藝在執行，物理位移全權交給它算！
	if is_instance_valid(active_martial_art) and active_martial_art.is_active:
		return active_martial_art.get_current_velocity(delta)

	if not is_attacking: return player.velocity
	if player.is_on_floor(): air_attack_locked = false 
	
	var new_x = player.velocity.x
	var new_y = player.velocity.y

	# 🌟 裝回：長按計時器推進
	if Input.is_action_pressed("attack"):
		light_hold_timer += delta
	else:
		light_hold_timer = 0.0

	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# ==========================================
	# 🌟 裝回：長按普攻轉強化普攻 (30)
	# ==========================================
	if combo_step in [1, 2, 3, 4, 61, 62]:
		if current_pozhen >= 40 and light_hold_timer >= 0.35:
			var can_cb = player.get("can_combo") if "can_combo" in player else true
			if can_cb:
				var input_dir = Input.get_axis("move_left", "move_right")
				if input_dir != 0 and player is Player:
					player.direction = 1 if input_dir > 0 else -1
				
				current_pozhen -= 40
				combo_step = 30 
				light_hold_timer = 0.0
				
				if not player.is_on_floor():
					air_attack_locked = true
					
				_play_attack(SKILL_CONFIG[30])
				print("🔥 長按觸發！發動強化普攻！")

	# --- 摩擦力減速邏輯 ---
	if combo_step in [1, 2, 3, 4, 30]: # 🌟 把 21 拿掉，換成 30
		new_x = move_toward(new_x, 0.0, base_friction)
		
	# 🌟 空戰慣性滑行與微浮空
	elif combo_step in [61, 62]:
		new_x = move_toward(new_x, 0.0, base_friction)
		
		if combo_step == 61 and not player.is_on_floor():
			if new_y > 0: new_y = 0.0
			new_y += (player.default_gravity * 0.6) * delta
			if new_y > 50.0: new_y = 50.0
			
	# 戰技 20：丟出迴旋鏢
	elif combo_step == 20:
		new_x = move_toward(new_x, 0.0, base_friction)
		
		var anim_time = player.animation_player.current_animation_position
		if anim_time >= 0.15 and not is_spear_thrown:
			is_spear_thrown = true
			spawn_boomerang()
			
	# ----------------------------------------
	# 🌌 大招前半段 (80)
	# ----------------------------------------
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
			
		if anim_time >= 0.05 and _ult_zoom_phase == 0:
			_ult_zoom_phase = 1
			_apply_charge_zoom(Vector2(1.5, 1.5), 0.3) 
			
		if anim_time >= 0.70 and _ult_zoom_phase == 1:
			_ult_zoom_phase = 2
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(30.0, 0.1)

	# ----------------------------------------
	# 🌌 大招後半段 (81)
	# ----------------------------------------
	elif combo_step == 81: 
		new_x = move_toward(new_x, 0.0, base_friction * 5.0)
		new_y = 0.0 
		player.invincible_time_left = 0.6 
		
		var anim_time = player.animation_player.current_animation_position
		if anim_time >= 0.05 and not is_wave_fired:
			is_wave_fired = true
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(150.0, 0.15) 
			spawn_spear_wave("ult_wave")
			
	else:
		new_x = move_toward(new_x, 0.0, base_friction)
			
	return Vector2(new_x, new_y)

func is_handling_gravity() -> bool:
	if is_instance_valid(active_martial_art) and active_martial_art.is_active:
		if active_martial_art.has_method("is_handling_gravity"):
			return active_martial_art.is_handling_gravity()

	if combo_step in [30, 61] and not player.is_on_floor(): return true  # 🌟 裝回 30 的滯空
	if combo_step in [80, 81]: return true
	return false
	
func requires_sheath() -> bool:
	if combo_step == 0: return false
	return combo_step not in no_sheath_steps

func gain_pozhen(amount: int) -> void:
	if amount <= 0: return
	if try_forward_resource("gain_pozhen", amount): return
		
	current_pozhen = mini(current_pozhen + amount, MAX_POZHEN)
	print("🟢 命中！獲得破陣值: ", amount, " | 目前破陣: ", current_pozhen, "/", MAX_POZHEN)
	
func _play_attack(config: Dictionary) -> void:
	_is_hitbox_locked = false 
	disable_hitbox()
	
	current_action_type = config.get("action_type", Weapon.ActionType.NONE)
	
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
		
		_current_energy_reward = float(config.get("energy", 0))
		_current_pozhen_reward = int(config.get("pozhen", 0))
		_multi_hit_energy = config.get("multi_hit_energy", false)
		_has_granted_resources_this_step = false
		
		if current_active_hitbox and current_active_hitbox.hit.is_connected(_on_hitbox_hit):
			current_active_hitbox.hit.disconnect(_on_hitbox_hit)
			
		current_active_hitbox = hitbox 
		
		if not current_active_hitbox.hit.is_connected(_on_hitbox_hit):
			current_active_hitbox.hit.connect(_on_hitbox_hit)
		
		hitbox.spark_type = 0
		hitbox.spark_scale = 0.3
		hitbox.spark_color = Color(1.0, 0.4, 0.2, 1.0)
		hitbox.aura_color = Color(1.0, 0.6, 0.2, 1.0)
		
		hitbox.hit_targets.clear()
		current_active_hitbox = hitbox 
	
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])
	
func _on_hitbox_hit(hurtbox: Node) -> void:
	if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: 
		return

	if _multi_hit_energy or not _has_granted_resources_this_step:
		if _current_pozhen_reward > 0:
			gain_pozhen(_current_pozhen_reward)
			
		if _current_energy_reward > 0:
			if player.has_method("add_weapon_resource"):
				player.add_weapon_resource(WEAPON_ID, _current_energy_reward)
				
		_has_granted_resources_this_step = true
		
func _play_air_step(step: int) -> void:
	var config: Dictionary = AIR_ATTACK_CONFIG[step]
	_play_attack(config) 
	player.velocity.y = air_thrust_force 

func _get_ground_distance() -> float:
	var space_state = player.get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(player.global_position, player.global_position + Vector2(0, 1000))
	query.collision_mask = 1 
	var result = space_state.intersect_ray(query)
	if result: return player.global_position.distance_to(result.position)
	return 1000.0
	
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

func is_attack_finished() -> bool:
	if not is_attacking: return true
	
	if not player.animation_player.is_playing():
		if combo_step == 80:
			combo_step = 81
			if player.has_method("clear_time_stop"): 
				player.clear_time_stop()
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.15)
			_ult_zoom_phase = 0 
			is_time_stop_triggered = false
			player.invincible_time_left = 1.0 
			_play_attack(SKILL_CONFIG[81])
			return false
			
		# ==========================================
		# 🌟 裝回：破陣值無縫預輸入 (Hold-to-Chain)
		# ==========================================
		if Input.is_action_pressed("attack"):
			if combo_step in [1, 2, 3, 4, 20, 22, 61, 62]: # 🌟 21 被拔除了
				if current_pozhen >= 40 and light_hold_timer >= 0.2:
					var input_dir = Input.get_axis("move_left", "move_right")
					if input_dir != 0:
						player.direction = 1 if input_dir > 0 else -1
						
					current_pozhen -= 40
					combo_step = 30 
					light_hold_timer = 0.0
					
					if not player.is_on_floor():
						air_attack_locked = true
						
					_play_attack(SKILL_CONFIG[30])
					print("🔥 動畫結束無縫銜接！轉向並發動強化普攻！")
					return false 
		
		player.is_input_locked = false 
		if combo_step in [61, 62] or (combo_step == 30 and not player.is_on_floor()): # 🌟 裝回 30 的空中鎖死
			air_attack_locked = true
		
		if combo_step == 81 or _ult_zoom_phase > 0:
			_ult_zoom_phase = 0
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.4)
			if player.has_method("clear_time_stop"): player.clear_time_stop()
			
		step_cooldown = 0.0
		last_attack_time = Time.get_ticks_msec() / 1000.0 
		
		_is_hitbox_locked = true 
		disable_hitbox()
		
		if is_instance_valid(active_martial_art):
			active_martial_art.is_active = false
			active_martial_art = null
		
		if not requires_sheath() and player.get("scabbard"):
			player.scabbard.fade_in()
		return true
		
	return false

func cancel_attack() -> void:
	if is_instance_valid(active_martial_art):
		active_martial_art.cancel()
		active_martial_art = null

	if not player.is_on_floor() and combo_step in [30, 61, 62]: # 🌟 裝回 30 的空中鎖死
		air_attack_locked = true
	player.is_input_locked = false
	is_attacking = false
	combo_step = 0
	step_cooldown = 0.0
	light_hold_timer = 0.0 # 🌟 裝回打斷時清空計時器
	_is_hitbox_locked = true 
	disable_hitbox()
	
	is_wave_fired = false 
	_ult_zoom_phase = 0 
	
	if is_time_stop_triggered:
		is_time_stop_triggered = false
		if player.has_method("clear_time_stop"): player.clear_time_stop() 
	
	if player.get("scabbard"):
		player.scabbard.fade_in()
		
	_apply_charge_zoom(ZOOM_LEVELS[0])

func _apply_charge_zoom(target_zoom: Vector2, duration: float = 0.2) -> void:
	if not (player is Player): return
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
			wave.speed = 800.0
			wave.max_distance = 800.0
			wave.scale = Vector2(3.0 * player.direction, 3.0) 
			
			wave.hitbox.damage_amount = 800 
			wave.hitbox.absolute_knockback = Vector2(800.0 * player.direction, 0.0)
			wave.hitbox.knockback_force = Vector2(0.0, -500.0)
			wave.hitbox.attack_type = Damage.Type.HEAVY
			
			wave.hitbox.spark_type = 0
			wave.hitbox.spark_scale = 1.0
			wave.hitbox.spark_color = Color(1.0, 0.8, 0.2, 1.0) 
			wave.hitbox.aura_color = Color(1.0, 0.5, 0.0, 1.0)
			wave.hitbox.hit_sfx_type = "hit_4"

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
	var w_pozhen = 10
	var b_state = [false] 
	
	boomerang.hitbox.hit.connect(func(hurtbox: Node):
		if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: return
		if not b_state[0]:
			gain_pozhen(w_pozhen)
			if player.has_method("add_weapon_resource"):
				player.add_weapon_resource(WEAPON_ID, w_energy)
			b_state[0] = true
	)
	
	boomerang.hitbox.spark_type = 0
	boomerang.hitbox.spark_scale = 0.4  
	boomerang.hitbox.spark_color = Color(1.2, 1.5, 0.5, 1.0)
	boomerang.hitbox.aura_color = Color(0.8, 0.5, 0.2, 1.0)
	
func can_air_light() -> bool: 
	if current_pozhen >= 40: return true 
	if air_attack_locked or _get_ground_distance() < min_air_attack_height: 
		return false
	return true
	
func can_air_skill() -> bool: return false

func can_use_heavy() -> bool:
	if not player.is_on_floor(): return false
	return true
