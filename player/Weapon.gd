class_name Weapon
extends Node2D
## 武器基底類別 (Weapon Base Contract)
## 這是所有武器的「合約」。定義了狀態機總監與武器溝通的唯一管道。
## 這樣總監就不需要知道每把武器的細節，徹底實現「解耦 (Decoupling)」。

var player: Node
@export_group("外觀設定")
## 這把武器專屬的劍鞘貼圖 (如果沒有劍鞘就留空)
@export var scabbard_texture: Texture2D

# ==========================================
# 🎨 UI 圖標與冷卻介面 (供 CombatUI 讀取)
# ==========================================
@export_group("技能圖標配置")
@export var skill_1_icon: Texture2D
@export var skill_1_enhanced_icon: Texture2D
@export var skill_2_icon: Texture2D
@export var skill_3_icon: Texture2D
@export var ult_icon: Texture2D

@export_group("技能冷卻時間") # 🌟 加上 Export，讓所有武器都能在面板獨立調數值
@export var skill_1_cd: float = 8.0 
@export var skill_2_cd: float = 8.0
@export var skill_3_cd: float = 8.0
@export var ult_cd: float = 20.0

# 計時器不用 Export，留在背景跑就好
var skill_1_timer: float = 0.0
var skill_2_timer: float = 0.0
var skill_3_timer: float = 0.0
var ult_timer: float = 0.0

func _ready() -> void:
	# ==========================================
	# 🌟 核心修復：保護動態生成的殘影武器
	# ==========================================
	# 如果是正常掛在場景上的武器，owner 會是 Player。
	# 但如果是殘影系統用 duplicate() 複製出來的，owner 會是 null！
	if owner != null:
		# 等待 Player 準備好
		if not owner.is_node_ready():
			await owner.ready
		player = owner
	# 如果 owner 是 null (殘影)，我們就不做任何事，
	# 乖乖等 Player.gd 的 spawn_phantom_striker 用程式碼幫我們 set("player", self)！

# ==========================================
# 🎬 總監 (WeaponAttackState) 會呼叫的標準介面
# ==========================================

## ⚔️ 總監下令：開始輕攻擊 (普攻)
func start_light_attack() -> void:
	pass

## ⚔️ 總監下令：開始重攻擊 (戰技)
func start_heavy_attack() -> void:
	pass

## 🏃 總監發問：這一幀，玩家的水平/垂直速度應該是多少？
## 🌟 絕對鐵律：武器只負責「計算並回傳數值」，絕對不准自己呼叫 player.move_and_slide()！
## 物理移動的執行權必須留在總監手裡，這樣系統才不會錯亂。
func get_current_velocity(delta: float) -> Vector2:
	return Vector2.ZERO

## 🍎 總監發問：這把武器現在的招式，需要總監幫忙套用重力嗎？
## 回傳 false：需要總監加重力 (一般地面攻擊)。
## 回傳 true：武器自己會算好 Y 軸速度 (例如太刀的空中滯空下劈、或者挑飛招式)。
func is_handling_gravity() -> bool:
	return false

## 🎬 總監發問：現在這套招式的動畫播完了嗎？可以下台了嗎？
## 只有當這個函數回傳 true 時，總監才會切換回 Idle 狀態。
func is_attack_finished() -> bool:
	return true

## 🛡️ 總監發問：現在這個瞬間，允許玩家按閃避中斷嗎？
## (例如大招期間回傳 false，給予絕對霸體；一般普攻回傳 true)
func can_be_canceled_by_dodge() -> bool:
	return true

## 💥 總監下令：招式被打斷了！立刻清理你的內部暫存！
## (當玩家挨打、或者強制閃避時，總監會呼叫這裡，讓武器把連段計數器、特效通通歸零)
func cancel_attack() -> void:
	pass
	
## 🗡️ 總監發問：這招打完之後，需要播放收刀(Sheath)動畫嗎？
func requires_sheath() -> bool:
	return false
	
# ==========================================
# 🛡️ 狀態機防護名單 (The Bouncer's List)
# ==========================================
## Player.gd 專用的審查接口。玩家在空中按攻擊時，先問武器給不給按。
func can_air_light() -> bool:
	return false

func can_air_skill() -> bool:
	return false
