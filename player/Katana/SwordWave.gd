class_name SwordWave
extends Node2D
## 劍氣投射物腳本
## 負責處理飛行距離、方向、播放消失動畫，並在壽命結束時自我銷毀。

# ==========================================
# 🎛️ 基礎飛行參數
# ==========================================
var direction: int = 1
var speed: float = 800.0
var max_distance: float = 400.0
var traveled_distance: float = 0.0

# 🌟 內部狀態記憶體
var is_expiring: bool = false # 記錄是否正在執行消失邏輯

# ==========================================
# 🔗 節點參考 (Node References)
# ==========================================
@onready var hitbox: Hitbox = $Hitbox
@onready var graphics: Node2D = $Graphics # 🌟 假設你把 Sprite 和 Aura 都放在一個叫 Graphics 的 Node2D 裡
@onready var animation_player: AnimationPlayer = $AnimationPlayer # 🌟 你新增的動畫播放器

# ==========================================
# ⚙️ 初始化與生命週期 (Lifecycle)
# ==========================================
func _ready() -> void:
	# 根據方向翻轉
	scale.x = direction
	
	# 因為 Hitbox.gd 會往上找 owner.direction 來決定火花方向，我們把自己設為 owner
	hitbox.owner = self
	
	# 🌟 播放預設的飛行動畫 (例如你剛建好的動畫)
	if animation_player.has_animation("fly"):
		animation_player.play("fly")

func _physics_process(delta: float) -> void:
	# 🌟 如果正在消失中，停止移動
	if is_expiring: return
	
	var step = speed * delta
	position.x += direction * step
	traveled_distance += step
	
	# ==========================================
	# 🌟 壽命結束邏輯：觸發消失
	# ==========================================
	if traveled_distance >= max_distance:
		expire()

# ==========================================
# 🎬 消失邏輯 (Expire)
# ==========================================
func expire() -> void:
	# 防呆：防止重複觸發
	if is_expiring: return
	is_expiring = true
	
	# 1. 🛑 立刻關閉判定框，防止消失期間還能打到人
	hitbox.monitorable = false
	hitbox.monitoring = false
	
	# 2. 🎬 嘗試播放淡出動畫
	if animation_player.has_animation("fade_out"):
		# 🌟 如果有設好動畫 (動畫最後一幀要記得呼叫 queue_free，請看下面的設定指南)
		animation_player.play("fade_out")
	else:
		# 🌟 防呆：如果沒動畫，就用程式碼硬切
		queue_free()
