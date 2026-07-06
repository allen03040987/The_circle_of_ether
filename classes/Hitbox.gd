class_name Hitbox
extends Area2D
## 萬用攻擊判定框 (Hitbox)
## 負責處理命中判定、多段打擊、黏著傷害、擊退計算以及視覺與聽覺特效的分發。

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
@export var pull_towards_owner: bool = false 

var absolute_knockback: Vector2 = Vector2.ZERO 
@onready var base_damage: int = damage_amount

# ==========================================
# 🔄 2. 多段連擊與黏著打擊
# ==========================================
@export_group("多段連擊設定")
@export var max_hits: int = 1 
@export var hit_interval: float = 0.0 
@export var sticky_multi_hit: bool = false 

var hit_targets: Dictionary = {} 

# ==========================================
# 🧃 3. 打擊感與視覺特效
# ==========================================
@export_group("打擊回饋")
@export var hit_sfx_type: String = "" 
@export var shake_intensity: float = 0.0  
@export var shake_on_hit_only: bool = true
var _has_shaken_this_attack: bool = false
var _suppress_feedback: bool = false

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

signal hit(hurtbox: Node)

# ==========================================
# ⚙️ 核心生命週期
# ==========================================
func _ready() -> void:
	area_entered.connect(_on_area_entered)

## 處理持續性的碰撞偵測、黏著多段打擊計時，以及空揮時的相機震動
func _process(_delta: float) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	var has_active_shape: bool = false
	
	if self.monitoring:
		for child in get_children():
			if (child is CollisionShape2D or child is CollisionPolygon2D) and not child.disabled:
				has_active_shape = true
				break
				
	if has_active_shape:
		if not shake_on_hit_only and not _has_shaken_this_attack and shake_intensity > 0:
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(shake_intensity)
			_has_shaken_this_attack = true 
	else:
		_has_shaken_this_attack = false
		
	if not has_active_shape and not sticky_multi_hit:
		hit_targets.clear()
		return 

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

	for target in dead_targets: 
		hit_targets.erase(target)

	if not has_active_shape and sticky_multi_hit and all_sticky_finished:
		hit_targets.clear()
		return

	if not sticky_multi_hit and hit_interval > 0.0 and has_active_shape:
		for area in get_overlapping_areas():
			_try_hit(area)

# ==========================================
# ⚔️ 命中判定與發動
# ==========================================
func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)

## 過濾無效目標，並驗證多段打擊的時間間隔與次數限制
func _try_hit(area: Area2D) -> void:
	if not (area is CollisionObject2D and "hurt" in area): return
	if not is_instance_valid(area.owner) or area.owner == self.owner: return 
				
	if not hit_targets.has(area):
		hit_targets[area] = {"hits_done": 0, "last_hit_time": 0.0}
		
	var data: Dictionary = hit_targets[area]
	if data["hits_done"] >= max_hits: return 
		
	var current_time = Time.get_ticks_msec() / 1000.0
	if data["hits_done"] == 0 or (current_time - data["last_hit_time"] >= hit_interval):
		_execute_hit(area)
		data["hits_done"] += 1
		data["last_hit_time"] = current_time

## 實際執行命中：計算擊退方向、觸發受擊方法，並呼叫特效與音效管理器
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
	
	_suppress_feedback = false
	hit.emit(hurtbox)
	if hurtbox.has_method("hurt"): hurtbox.hurt(self)
	elif hurtbox.has_signal("hurt"): hurtbox.emit_signal("hurt", self)

	# 🔧 如果對方在 hurt 訊號的處理過程中判定為「閃避成功」，就不要播放震動/音效/火花
	if _suppress_feedback: return

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

## 當敵人成功閃避此攻擊時，將其登記以防止後續的重複判定
func register_dodge(hurtbox: Area2D) -> void:
	if not hit_targets.has(hurtbox): hit_targets[hurtbox] = {"hits_done": 0, "last_hit_time": 0.0}
	if hit_targets[hurtbox]["hits_done"] < max_hits:
		hit_targets[hurtbox]["hits_done"] += 1

## 讓正在處理中的這一次命中跳過震動/音效/火花回饋 (在 hurt 訊號的處理流程中呼叫，例如閃避判定成立時)
func suppress_feedback() -> void:
	_suppress_feedback = true
