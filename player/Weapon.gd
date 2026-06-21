class_name Weapon
extends Node2D
## 武器基底類別 (Weapon Base Contract)
## 職責：定義了狀態機總監與具體武器溝通的唯一管道，實現解耦。
## 禁忌：武器只負責「計算並回傳數值」，絕對不准自己呼叫 player.move_and_slide()！

var player: Node

# ==========================================
# 🏷️ 動作類別標籤 (Action Type)
# ==========================================
enum ActionType {
	NONE,
	NORMAL,   # 普攻 (含強化普攻、空中普攻)
	SKILL,    # 戰技 (地上/空中)
	ULTIMATE, # 大招
	INTRO,    # 切換/變奏出場
	ASSIST    # 援助/協同攻擊
}

## 當前正在執行的動作標籤 (供外界讀取，如協同雷射)
var current_action_type: ActionType = ActionType.NONE

@export_group("外觀設定")
## 這把武器專屬的劍鞘貼圖 (如果沒有劍鞘就留空)
@export var scabbard_texture: Texture2D

# ==========================================
# 🎨 UI 圖標與冷卻介面 (僅保留戰技 1 與大招)
# ==========================================
@export_group("技能圖標配置")
@export var skill_1_icon: Texture2D
@export var ult_icon: Texture2D

@export_group("技能冷卻時間")
@export var skill_1_cd: float = 8.0 
@export var ult_cd: float = 20.0

# 內部計時器
var skill_1_timer: float = 0.0
var ult_timer: float = 0.0


# ==========================================
# 🥋 核心模組：武藝組件系統 (Martial Arts Component System)
# ==========================================
var martial_slots: Array[Node] = [null, null, null] # 存放實例化後的武藝 Node (1, 2, 3)
var active_martial_art: Node = null # 當前正在執行的武藝

## 系統呼叫：將字串陣列轉換為實際的武藝節點並裝備
func load_martial_arts(art_paths: Array[String]) -> void:
	# 1. 拔除並清空舊武藝
	for slot in martial_slots:
		if is_instance_valid(slot): slot.queue_free()
	martial_slots = [null, null, null]
	
	# 2. 實例化新武藝並加為子節點
	for i in range(min(art_paths.size(), 3)):
		if art_paths[i] != "":
			var art_resource = load(art_paths[i])
			if art_resource:
				var art_node = null
				# 🌟 完美相容：支援純腳本 (.gd) 或場景 (.tscn)
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

## 總機下令：發動武藝！
func execute_martial_art(slot_index: int) -> void:
	var idx = slot_index - 1
	if idx < 0 or idx >= 3 or not is_instance_valid(martial_slots[idx]): 
		return # 空槽位或無效
		
	# 將武器最高控制權移交給指定的武藝節點
	active_martial_art = martial_slots[idx]
	if active_martial_art.has_method("enter"):
		active_martial_art.enter()

# ==========================================
# ⚙️ 初始化
# ==========================================
func _ready() -> void:
	# 🌟 保護動態生成的殘影武器
	# 殘影複製出來的武器 owner 會是 null，等待 Player 腳本動態注入
	if owner != null:
		if not owner.is_node_ready():
			await owner.ready
		player = owner

# ==========================================
# 🎬 UI 專用接口：取得當前該顯示的技能圖標
# ==========================================
func get_dynamic_skill_icon(slot: int) -> Texture2D:
	# 🌟 如果有裝備武藝，優先回傳武藝的專屬圖標！
	if slot >= 1 and slot <= 3:
		var idx = slot - 1
		if is_instance_valid(martial_slots[idx]) and "icon" in martial_slots[idx]:
			var ma_icon = martial_slots[idx].get("icon")
			if ma_icon != null: return ma_icon

	# 舊版相容邏輯
	match slot:
		1: return skill_1_icon
		4: return ult_icon
	return null
	
# ==========================================
# 📡 跨實例資源快遞路由
# ==========================================
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
# 🎬 總監 (WeaponAttackState) 呼叫標準介面 (Virtual Methods)
# ==========================================

## ⏳ 系統呼叫：背景計時器更新
func update_timers_only(_delta: float) -> void:
	pass

## ⚔️ 總監下令：開始輕攻擊 (普攻)
func start_light_attack() -> void:
	pass

## ⚔️ 總監下令：開始重攻擊 (戰技)
func start_heavy_attack() -> void:
	pass

## 🏃 總監發問：這一幀，玩家的水平/垂直速度應該是多少？
func get_current_velocity(_delta: float) -> Vector2:
	return Vector2.ZERO

## 🍎 總監發問：這把武器現在的招式，需要總監幫忙套用重力嗎？
func is_handling_gravity() -> bool:
	return false

## 🎬 總監發問：現在這套招式的動畫播完了嗎？可以下台了嗎？
func is_attack_finished() -> bool:
	return true

## 🛡️ 總監發問：現在這個瞬間，允許玩家按閃避中斷嗎？
func can_be_canceled_by_dodge() -> bool:
	return true

## 💥 總監下令：招式被打斷了！立刻清理你的內部暫存！
func cancel_attack() -> void:
	pass
	
## 🗡️ 總監發問：這招打完之後，需要播放收刀(Sheath)動畫嗎？
func requires_sheath() -> bool:
	return false
	
# ==========================================
# 🛡️ 狀態機防護名單 (The Bouncer's List)
# ==========================================
func can_air_light() -> bool:
	return false

func can_air_skill() -> bool:
	return false
