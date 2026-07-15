class_name VsKnockdown
extends VsPlayerState
## 倒地狀態（causes_knockdown = true 的攻擊觸發）
## 趴地一段時間後自動進入 VsGetup

const KNOCKDOWN_DURATION: float = 1.2  # 趴地時長（秒）

var elapsed: float = 0.0

func enter(_prev: StringName) -> void:
	elapsed = 0.0
	var vs  := player as VsPlayer
	vs.anim_player.play("launched")
	vs.invincible_time_left = 0.5  # 落地初始無敵（防追打）

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	if player.is_on_floor():
		player.velocity.x = move_toward(player.velocity.x, 0.0, FRICTION * delta)
		player.velocity.y = 0.0
	else:
		_apply_gravity(delta)
	if elapsed >= KNOCKDOWN_DURATION:
		return &"vsgetup"
	return &""
