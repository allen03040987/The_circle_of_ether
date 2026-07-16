class_name VsRun
extends VsPlayerState

func enter(_prev: StringName) -> void:
	(player as VsPlayer).anim_player.play("running")

func sync_anim() -> void:
	(player as VsPlayer).anim_player.play("running")

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
	if input.move_dir == 0.0 and absf(player.velocity.x) < 1.0:
		return &"vsidle"
	return &""
