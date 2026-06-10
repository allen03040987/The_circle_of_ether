class_name Hitbox
extends Area2D
## 萬用攻擊判定框 (Hitbox)
## 職責：宣告攻擊屬性、處理多段連擊計時、觸發打擊回饋 (VFX/Shake)，並廣播 hit 信號。
## 解耦：Hitbox 不再負責管理玩家的戰鬥資源，只負責大喊「我打中人了！」。

enum SparkType { SLASH, BLUNT, OTHER }

# ==========================================
# 🎛️ 1. 基礎攻擊屬性
# ==========================================
@export_group("基礎攻擊屬性")
@export var damage_amount: int = 1

@export var attack_type: Damage.Type = Damage.Type.LIGHT
@export var source_type: Damage.SourceType = Damage.SourceType.MELEE

@export var knockback_force: Vector2 = Vector2(150.0, 0.0)
@export var poise_damage: float = 1.0 
@export var pull_towards_owner: bool = false # 黑洞聚怪模式

var absolute_knockback: Vector2 = Vector2.ZERO 
@onready var base_damage: int = damage_amount

# ==========================================
# 🔄 2. 多段連擊與黏著打擊
# ==========================================
@export_group("多段連擊設定")
@export var max_hits: int = 1 
@export var hit_interval: float = 0.0 
@export var sticky_multi_hit: bool = false 

var hit_targets: Dictionary = {} # 記錄打到誰、次數、時間

# ==========================================
# 🧃 3. 打擊感與視覺特效
# ==========================================
@export_group("打擊回饋")
@export var hit_sfx_type: String = "" 
@export var hitstop_duration: float = 0.0 
@export var shake_intensity: float = 0.0  
@export var shake_on_hit_only: bool = true 
var _has_shaken_this_attack: bool = false 

@export_group("火花進階設定")
@export var spark_type: SparkType = SparkType.SLASH
@export var spark_base_offset: Vector2 = Vector2.ZERO
@export var attach_spark_to_victim: bool = true 
@export var spark_random_angle: float = 20.0
@export var spark_random_offset: Vector2 = Vector2(15.0, 15.0)
@export var spark_scale: float = 1.0
@export var spark_color: Color = Color.WHITE
@export var spark_raw_intensity: float = 2.0
@export var custom_spark_scene: PackedScene
@export var aura_color: Color = Color(1.0, 1.0, 1.0, 0.5) 

# 🌟 唯一的對外溝通管道
signal hit(hurtbox: Node)

# ==========================================
# ⚙️ 核心生命週期與黏著巡檢
# ==========================================
func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _process(_delta: float) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	var has_active_shape: bool = false
	
	if self.monitoring:
		for child in get_children():
			if (child is CollisionShape2D or child is CollisionPolygon2D) and not child.disabled:
				has_active_shape = true
				break
				
	# --- 處理空揮震動 ---
	if has_active_shape:
		if not shake_on_hit_only and not _has_shaken_this_attack and shake_intensity > 0:
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(shake_intensity)
			_has_shaken_this_attack = true 
	else:
		_has_shaken_this_attack = false
		
	# --- 非黏著攻擊結束清理 ---
	if not has_active_shape and not sticky_multi_hit:
		hit_targets.clear()
		return 

	# --- 黏著打擊迴圈 (Sticky Loop) ---
	var dead_targets = []
	var all_sticky_finished: bool = true 

	for hurtbox in hit_targets.keys():
		if not is_instance_valid(hurtbox):
			dead_targets.append(hurtbox)
			continue
			
		var data: Dictionary = hit_targets[hurtbox]
		if sticky_multi_hit and data["hits_done"] < max_hits:
			all_sticky_finished = false 
			if current_time - data["last_hit_time"] >= hit_interval:
				_execute_hit(hurtbox)
				data["hits_done"] += 1
				data["last_hit_time"] = current_time 

	for target in dead_targets: hit_targets.erase(target)

	# --- 黏著攻擊完整結束清理 ---
	if not has_active_shape and sticky_multi_hit and all_sticky_finished:
		hit_targets.clear()
		return

	# --- 持續索敵 ---
	if not sticky_multi_hit and hit_interval > 0.0 and has_active_shape:
		for area in get_overlapping_areas():
			_try_hit(area)

# ==========================================
# ⚔️ 命中判定與發動
# ==========================================
func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)
	
	

