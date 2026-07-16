class_name VsAttack
extends VsPlayerState
## 普攻連段狀態（地面5段）
## 動畫在首次 enter() 時以程式碼建立並注入 AnimationPlayer，
## 連段繼續時直接呼叫 enter() 繞過 VsStateMachine 防重入鎖。

# ── 素材 ──────────────────────────────────────────────────────────────────────
const _TEX: Array = [
	null,
	preload("res://player/Katana/A1.png"),
	preload("res://player/Katana/A2.png"),
	preload("res://player/Katana/A3.png"),
	preload("res://player/Katana/A4.png"),
	preload("res://player/Katana/A5.png"),
]

# ── 連段資料表 ────────────────────────────────────────────────────────────────
# hitbox_start/end：判定框開/關時間點（秒）
# can_combo_start：可輸入下一招的開始時間；< 0 = 此招無法接續
# length：整體動畫時長（秒）
const COMBO_DATA: Dictionary = {
	1: {
		"hframes": 3, "vframes": 2, "region": Rect2(0, 0, 384, 128),
		"pos": Vector2(3, -30),
		"ftimes": [0.0, 0.04, 0.08, 0.12, 0.16, 0.48],
		"fids":   [0, 1, 2, 3, 4, 5],
		"hitbox_start": 0.09, "hitbox_end": 0.12,
		"length": 0.5,  "can_combo_start": 0.25,
		"damage": 80.0, "hitstun": 0.35, "knockback": Vector2(200.0, -50.0),
	},
	2: {
		"hframes": 3, "vframes": 3, "region": Rect2(0, 0, 384, 192),
		"pos": Vector2(2, -30),
		"ftimes": [0.0, 0.05, 0.1, 0.13, 0.17, 0.19, 0.21, 0.23],
		"fids":   [0, 1, 2, 3, 4, 5, 6, 7],
		"hitbox_start": 0.17, "hitbox_end": 0.24,
		"length": 0.7,  "can_combo_start": 0.3,
		"damage": 80.0, "hitstun": 0.35, "knockback": Vector2(220.0, -50.0),
	},
	3: {
		"hframes": 3, "vframes": 2, "region": Rect2(0, 0, 384, 128),
		"pos": Vector2(1, -31),
		"ftimes": [0.0, 0.15, 0.17, 0.21, 0.22],
		"fids":   [0, 1, 2, 3, 4],
		"hitbox_start": 0.15, "hitbox_end": 0.23,
		"length": 0.7,  "can_combo_start": 0.3,
		"damage": 80.0, "hitstun": 0.35, "knockback": Vector2(240.0, -50.0),
	},
	4: {
		"hframes": 3, "vframes": 2, "region": Rect2(0, 0, 384, 128),
		"pos": Vector2(5, -31),
		"ftimes": [0.0, 0.09, 0.12, 0.17, 0.22],
		"fids":   [0, 1, 2, 3, 4],
		"hitbox_start": 0.10, "hitbox_end": 0.21,
		"length": 0.6,  "can_combo_start": 0.3,
		"damage": 80.0, "hitstun": 0.35, "knockback": Vector2(260.0, -50.0),
	},
	5: {
		"hframes": 3, "vframes": 3, "region": Rect2(0, 0, 384, 192),
		"pos": Vector2(5, -29),
		"ftimes": [0.0, 0.1, 0.2, 0.3, 0.35, 0.4, 0.45],
		"fids":   [0, 1, 2, 3, 4, 5, 6],
		"hitbox_start": 0.36, "hitbox_end": 0.58,
		"length": 0.8,  "can_combo_start": -1.0,
		"damage": 150.0, "hitstun": 0.5, "knockback": Vector2(450.0, -80.0),
	},
}
const MAX_COMBO: int = 5

# ── 狀態變數 ──────────────────────────────────────────────────────────────────
var combo_step:      int   = 1
var elapsed:         float = 0.0
var attack_buffered: bool  = false
var _hitbox_active:  bool  = false
var _anims_ready:    bool  = false   # 動畫是否已注入 AnimationPlayer

# ── 進場 ──────────────────────────────────────────────────────────────────────
func enter(_prev: StringName) -> void:
	elapsed         = 0.0
	attack_buffered = false
	_hitbox_active  = false
	var vs              := player as VsPlayer
	var data: Dictionary = COMBO_DATA[combo_step]

	_ensure_animations_registered(vs)
	vs.anim_player.play("attack_%d" % combo_step)

	vs.hitbox.damage       = data["damage"]
	vs.hitbox.hitstun_time = data["hitstun"]
	vs.hitbox.knockback    = data["knockback"]
	vs.hitbox.monitoring   = false
	vs.hitbox.reset_hits()

	vs.mark_in_combat()

