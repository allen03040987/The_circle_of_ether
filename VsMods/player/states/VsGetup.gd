class_name VsGetup
extends VsPlayerState
## 起身狀態（倒地滿時自動進入）
## ⚠ 2026-07-27 使用者要求拿掉「起身後」額外 2 秒無敵——但起身動畫播放期間
## （角色處於無法操作的起身姿勢，不該被打）仍然要無敵，兩者不是同一件事。
## 無敵時間精確設成起身動畫長度，動畫播完那一刻自然歸零，不會延續到操作權
## 交還之後。起身期間仍可用衝刺打斷（打斷當下無敵也一併結束，見下）。

var elapsed:   float = 0.0
var _duration: float = 0.3   # 起身時長 = launched_2 動畫長度（enter/restore 時讀取）

func enter(_prev: StringName) -> void:
	elapsed = 0.0
	var vs  := player as VsPlayer
	vs.anim_player.play("launched_2")
	_duration = vs.anim_player.get_animation("launched_2").length
	# 只罩住起身動畫本身這段時間，不多不少——跟 VsKnockdown.INVINCIBLE_COVER
	# 那個「先給一個罩住整段流程的暫定大值、之後再校正」的做法不同，這裡精確
	# 值就是動畫長度，不需要之後再由誰校正。
	vs.invincible_time_left = _duration

func save_state() -> Dictionary:
	return {"elapsed": elapsed}

func restore_state(d: Dictionary) -> void:
	elapsed   = d.get("elapsed", 0.0)
	_duration = (player as VsPlayer).anim_player.get_animation("launched_2").length

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("launched_2")
	vs.anim_player.seek(elapsed, true)

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	# 承接倒地彈起的殘留滑行動量，摩擦減速（不瞬間黏住）
	player.velocity.x = move_toward(player.velocity.x, 0.0, (player as VsPlayer).friction * 1.5 * delta)
	# 衝刺打斷起身：提前結束就不再是「正在起身」的無防禦姿勢了，無敵一併提前結束
	var vs := player as VsPlayer
	if input.dodge and vs.use_dash_energy(30.0):
		vs.invincible_time_left = 0.0
		return &"vsdodge"
	if elapsed >= _duration:
		return _recovery_transition(input)   # 支援跑步預輸入
	return &""
