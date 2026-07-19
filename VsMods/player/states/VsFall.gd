class_name VsFall
extends VsPlayerState

const LAND_SFX := preload("res://sound/SFX/land.wav")

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
	var art_transition := _check_art_cast(input)
	if art_transition != &"":
		return art_transition
	if input.attack and not vs.air_attack_used:
		return &"vsairattack"

	if _grounded():
		vs.vfx_sfx(LAND_SFX, -10.0)
		return _recovery_transition(input)
	return &""
