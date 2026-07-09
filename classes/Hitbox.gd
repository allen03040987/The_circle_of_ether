class_name Hitbox
extends Area2D
## 萬用攻擊判定框 (Hitbox)
## 負責處理命中判定、多段打擊、黏著傷害、擊退計算以及視覺與聽覺特效的分發。

## 🌟 SLASH_2~5/BLUNT_2~5 都附加在 OTHER 之後、不插在 SLASH/BLUNT 中間——因為某些地方(Sickle.gd、Art_Katana系列)是直接寫死 0/1 這種 raw int，插在中間會讓那些既有的判斷全部錯位
enum SparkType { SLASH, BLUNT, OTHER, SLASH_2, SLASH_3, SLASH_4, SLASH_5, BLUNT_2, BLUNT_3, BLUNT_4, BLUNT_5 }

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
@export var breaks_guard: bool = false ## 是否能破解敵人的「黃圈彈刀」格擋判定窗
@export var requires_countermeasure: bool = false ## 「黃圈技」專屬：只有帶 breaks_guard 的「對策技」能破解，通用的「彈反型招式」對這一下攻擊無效

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

# 🌟 這些常數是「沒在招式資料裡指定 spark 欄位時」的唯一預設值來源——
# 武器腳本 (如 Katana.gd) 的 fallback 一律讀這裡，只要改這裡，所有招式的預設外觀就會一起變
const DEFAULT_SPARK_TYPE: SparkType = SparkType.BLUNT
const DEFAULT_SPARK_BASE_OFFSET: Vector2 = Vector2(0.0, 0.0)
const DEFAULT_ATTACH_SPARK_TO_VICTIM: bool = true
const DEFAULT_SPARK_RANDOM_ANGLE: float = 20.0
const DEFAULT_SPARK_RANDOM_OFFSET: Vector2 = Vector2(0.0, 0.0)
const DEFAULT_SPARK_SCALE: float = 0.3
const DEFAULT_SPARK_COLOR: Color = Color.WHITE
const DEFAULT_SPARK_RAW_INTENSITY: float = 1.0
const DEFAULT_AURA_COLOR: Color = Color(1.0, 1.0, 1.0, 0.5)

@export_group("火花進階設定")
@export var spark_type: SparkType = DEFAULT_SPARK_TYPE
@export var spark_base_offset: Vector2 = DEFAULT_SPARK_BASE_OFFSET
@export var attach_spark_to_victim: bool = DEFAULT_ATTACH_SPARK_TO_VICTIM
@export var spark_random_angle: float = DEFAULT_SPARK_RANDOM_ANGLE
@export var spark_random_offset: Vector2 = DEFAULT_SPARK_RANDOM_OFFSET
@export var spark_scale: float = DEFAULT_SPARK_SCALE
@export var spark_color: Color = DEFAULT_SPARK_COLOR
@export var spark_raw_intensity: float = DEFAULT_SPARK_RAW_INTENSITY
@export var custom_spark_scene: PackedScene
@export var aura_color: Color = DEFAULT_AURA_COLOR

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

## 🌟 鎖定這次攻擊的擊退方向——多段連擊(sticky_multi_hit)持續期間玩家若轉身/移動，擊退方向不會被中途打亂。
## 0 = 尚未鎖定，退回舊的「每次命中即時抓 owner 目前朝向」行為；武器腳本要在每次出招開頭 (清空 hit_targets 的同時) 呼叫一次。
var _locked_attacker_dir: int = 0
func lock_attacker_direction() -> void:
	var d: int = 1
	if is_instance_valid(self.owner):
		if "direction" in self.owner: d = self.owner.direction
		elif "player" in self.owner and is_instance_valid(self.owner.player) and "direction" in self.owner.player:
			d = self.owner.player.direction
	_locked_attacker_dir = d

## 實際執行命中：計算擊退方向、觸發受擊方法，並呼叫特效與音效管理器
func _execute_hit(hurtbox: Node) -> void:
	var attacker_dir: int = 1
	if _locked_attacker_dir != 0:
		attacker_dir = _locked_attacker_dir
	elif is_instance_valid(self.owner):
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
		# 🌟 火花基準點：優先找敵人自己場景裡有沒有放 "SparkAnchor" (Marker2D)，沒有才退回 Hurtbox 節點本身的位置(通常在腳邊)。
		# 每隻敵人的立繪比例不同，直接在該敵人的 .tscn 編輯器裡拖一個 Marker2D、命名成 SparkAnchor、擺到想要的高度(例如軀幹中心)就好，不用改任何程式碼。
		var spark_owner: Node = hurtbox.owner if is_instance_valid(hurtbox.owner) else hurtbox
		var anchor_node: Node2D = spark_owner.find_child("SparkAnchor", true, false) as Node2D
		var base_pos: Vector2 = anchor_node.global_position if is_instance_valid(anchor_node) else hurtbox.global_position
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
