class_name Weapon
extends Node2D
## 武器基底類別 (Weapon Base Contract)

var player: Node

enum ActionType {
	NONE,
	NORMAL,   
	SKILL,    
	ULTIMATE, 
	INTRO,    
	ASSIST    
}

var current_action_type: ActionType = ActionType.NONE

@export_group("外觀設定")
@export var scabbard_texture: Texture2D

@export_group("技能圖標配置")
@export var skill_1_icon: Texture2D
@export var ult_icon: Texture2D

@export_group("技能冷卻時間")
@export var skill_1_cd: float = 8.0 
@export var ult_cd: float = 20.0

var skill_1_timer: float = 0.0
var ult_timer: float = 0.0

# ==========================================
# 🥋 武藝組件系統 
# ==========================================
var martial_slots: Array[Node] = [null, null, null] 
var active_martial_art: Node = null 

func load_martial_arts(art_paths: Array[String]) -> void:
	for slot in martial_slots:
		if is_instance_valid(slot): slot.queue_free()
	martial_slots = [null, null, null]
	
	for i in range(min(art_paths.size(), 3)):
		if art_paths[i] != "":
			var art_resource = load(art_paths[i])
			if art_resource:
				var art_node = null
				if art_resource is GDScript:
					art_node = art_resource.new()
				elif art_resource is PackedScene:
					art_node = art_resource.instantiate()
					
				if art_node:
					add_child(art_node)
					if art_node.has_method("setup"):
						art_node.setup(player, self)
					martial_slots[i] = art_node
					
					var a_name = art_node.get("art_name") if "art_name" in art_node else "未知武藝"
					print("📦 [", name, "] 成功掛載武藝槽位 ", i+1, ": ", a_name)

func execute_martial_art(slot_index: int) -> void:
	var idx = slot_index - 1
	if idx < 0 or idx >= 3 or not is_instance_valid(martial_slots[idx]): 
		return # 空槽位或無效
		
	var target_art = martial_slots[idx]
	
	# 🌟 新增：空戰限制防護網
	if not player.is_on_floor():
		var can_air = target_art.get("can_use_in_air") if "can_use_in_air" in target_art else false
		if not can_air:
			print("🚫 [系統攔截] 武藝 '", target_art.get("art_name"), "' 只能在地面施放！")
			return # 直接退回，狀態機會在一幀後自動切換至 Fall 狀態
			
	# 如果有舊的武藝還在執行，先強制超渡它 (防護幽靈殘留)
	if is_instance_valid(active_martial_art) and active_martial_art.has_method("cancel"):
		active_martial_art.cancel()
		
	# 將武器最高控制權移交給指定的武藝節點
	active_martial_art = target_art
	if active_martial_art.has_method("enter"):
		active_martial_art.enter()

# ==========================================
# ⚙️ 初始化與介面
# ==========================================
func _ready() -> void:
	if owner != null:
		if not owner.is_node_ready():
			await owner.ready
		player = owner

func get_dynamic_skill_icon(slot: int) -> Texture2D:
	if slot >= 1 and slot <= 3:
		var idx = slot - 1
		if is_instance_valid(martial_slots[idx]) and "icon" in martial_slots[idx]:
			var ma_icon = martial_slots[idx].get("icon")
			if ma_icon != null: return ma_icon

	match slot:
		1: return skill_1_icon
		4: return ult_icon
	return null
	
func try_forward_resource(method_name: String, amount: int) -> bool:
	if not (player is Player):
		var rp = player.get("real_player")
		if is_instance_valid(rp):
			var slot = rp.get("weapon_slot")
			if is_instance_valid(slot):
				for w in slot.get_children():
					if w.get("WEAPON_ID") == self.get("WEAPON_ID") and w.has_method(method_name):
						w.call(method_name, amount)
						return true 
		return true 
	return false 
	
# ==========================================
# 🎬 總監呼叫介面 (Virtual Methods)
# ==========================================
func update_timers_only(_delta: float) -> void: pass
func start_light_attack() -> void: pass
func start_heavy_attack() -> void: pass
func get_current_velocity(_delta: float) -> Vector2: return Vector2.ZERO
func is_handling_gravity() -> bool: return false
func is_attack_finished() -> bool: return true
func can_be_canceled_by_dodge() -> bool: return true
func cancel_attack() -> void: pass
func requires_sheath() -> bool: return false
func can_air_light() -> bool: return false
func can_air_skill() -> bool: return false
