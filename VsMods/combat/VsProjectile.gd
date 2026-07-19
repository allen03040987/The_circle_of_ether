class_name VsProjectile
extends Node2D
## 確定性彈道物件（比照主遊戲 c_3_wave.tscn 簡化版，脫手施放：離開施放者後
## 自己飛行，不受施放狀態的生命週期綁定）。
##
## 必須以 vs_world 的直屬子節點形式存在——`position` 才等同世界座標（見
## CLAUDE.md 的 global_position 確定性規則：「模擬邏輯一律用 position（vs_world
## 直屬子節點兩者等值）」）。移動由 vs_world._simulate_frame() 每幀呼叫
## simulate(delta) 手動推進直線位移，不用 _physics_process/move_and_slide，
## 純粹是無狀態的位置累加，rollback 重模擬結果保證一致。
##
## 命中判定不走 Area2D 訊號（同一套理由：rollback 中間幀不會觸發），由
## vs_world._check_projectile_hits() 比照 _manual_check() 的手動幾何判定驅動，
## 复用 VsHitbox 既有的 has_hit/hit_targets 防重複機制。

@onready var hitbox: VsHitbox = $VsHitbox

var direction:    int   = 1
var speed:        float = 1500.0
var max_distance: float = 1200.0
var traveled:     float = 0.0
var owner_player: VsPlayer = null   # 排除命中自己人用，不進快照（還原時由 vs_world 重新指派）

func simulate(delta: float) -> void:
	var step := direction * speed * delta
	position.x += step
	traveled += absf(step)

func should_despawn() -> bool:
	return traveled >= max_distance or hitbox.has_hit

func save_state() -> Dictionary:
	return {
		"pos":    position,
		"dir":    direction,
		"speed":  speed,
		"maxd":   max_distance,
		"trav":   traveled,
		"hb_mon": hitbox.monitoring,
		"hb_hit": hitbox.has_hit,
	}

func restore_state(d: Dictionary) -> void:
	position          = d["pos"]
	direction         = d["dir"]
	speed             = d["speed"]
	max_distance      = d["maxd"]
	traveled          = d["trav"]
	hitbox.monitoring = d["hb_mon"]
	hitbox.has_hit    = d["hb_hit"]
	hitbox.hit_targets.clear()
	hitbox.direction_override = direction
	scale.x = direction
