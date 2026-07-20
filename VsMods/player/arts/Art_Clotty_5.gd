class_name Art_Clotty_5
extends VsMartialArt
## 斷空劍氣簡化版——主遊戲原版可長按蓄力發射 1~6 發劍氣（依蓄力時間分階），
## 使用者要求砍掉蓄力機制，改成單純「出招→發射一發劍氣→收招」。
## 彈道本身是獨立的 VsProjectile 節點（VsMods/combat/VsProjectile.gd，脫手
## 施放、離開這個狀態後仍自己飛行判定），發射時機由 `art_5` 動畫的 Call Method
## 軌道呼叫 VsPlayer.fire_sword_wave() 決定——跟 strike_impulse 同一套「時間點
## 放動畫軌道，不寫死程式碼」慣例，這支腳本完全不管發射的確切時間點。
## ⚠ 2026-07-19 使用者要求可在空中施放，比照 Art_Clotty_4.gd 的做法：
## can_use_in_air=true，且空中施放時完全無視重力（原地懸空，不套用任何重力
## 係數），跟 3 號同一套統一手感。

func _init() -> void:
	art_name       = "武藝五"
	energy_cost    = 20.0
	can_use_in_air = true

var _anim_length: float = 0.0

func enter(_prev: StringName) -> void:
	super.enter(_prev)
	var vs := player as VsPlayer
	player.velocity.x = 0.0
	if not _grounded():
		player.velocity.y = 0.0   # 無視重力：懸空施放，不用起跳推力
	vs.anim_player.play("art_5")
	_anim_length = vs.anim_player.get_animation("art_5").length
	vs.mark_in_combat()

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer
	# 衝刺取消：任何時點都適用（全域規則：衝刺可打斷任何非受擊動作）——之前
	# 漏加，這招（跟其他幾支武藝）按了衝刺鍵完全沒反應
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"
	if _grounded():
		player.velocity.x = move_toward(player.velocity.x, 0.0, vs.friction * delta)
	else:
		player.velocity.y = 0.0   # 無視重力：全程原地懸空，不套用任何重力係數

	if elapsed >= _anim_length:
		return _recovery_transition(input)
	return &""

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("art_5")
	vs.anim_player.seek(elapsed, true)
