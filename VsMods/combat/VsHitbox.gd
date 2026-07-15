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

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if not (area is VsHurtbox): return
	if hit_targets.has(area): return
	if not is_instance_valid(area.owner): return
	if area.owner == self.owner: return
	hit_targets[area] = true
	area.receive_hit(self)

## 換招時呼叫，清除已命中記錄以允許再次判定
func reset_hits() -> void:
	hit_targets.clear()