# ── 每幀更新 ──────────────────────────────────────────────────────────────────
func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	var vs              := player as VsPlayer
	var data: Dictionary = COMBO_DATA[combo_step]

	# 連段輸入緩衝（can_combo_start < 0 = 此段無法接續）
	var ccs: float = data["can_combo_start"]
	if input.attack and ccs >= 0.0 and elapsed >= ccs:
		attack_buffered = true

	# 攻擊判定框開關
	var want_active: bool = elapsed >= (data["hitbox_start"] as float) and elapsed < (data["hitbox_end"] as float)
	if want_active != _hitbox_active:
		_hitbox_active       = want_active
		vs.hitbox.monitoring = want_active
		if not want_active:
			vs.hitbox.reset_hits()

	# 地面慣性衰減（攻擊期間不接受移動輸入）
	if _grounded():
		player.velocity.x = move_toward(player.velocity.x, 0.0, FRICTION * 0.5 * delta)
	else:
		_apply_gravity(delta)

	# 動畫結束
	if elapsed >= (data["length"] as float):
		_kill_hitbox(vs)
		if attack_buffered and combo_step < MAX_COMBO:
			combo_step += 1
			enter(&"vsattack")   # 直接重啟，繞過防重入（exit() 不會被呼叫）
			return &""
		else:
			combo_step = 1
			return &"vsidle" if _grounded() else &"vsfall"

	return &""

# ── 離場 ──────────────────────────────────────────────────────────────────────
func exit() -> void:
	combo_step = 1
	_kill_hitbox(player as VsPlayer)

# ── 私有輔助 ──────────────────────────────────────────────────────────────────
func _kill_hitbox(vs: VsPlayer) -> void:
	if _hitbox_active:
		vs.hitbox.monitoring = false
		vs.hitbox.reset_hits()
		_hitbox_active = false

func save_state() -> Dictionary:
	var vs := player as VsPlayer
	return {
		"step":    combo_step,
		"elapsed": elapsed,
		"buf":     attack_buffered,
		"hb":      _hitbox_active,
		# has_hit 隨快照保存：rollback 還原後不會因 hit_targets 被清而重複命中
		"hh":      vs.hitbox.has_hit if is_instance_valid(vs) else false,
	}

func restore_state(d: Dictionary) -> void:
	combo_step      = d.get("step",    1)
	elapsed         = d.get("elapsed", 0.0)
	attack_buffered = d.get("buf",     false)
	_hitbox_active  = d.get("hb",      false)
	var vs := player as VsPlayer
	if is_instance_valid(vs):
		vs.hitbox.monitoring = _hitbox_active
		vs.hitbox.has_hit    = d.get("hh", false)

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("attack_%d" % combo_step)
	vs.anim_player.seek(elapsed, true)

## 首次呼叫時將 attack_1~5 動畫以程式碼建立並注入 AnimationPlayer，
## 之後 anim_player.play("attack_N") 即可使用，在編輯器裡也看得到。
func _ensure_animations_registered(vs: VsPlayer) -> void:
	if _anims_ready:
		return
	var lib := vs.anim_player.get_animation_library("")
	for step: int in COMBO_DATA:
		var anim_name := "attack_%d" % step
		if lib.has_animation(anim_name):
			continue
		var data: Dictionary = COMBO_DATA[step]
		var anim := Animation.new()
		anim.length = data["length"]

		# texture（離散，t=0 設一次）
		var t0 := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t0, "Graphics/Sprite2D:texture")
		anim.track_insert_key(t0, 0.0, _TEX[step])
		anim.value_track_set_update_mode(t0, Animation.UPDATE_DISCRETE)

		# hframes
		var t1 := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t1, "Graphics/Sprite2D:hframes")
		anim.track_insert_key(t1, 0.0, data["hframes"] as int)
		anim.value_track_set_update_mode(t1, Animation.UPDATE_DISCRETE)

		# vframes
		var t2 := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t2, "Graphics/Sprite2D:vframes")
		anim.track_insert_key(t2, 0.0, data["vframes"] as int)
		anim.value_track_set_update_mode(t2, Animation.UPDATE_DISCRETE)

		# region_rect（對應 tscn 現有動畫的 update=0 慣例）
		var t3 := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t3, "Graphics/Sprite2D:region_rect")
		anim.track_insert_key(t3, 0.0, data["region"])
		anim.value_track_set_update_mode(t3, Animation.UPDATE_CONTINUOUS)

		# position
		var t4 := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t4, "Graphics/Sprite2D:position")
		anim.track_insert_key(t4, 0.0, data["pos"])
		anim.value_track_set_update_mode(t4, Animation.UPDATE_DISCRETE)

		# frame（逐格鍵）
		var t5 := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t5, "Graphics/Sprite2D:frame")
		anim.value_track_set_update_mode(t5, Animation.UPDATE_DISCRETE)
		var ftimes: Array = data["ftimes"]
		var fids:   Array = data["fids"]
		for i: int in ftimes.size():
			anim.track_insert_key(t5, ftimes[i] as float, fids[i] as int)

		lib.add_animation(anim_name, anim)
	_anims_ready = true
