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
	if input.skill:
		return &"vsskill"
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"
	var art_transition := _check_art_cast(input)
	if art_transition != &"":
		return art_transition
	if input.guard:
		return &"vsguard"
	if input.jump:
		return &"vsjump"
	if input.move_dir == 0.0:
		return &"vsidle"   # 放開方向鍵即停（_apply_ground_move 已把速度歸零）
	return &""
