class_name VsHitbox
extends Area2D
## VS 模式攻擊判定框（格鬥遊戲用）

enum BreakLevel {
	NONE,              # 無破甲
	ARMOR_BREAK,       # 破霸：可對霸體造成擊退/硬直
	STRONG_ARMOR_BREAK # 強破霸：可對強霸體造成擊退/硬直，並無視 50% 減傷
}

@export var damage: float = 100.0
@export var hitstun_time: float = 0.4       # 受擊硬直時長（秒）
@export var knockback: Vector2 = Vector2(200.0, -80.0)
@export var causes_knockdown: bool = false  # true = 觸發倒地狀態
@export var can_hit_downed: bool = false    # true = 可命中倒地目標（OTG）
@export var detached: bool = false          # true = 動畫結束後 hitbox 仍有效
@export var break_level: BreakLevel = BreakLevel.NONE
@export var guard_damage: float = 0.0      # 留用欄位（目前由體質效果系統統一計算）

var hit_targets: Dictionary = {}
## rollback 安全旗標：此段攻擊是否已命中過（儲存於快照，還原後不會意外重複觸發）
var has_hit: bool = false
## 擁有此 hitbox 的玩家（由 VsPlayer._build_hitbox 設定）。
## 受擊方向一律從它的 position（模擬資料）計算——Node.owner 對程式碼建立的
## 節點是 null，而 global_position 在 rollback 重模擬中可能過期。
var owner_player: Node2D = null

## 打擊偵測統一由 vs_world._simulate_frame() 內的幾何計算驅動，
## 不使用 Area2D 信號（信號有一幀延遲，導致兩端命中時機不同 → HP desync）

## 換招時呼叫，清除已命中記錄以允許再次判定
func reset_hits() -> void:
	hit_targets.clear()
	has_hit = false
