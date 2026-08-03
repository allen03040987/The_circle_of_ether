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
## 選用——不是每個投射物都需要動畫（原本的劍氣/地刺都是靜態單幀）。哪個
## Inherited Scene 變體想要動畫，就自己在編輯器加一顆 AnimationPlayer 子節點
## +一支叫 "default" 的動畫（例如地刺的破土逐格效果），base VsProjectile.tscn
## 不強制要求；沒有這顆節點的變體完全不受影響，見下方 _ready()/simulate()。
@onready var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")

## 動畫 seek 期間（restore_state() 觸發）設 true，比照 VsPlayer._resyncing_anim
## 的防呆慣例：純視覺 resync 的 seek() 不該被任何 Call Method 軌道當成「真的
## 走過這一幀模擬」。目前地刺這類動畫只用值軌道（冪等，不受影響），但之後
## 若有投射物動畫想加 Call Method 軌道，這裡已經先把防呆準備好，不用重新設計。
var _resyncing_anim: bool = false

var direction:    int   = 1
var speed:        float = 1500.0
var max_distance: float = 1200.0
var traveled:     float = 0.0
var owner_player: VsPlayer = null   # 排除命中自己人用，不進快照（還原時由 vs_world 重新指派）

## 存活秒數上限（2026-08-01，奈何地刺新增）——`speed=0` 的靜止彈道（原地
## 生成的判定，例如地刺）沒有「飛行距離」可以用來判斷該不該消失，`lifetime`
## 是並列的另一種銷毀條件；預設 0 = 不啟用，完全不影響既有會飛行的彈道
## （劍氣等）。`_age` 每幀累加，跟 `traveled` 同樣是無狀態的純累加，rollback
## 重模擬結果保證一致。
var lifetime: float = 0.0
var _age:     float = 0.0

## 這顆物件是用哪個場景生成的（"wave" = VsProjectile.tscn 劍氣、"spike" =
## VsGroundSpike.tscn 地刺）——兩者共用這支腳本，vs_world._instantiate_projectile()
## 生成時設定，rollback 還原時 vs_world._restore_projectiles() 要靠這個決定
## 該用哪個 PackedScene 重建節點（節點本身砍掉重建，這個欄位隨 save_state()/
## restore_state() 走，不會遺失）。
var scene_kind: StringName = &"wave"

func _ready() -> void:
	if anim_player:
		# MANUAL 模式在運行時才切、Call Method 用 IMMEDIATE——跟 VsPlayer._ready()
		# 同一套理由，見 CLAUDE.md 確定性規則表；沒有這兩行的話編輯器動畫面板
		# 會壞掉不能播（MANUAL 寫死在 tscn 會這樣），未來若加 Call Method 軌道
		# 也會因為延遲執行而破壞確定性。
		anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim_player.callback_mode_method  = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
		if anim_player.has_animation("default"):
			anim_player.play("default")

func simulate(delta: float) -> void:
	var step := direction * speed * delta
	position.x += step
	traveled += absf(step)
	_age += delta
	if anim_player:
		anim_player.advance(delta)

func should_despawn() -> bool:
	return traveled >= max_distance or hitbox.has_hit or (lifetime > 0.0 and _age >= lifetime)

func save_state() -> Dictionary:
	return {
		"pos":    position,
		"dir":    direction,
		"speed":  speed,
		"maxd":   max_distance,
		"trav":   traveled,
		"life":   lifetime,
		"age":    _age,
		"kind":   scene_kind,
		"hb_mon": hitbox.monitoring,
		"hb_hit": hitbox.has_hit,
	}

func restore_state(d: Dictionary) -> void:
	position          = d["pos"]
	direction         = d["dir"]
	speed             = d["speed"]
	max_distance      = d["maxd"]
	traveled          = d["trav"]
	lifetime          = d.get("life", 0.0)
	_age              = d.get("age", 0.0)
	scene_kind        = d.get("kind", &"wave")
	hitbox.monitoring = d["hb_mon"]
	hitbox.has_hit    = d["hb_hit"]
	hitbox.hit_targets.clear()
	hitbox.direction_override = direction
	scale.x = direction
	# 動畫時間對齊還原後的 _age——純視覺 resync，不是真的走過這段模擬時間，
	# 所以 seek() 期間設 _resyncing_anim（目前沒有 Call Method 軌道會讀它，
	# 純粹是預先準備好的防呆，見欄位註解）。
	if anim_player and anim_player.has_animation("default"):
		_resyncing_anim = true
		anim_player.play("default")
		anim_player.seek(_age, true)
		_resyncing_anim = false
