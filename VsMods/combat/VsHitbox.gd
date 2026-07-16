class_name VsHitbox
extends Area2D
## VS 模式攻擊判定框（格鬥遊戲用）

@export var damage: float = 100.0
@export var hitstun_time: float = 0.4        # 受擊硬直時長（秒）
@export var knockback: Vector2 = Vector2(200.0, -80.0)
@export var causes_knockdown: bool = false   # true = 觸發倒地狀態
@export var guard_damage: float = 0.0        # 防禦中的碎片傷害（0 = 與主傷害同用 CHIP_RATIO 計算）
@export var guard_break: bool = false        # 是否能打破防禦狀態

var hit_targets: Dictionary = {}
## rollback 安全旗標：此段攻擊是否已命中過（儲存於快照，還原後不會意外重複觸發）
var has_hit: bool = false

## 打擊偵測統一由 vs_world._simulate_frame() 內的幾何計算驅動，
## 不使用 Area2D 信號（信號有一幀延遲，導致兩端命中時機不同 → HP desync）

## 換招時呼叫，清除已命中記錄以允許再次判定
func reset_hits() -> void:
	hit_targets.clear()
	has_hit = false
