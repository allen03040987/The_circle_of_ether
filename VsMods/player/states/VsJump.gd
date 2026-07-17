class_name VsJump
extends VsPlayerState

func enter(_prev: StringName) -> void:
	player.velocity.y = JUMP_FORCE
	(player as VsPlayer).anim_player.play("jump")

func sync_anim() -> void:
	(player as VsPlayer).anim_player.play("jump")

func physics_update(delta: float, input: InputState) -> StringName:
	_apply_gravity(delta)
	_apply_air_move(input)

	var vs := player as VsPlayer
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"
	if input.attack:
		return &"vsairattack"

	if player.velocity.y >= 0.0:
		return &"vsfall"
	return &""
