class_name VsIdle
extends VsPlayerState

func enter(_prev: StringName) -> void:
	(player as VsPlayer).anim_player.play("idle")

func sync_anim() -> void:
	(player as VsPlayer).anim_player.play("idle")

func physics_update(delta: float, input: InputState) -> StringName:
	_apply_gravity(delta)
	_apply_ground_move(delta, input)

	if not player.is_on_floor():
		return &"vsfall"

	var vs := player as VsPlayer
	if input.attack:
		return &"vsattack"
	if input.dodge and vs.use_energy(15.0):
		return &"vsdodge"
	if input.guard:
		return &"vsguard"
	if input.jump:
		return &"vsjump"
	if input.move_dir != 0.0:
		return &"vsrun"
	return &""
