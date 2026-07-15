## VsPlayerState — 玩家狀態共用常數與輔助方法
class_name VsPlayerState
extends VsState

const GRAVITY    := 980.0   # px/s²
const MOVE_SPEED := 150.0   # px/s（地面）
const AIR_SPEED  := 130.0   # px/s（空中）
const FRICTION   := 900.0   # px/s²（地面減速）
const JUMP_FORCE := -420.0  # px/s（負號朝上）

func _apply_gravity(delta: float) -> void:
	if not player.is_on_floor():
		player.velocity.y += GRAVITY * delta

func _apply_ground_move(delta: float, input: InputState) -> void:
	if input.move_dir != 0.0:
		player.velocity.x = input.move_dir * MOVE_SPEED
		# facing_dir 在 VsPlayer 上
		(player as VsPlayer).facing_dir = int(sign(input.move_dir))
	else:
		player.velocity.x = move_toward(player.velocity.x, 0.0, FRICTION * delta)

func _apply_air_move(input: InputState) -> void:
	if input.move_dir != 0.0:
		player.velocity.x = input.move_dir * AIR_SPEED
		(player as VsPlayer).facing_dir = int(sign(input.move_dir))
