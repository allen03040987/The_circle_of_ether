class_name Weapon
extends Node2D
## 武器基底類別 (Weapon Base Contract)
## 定義了所有武器與「戰鬥狀態總監」溝通的統一虛擬方法，並負責管理武藝卡帶的裝卸與生命週期。

var player: Node

enum ActionType {
	NONE,
	NORMAL,
	SKILL,
	INTRO,
	ASSIST
}

var current_action_type: ActionType = ActionType.NONE

@export_group("外觀設定")
@export var scabbard_texture: Texture2D

# ==========================================
# 🥋 武藝組件系統 
# ==========================================
var martial_slots: Array[Node] = [null, null, null]
var active_martial_art: Node = null

## 讀取並實例化玩家配置的武藝腳本
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

## 啟動指定槽位的武藝卡帶，並攔截違規的空戰觸發
func execute_martial_art(slot_index: int) -> void:
	var idx = slot_index - 1
	if idx < 0 or idx >= 3 or not is_instance_valid(martial_slots[idx]):
		return 
		
	var target_art = martial_slots[idx]
	
	if not player.is_on_floor():
		var can_air = target_art.get("can_use_in_air") if "can_use_in_air" in target_art else false
		if not can_air:
			print("🚫 [系統攔截] 武藝 '", target_art.get("art_name"), "' 只能在地面施放！")
			return 
			
	if is_instance_valid(active_martial_art) and active_martial_art.has_method("cancel"):
		active_martial_art.cancel()
		
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

## 獲取武藝槽位對應的圖標
func get_dynamic_skill_icon(slot: int) -> Texture2D:
	if slot >= 1 and slot <= 3:
		var idx = slot - 1
		if is_instance_valid(martial_slots[idx]) and "icon" in martial_slots[idx]:
			var ma_icon = martial_slots[idx].get("icon")
			if ma_icon != null: return ma_icon
	return null
	
## 處理分身/幻影將打擊資源傳回給本體武器的邏輯
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
## 更新武器內部計時器 (如冷卻時間)
func update_timers_only(_delta: float) -> void: pass
## 觸發普攻起手
func start_light_attack() -> void: pass
## 觸發重擊或戰技起手
func start_heavy_attack() -> void: pass
## 武器負責提供的當前物理速度 (含煞車/突進)
func get_current_velocity(_delta: float) -> Vector2: return Vector2.ZERO
## 是否由武器全權接管 Y 軸重力
func is_handling_gravity() -> bool: return false
## 判斷攻擊動畫與收招階段是否已經完全結束
func is_attack_finished() -> bool: return true
## 判斷當前招式能否被閃避中斷
func can_be_canceled_by_dodge() -> bool: return true
## 被外力(受擊/閃避/大招)強制中斷時的清洗邏輯
func cancel_attack() -> void: pass
## 判斷收招時是否需要播放收刀動畫
func requires_sheath() -> bool: return false
## 空戰驗證
func can_air_light() -> bool: return false
func can_air_skill() -> bool: return false
