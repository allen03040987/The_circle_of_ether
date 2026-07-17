class_name VsIdle
extends VsPlayerState

func enter(_prev: StringName) -> void:
	var vs := player as VsPlayer
	# 回到 idle 自動面向對手（輔助鎖敵）。用模擬資料 position 算，確定性安全；
	# rollback 還原走 set_state_quiet 不會經過這裡，facing_dir 由快照還原
	if vs.opponent:
		var dx := vs.opponent.position.x - vs.position.x
		if dx != 0.0:
			vs.facing_dir = 1 if dx > 0.0 else -1
	vs.anim_player.play("idle")

func sync_anim() -> void:
	(player as VsPlayer).anim_player.play("idle")

func physics_update(delta: float, input: InputState) -> StringName:
	_apply_gravity(delta)
	_apply_ground_move(delta, input)

	if not _grounded():
		return &"vsfall"

	var vs := player as VsPlayer
	if input.attack:
		return &"vsattack"
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"
	if input.guard:
		return &"vsguard"
	if input.jump:
		return &"vsjump"
	if input.move_dir != 0.0:
		return &"vsrun"
	return &""
