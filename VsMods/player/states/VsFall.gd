class_name VsFall
extends VsPlayerState

func enter(_prev: StringName) -> void:
	(player as VsPlayer).anim_player.play("fall")

func physics_update(delta: float, input: InputState) -> StringName:
	_apply_gravity(delta)
	_apply_air_move(input)

	var vs := player as VsPlayer
	if input.dodge and vs.use_energy(15.0):
		return &"vsdodge"

	if player.is_on_floor():
		if input.move_dir != 0.0:
			return &"vsrun"
		return &"vsidle"
	return &""