func _try_hit(area: Area2D) -> void:
	if not (area is CollisionObject2D and "hurt" in area): return
	if not is_instance_valid(area.owner) or area.owner == self.owner: return 
	
	var victim: Node = area.owner
	
	# 🌟 環境力通行證：大於 0 傷害的真攻擊才觸發閃避與無敵！
	if damage_amount > 0:
		if is_instance_valid(victim):
			if victim is Player and (victim.invincible_timer.time_left > 0 or victim.get("is_weapon_invincible")):
				return 
			if "state_machine" in victim:
				var sm: Node = victim.state_machine
				if is_instance_valid(sm) and is_instance_valid(sm.current_state):
					if sm.current_state.name.to_lower() == "slide":
						if sm.current_state.has_method("trigger_perfect_dodge"):
							sm.current_state.trigger_perfect_dodge()
						register_dodge(area) 
						return
				
	if not hit_targets.has(area):
		hit_targets[area] = {"hits_done": 0, "last_hit_time": 0.0}
		
	var data: Dictionary = hit_targets[area]
	if data["hits_done"] >= max_hits: return 
		
	var current_time = Time.get_ticks_msec() / 1000.0
	if data["hits_done"] == 0 or (current_time - data["last_hit_time"] >= hit_interval):
		_execute_hit(area)
		data["hits_done"] += 1
		data["last_hit_time"] = current_time

func _execute_hit(hurtbox: Node) -> void:
	var attacker_dir: int = 1
	if is_instance_valid(self.owner):
		if "direction" in self.owner: attacker_dir = self.owner.direction
		elif "player" in self.owner and is_instance_valid(self.owner.player) and "direction" in self.owner.player:
			attacker_dir = self.owner.player.direction 
		
	if pull_towards_owner and is_instance_valid(hurtbox):
		var victim_node = hurtbox.owner if is_instance_valid(hurtbox.owner) else hurtbox
		var pull_dir = sign(self.global_position.x - victim_node.global_position.x)
		if pull_dir == 0: pull_dir = attacker_dir
		absolute_knockback = Vector2(abs(knockback_force.x) * pull_dir, knockback_force.y)
	else:
		absolute_knockback = Vector2(knockback_force.x * attacker_dir, knockback_force.y)
	
	# 🌟 發送訊號：我只負責廣播，剩下的交給大腦 (Player/Weapon) 去煩惱
	hit.emit(hurtbox)     
	if hurtbox.has_method("hurt"): hurtbox.hurt(self)
	elif hurtbox.has_signal("hurt"): hurtbox.emit_signal("hurt", self) 
	
	# --- 視覺與打擊回饋 ---
	if hitstop_duration > 0 and CombatManager.has_method("apply_hitstop"):
		CombatManager.apply_hitstop(hitstop_duration)
	if shake_intensity > 0 and CombatManager.has_method("apply_camera_shake"):
		CombatManager.apply_camera_shake(shake_intensity)
	if hit_sfx_type != "":
		AudioManager.play_hit_sfx(hit_sfx_type, -2.0)
		
	if (spark_type != SparkType.OTHER or custom_spark_scene != null) and CombatManager.has_method("spawn_spark"):
		var base_pos: Vector2 = hurtbox.global_position
		base_pos.x += spark_base_offset.x * attacker_dir
		base_pos.y += spark_base_offset.y
		
		var spawn_pos: Vector2 = base_pos
		spawn_pos.x += randf_range(-spark_random_offset.x, spark_random_offset.x)
		spawn_pos.y += randf_range(-spark_random_offset.y, spark_random_offset.y)
		
		var angle_offset: float = randf_range(-spark_random_angle, spark_random_angle)
		var target: Node = hurtbox.owner if attach_spark_to_victim else null
		
		CombatManager.spawn_spark(
			spark_type, spawn_pos, attacker_dir, target, angle_offset,
			spark_scale, spark_color, custom_spark_scene, aura_color, spark_raw_intensity
		)

func register_dodge(hurtbox: Area2D) -> void:
	if not hit_targets.has(hurtbox): hit_targets[hurtbox] = {"hits_done": 0, "last_hit_time": 0.0}
	if hit_targets[hurtbox]["hits_done"] < max_hits:
		hit_targets[hurtbox]["hits_done"] += 1
