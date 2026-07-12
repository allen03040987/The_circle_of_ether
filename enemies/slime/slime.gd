class_name Slime
extends Enemy
## 史萊姆雜兵 AI
## 狀態機邏輯已搬到 StateMachine 底下的獨立狀態節點 (enemies/slime/state/*.gd)，
## 這裡只留跨狀態共用的資料、節點參考跟輔助函式。

@onready var state_machine: StateMachine = $StateMachine

# ==========================================
# 🎛️ 巡邏設定
# ==========================================
@export_group("巡邏設定")
@export var max_walk_distance: float = 150.0 ## 每次巡邏隨機挑一個不超過這個長度的距離走，跟出生點無關
@export var min_walk_speed: float = 50.0 ## 每次巡邏隨機挑的移動速度下限，上限沿用 max_speed
@export var turn_wait_time: float = 1.0 ## 走到隨機距離/撞牆/懸崖，停下來等這麼久再掉頭

# ==========================================
# 🎛️ 跳撲攻擊設定
# ==========================================
@export_group("跳撲攻擊設定")
@export var retreat_distance: float = 40.0
@export var retreat_speed: float = 80.0
@export var prepare_wait_time: float = 1.0 ## 後退完，等這麼久才跳
@export var warning_icon_lead_time: float = 0.5 ## 驚嘆號在跳之前這麼久出現（要 < prepare_wait_time）
@export var hop_velocity: Vector2 = Vector2(250.0, -280.0) ## 跳撲的初速（x 會乘上 direction），佔位數值之後再調
@export var landing_recovery_time: float = 0.1 ## 落地後停頓這麼久才繼續巡邏
@export var attack_cooldown_time: float = 2.5

# 🌟 解耦：把傷害參數提取到外部，方便面板調整
@export_group("史萊姆攻擊力")
@export var base_damage: int = 10
@export var base_knockback: Vector2 = Vector2(400.0, 0.0)

@export_group("受擊反應設定")
@export var hurt_recovery_time: float = 1.0 ## 被打之後至少停頓這麼久才回到巡邏，不是動畫一播完就走

# --- 跨狀態共用資料（各個狀態節點直接讀寫 slime.xxx） ---
var attack_cooldown: float = 0.0
var warning_tween: Tween
var consecutive_turns: int = 0 ## 連續掉頭次數：兩邊都走不了（例如一邊超出巡邏範圍、另一邊有牆）時用來偵測「卡住了」，避免無限掉頭

# ==========================================
# 🔗 節點參考
# ==========================================
@onready var wall_checker: RayCast2D = $Graphics/WallChecker
@onready var floor_checker: RayCast2D = $Graphics/FloorChecker
@onready var back_floor_checker: RayCast2D = $Graphics/BackFloorChecker ## 跟 floor_checker 鏡射對稱，永遠看向「面向的反方向」，後退專用
@onready var player_checker: RayCast2D = $Graphics/playerChecker
@onready var warning_icon: Sprite2D = $Graphics/WarningIcon
@onready var hitbox_shape: CollisionShape2D = $Graphics/Hitbox/CollisionShape2D
@onready var hitbox: Hitbox = $Graphics/Hitbox

# ==========================================
# ⚙️ 核心生命週期
# ==========================================
func _ready() -> void:
	super._ready() # 確保繼承的 Enemy._ready() 被呼叫
	hitbox_shape.disabled = true
	if warning_icon: warning_icon.visible = false

func can_see_player() -> bool:
	if not player_checker.is_colliding(): return false
	return player_checker.get_collider() is Player

func _physics_process(delta: float) -> void:
	if attack_cooldown > 0: attack_cooldown -= delta

# ==========================================
# 💥 受擊接收
# ==========================================
func _on_hurtbox_hurt(hb: Hitbox) -> void:
	take_damage(hb)
