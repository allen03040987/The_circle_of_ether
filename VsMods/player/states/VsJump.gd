class_name VsJump
extends VsPlayerState

const JUMP_SFX := preload("res://sound/SFX/jump.wav")

func enter(_prev: StringName) -> void:
	player.velocity.y = (player as VsPlayer).effective_jump_force()
	(player as VsPlayer).anim_player.play("jump")
	(player as VsPlayer).vfx_sfx(JUMP_SFX, -10.0)

func sync_anim() -> void:
	(player as VsPlayer).anim_player.play("jump")

func physics_update(delta: float, input: InputState) -> StringName:
	_apply_gravity(delta)
	_apply_air_move(input)

	var vs := player as VsPlayer
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"
	var art_transition := _check_art_cast(input)
	if art_transition != &"":
		return art_transition
	if input.attack and not vs.air_attack_used:
		return &"vsairattack"

	if player.velocity.y >= 0.0:
		return &"vsfall"
	return &""
