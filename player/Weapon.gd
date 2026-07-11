class_name Weapon
extends Node2D
## 武器基底類別 (Weapon Base Contract)
## 定義了所有武器與「戰鬥狀態總監」溝通的統一虛擬方法，並負責管理武藝卡帶的裝卸與生命週期。

var player: Node

## 招式標籤：位元旗標(bitmask)，一招可以同時掛多個標籤（例如「普攻＋空戰」）。
## NORMAL/SKILL 的數值刻意維持跟舊版一樣是 1/2，所有既有的 `== ActionType.NORMAL` 這類比較不會被影響；
## INTRO/ASSIST 目前整個專案都沒用到，直接挪去空的位元不會動到任何東西。
enum ActionType {
	NONE = 0,
	NORMAL = 1,      # 普攻：沒什麼特點的基礎連段
	SKILL = 2,       # 戰技：武器本體除了普攻以外的招式
	MARTIAL_ART = 4, # 武藝：三卡槽的武藝卡帶
	AIR = 8,         # 空戰：能在空中施放
	INTRO = 16,
	ASSIST = 32
}

var current_action_type: int = ActionType.NONE

## 這把武器的火花「預設外觀」——招式資料裡的某招沒指定 spark 欄位時，優先套用這裡（而不是 Hitbox.gd 的通用預設）。
## 子類別 (Katana.gd / Spear.gd ...) 覆寫這個方法即可帶出自己專屬的火花識別度，基底回傳空字典代表沒有客製化、全部退回 Hitbox 通用預設。
## 🔧 這裡故意用方法而不是 const：GDScript 不允許子類別重新宣告跟父類別同名的 const。
func get_weapon_default_spark() -> Dictionary:
	return {}

## 這把武器目前的移動速度倍率（例如長槍丟出去、人還沒接回槍的時候身法變輕巧）。基底固定 1.0，武器自己覆寫。
func get_speed_multiplier() -> float:
	return 1.0

@export_group("外觀設定")
@export var scabbard_texture: Texture2D

# ==========================================
# 🥋 武藝組件系統 
# ==========================================
var martial_slots: Array[Node] = [null, null, null]
var active_martial_art: Node = null

## 武藝實際成功施放時發出（能量閘門通過、真的 enter() 了）——給 UI 播放施放特效用，跟「輸入被擋下」的 denied 訊號分開
signal martial_art_cast(slot_index: int)

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

	# 🔋 能量閘門：所有武藝統一在這裡扣費，不放行任何一招裸放。
	# Player._has_martial_art() 已經在輸入層先擋過一次（避免撞到「取消目前招式後才發現放不出來」的怪空檔），
	# 這裡是最終、唯一真正生效的把關（例如未來若有非輸入觸發的武藝施放，也一樣會被扣到）
	var cost = target_art.get("energy_cost") if "energy_cost" in target_art else 0.0
	if cost > 0 and player.has_method("consume_martial_energy"):
		if not player.consume_martial_energy(cost):
			print("🚫 [系統攔截] 武藝 '", target_art.get("art_name"), "' 能量不足，需要 ", cost)
			return

	if is_instance_valid(active_martial_art) and active_martial_art.has_method("cancel"):
		active_martial_art.cancel()
		
	active_martial_art = target_art
	if active_martial_art.has_method("enter"):
		active_martial_art.enter()

	martial_art_cast.emit(slot_index)

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
	
## 🌟 分身/幻影(PhantomStriker)系統已整個刪除，`player` 現在必定是真正的 Player，這裡永遠沒有東西可轉發。
## 保留這個函式與呼叫端 (Sickle/Spear/Talisman) 的 `if try_forward_resource(...): return` 寫法不變，只是把已確認打不到的死路徑清掉。
func try_forward_resource(_method_name: String, _amount: int) -> bool:
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
