class_name Weapon
extends Node2D
## 武器基底類別 (Weapon Base Contract)
## 職責：定義了狀態機總監與具體武器溝通的唯一管道，實現解耦。
## 禁忌：武器只負責「計算並回傳數值」，絕對不准自己呼叫 player.move_and_slide()！

var player: Node

# ==========================================
# 🏷️ 動作類別標籤 (Action Type) - 🌟 新增
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
# 🎨 UI 圖標與冷卻介面 (供 CombatUI 讀取)
# ==========================================
@export_group("技能圖標配置")
@export var skill_1_icon: Texture2D
@export var skill_2_icon: Texture2D
@export var skill_3_icon: Texture2D
@export var ult_icon: Texture2D


@export_group("技能冷卻時間")
@export var skill_1_cd: float = 8.0 
@export var skill_2_cd: float = 8.0
@export var skill_3_cd: float = 8.0
@export var ult_cd: float = 20.0

# 內部計時器 (留在背景跑，不 Export)
var skill_1_timer: float = 0.0
var skill_2_timer: float = 0.0
var skill_3_timer: float = 0.0
var ult_timer: float = 0.0


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
	match slot:
		1: return skill_1_icon
		2: return skill_2_icon
		3: return skill_3_icon
		4: return ult_icon
	return null
	
# ==========================================
# 🎬 總監 (WeaponAttackState) 呼叫標準介面
# ==========================================

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
## 回傳 false：總監加重力；回傳 true：武器自己處理 Y 軸。
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
## 玩家在空中按攻擊時，先問武器給不給按。
func can_air_light() -> bool:
	return false

func can_air_skill() -> bool:
	return false
