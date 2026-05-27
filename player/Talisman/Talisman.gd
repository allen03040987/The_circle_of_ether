class_name Talisman
extends Weapon
## 武器腳本：符咒 (Talisman)

const WEAPON_ID: String = "talisman"

# 🌟 武器自己管理專屬的美術資源，絕對不污染全局 VFX 字典！
const TALISMAN_VFX_SCENE = preload("res://player/Talisman/TalismanVFX.tscn")
const TRUE_PROJ_SCENE = preload("res://player/Talisman/TrueProjectile.tscn") # 留給重擊的真投射物

# ==========================================
# 📖 招式數據庫 (加入專屬視覺設定)
# ==========================================
const LIGHT_ATTACK_CONFIG = {
	# A1: 原地靜止的符咒
	1: {
		"anim": "talisman/attack_1", "hitbox_name": "Hitbox", 
		"base_dmg": 100, "energy": 5, "switch": 5,
		"vfx_anim": "a1",    # VFX 要播的動畫
		"vfx_fly_dist": 0.0       # 飛行距離 0 = 原地不動
	},
	# A2: 往前飛行的符咒
	2: {
		"anim": "talisman/attack_2", "hitbox_name": "Hitbox", 
		"base_dmg": 120, "energy": 5, "switch": 5,
		"vfx_anim": "a2",     # VFX 要播的動畫
		"vfx_fly_dist": 0.0 
	}
}

var combo_step: int = 0
var is_attacking: bool = false
var step_cooldown: float = 0.0
var is_vfx_fired: bool = false # 防止同一段攻擊重複生成特效的鎖

var last_attack_time: float = 0.0
const COMBO_TIMEOUT: float = 0.3

# 專屬資源記憶體 (解耦 Hitbox 用)
var current_active_hitbox: Hitbox = null
var _current_energy_reward: float = 0.0
var _current_switch_reward: float = 0.0
var _has_granted_resources_this_step: bool = false
var _is_hitbox_locked: bool = false

func _ready() -> void:
	if owner != null:
		if not owner.is_node_ready(): await owner.ready
		player = owner

# ==========================================
# 🎬 實作 Weapon.gd 合約接口
# ==========================================
func start_light_attack() -> void:
	if step_cooldown > 0: return
	step_cooldown = 0.15
	is_attacking = true
	is_vfx_fired = false # 換招時解鎖
	
	combo_step += 1
	if not LIGHT_ATTACK_CONFIG.has(combo_step): combo_step = 1
	
	_play_attack(LIGHT_ATTACK_CONFIG[combo_step])

func start_heavy_attack() -> void:
	# ... (保留你原本的重擊真投射物邏輯)
	pass

# ==========================================
# 🏃 物理與專屬視覺生成
# ==========================================
func get_current_velocity(delta: float) -> Vector2:
	if not is_attacking: return player.velocity
	var new_x = move_toward(player.velocity.x, 0.0, player.FLOOR_ACCELERATION * delta)
	
	# 🌟 在合適的動畫幀生成專屬視覺符咒！
	if LIGHT_ATTACK_CONFIG.has(combo_step):
		var anim_time = player.animation_player.current_animation_position
		# 假設動畫播到 0.1 秒時，手已經揮出去了，此時生成符咒
		if anim_time >= 0.1 and not is_vfx_fired:
			is_vfx_fired = true
			_spawn_weapon_vfx(LIGHT_ATTACK_CONFIG[combo_step])
			
	return Vector2(new_x, player.velocity.y)

# 🌟 武器獨立的美術生成器 (輕量化 Node2D + Tween 飛行)
func _spawn_weapon_vfx(config: Dictionary) -> void:
	if not TALISMAN_VFX_SCENE: return
	
	var vfx = TALISMAN_VFX_SCENE.instantiate()
	# 🌟 脫離玩家層級，加到世界場景，這樣符咒就不會跟著玩家亂動
	get_tree().current_scene.add_child(vfx)
	
	# 決定生成位置 (稍微在玩家前方)
	vfx.global_position = player.global_position + Vector2(30 * player.direction, -30)
	vfx.scale.x = player.direction
	
	# ==========================================
	# 🌟 核心修復：把圖層設定為玩家的圖層 + 1
	# ==========================================
	# 假設你的玩家 Z-index 是 0 或更高，這裡強制讓 VFX 永遠在玩家上面一層
	vfx.z_index = player.z_index + 1
	
	# 抗時停倍率
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	
	# 呼叫我們寫在 TalismanVFX.gd 裡的方法來播動畫
	var vfx_anim_name = config.get("vfx_anim", "")
	if vfx.has_method("play_and_free") and vfx_anim_name != "":
		vfx.play_and_free(vfx_anim_name, speed_mult)
	
	# 🚀 輕量級飛行邏輯：如果字典有設定要飛 (A2)
	var fly_dist = config.get("vfx_fly_dist", 0.0)
	if fly_dist > 0.0:
		var target_pos = vfx.global_position + Vector2(fly_dist * player.direction, 0)
		var tween = create_tween()
		tween.set_speed_scale(speed_mult) # 飛行也能抗時停！
		# 花 0.3 秒平滑飛到目標位置
		tween.tween_property(vfx, "global_position", target_pos, 0.3).set_ease(Tween.EASE_OUT)

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
		hitbox.hit_interval = config.get("interval", 0.0)
		hitbox.knockback_force = config.get("knockback", Vector2.ZERO)
		hitbox.attack_type = config.get("type", Damage.Type.LIGHT)
		hitbox.hit_sfx_type = config.get("hit_sfx_type", "hit")
		
		# 符咒專屬火花 (例如靈能青藍色)
		hitbox.spark_type = 0
		hitbox.spark_scale = 0.3
		hitbox.spark_color = Color(0.2, 0.8, 1.5, 1.0)
		hitbox.aura_color = Color(0.0, 0.5, 1.0, 1.0)
		
		hitbox.hit_targets.clear()
		
		_current_energy_reward = float(config.get("energy", 0))
		_current_switch_reward = float(config.get("switch", 0))
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

	if not _has_granted_resources_this_step:
		if _current_energy_reward > 0 or _current_switch_reward > 0:
			if player.has_method("add_weapon_resource"):
				player.add_weapon_resource(WEAPON_ID, _current_energy_reward, _current_switch_reward)
				
		_has_granted_resources_this_step = true

# ==========================================
# 🎬 狀態機防呆與收招結算
# ==========================================
func is_handling_gravity() -> bool:
	return false

func is_attack_finished() -> bool:
	if not is_attacking: return true
	if not player.animation_player.is_playing():
		player.is_input_locked = false
		is_attacking = false
		step_cooldown = 0.0
		last_attack_time = Time.get_ticks_msec() / 1000.0 
		
		_is_hitbox_locked = true 
		disable_hitbox()
		return true
	return false

func cancel_attack() -> void:
	player.is_input_locked = false
	is_attacking = false
	combo_step = 0
	step_cooldown = 0.0
	is_vfx_fired = false
	_is_hitbox_locked = true 
	disable_hitbox()

func requires_sheath() -> bool:
	return false

func update_timers_only(delta: float) -> void:
	if step_cooldown > 0: step_cooldown -= delta

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
					
