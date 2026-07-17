class_name VsFall
extends VsPlayerState

func enter(_prev: StringName) -> void:
	(player as VsPlayer).anim_player.play("fall")

func sync_anim() -> void:
	(player as VsPlayer).anim_player.play("fall")

func physics_update(delta: float, input: InputState) -> StringName:
	_apply_gravity(delta)
	_apply_air_move(input)

	var vs := player as VsPlayer
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"

	if _grounded():
		return _recovery_transition(input)
	return &""
