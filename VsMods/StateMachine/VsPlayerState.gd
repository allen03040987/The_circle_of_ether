## VsPlayerState — 玩家狀態共用常數與輔助方法
class_name VsPlayerState
extends VsState

const GRAVITY    := 980.0   # px/s²
const MOVE_SPEED := 150.0   # px/s（地面）
const AIR_SPEED  := 130.0   # px/s（空中）
const FRICTION   := 900.0   # px/s²（地面減速，目前只有攻擊慣性衰減在用）
const JUMP_FORCE := -420.0  # px/s（負號朝上）

## 確定性地面判定：讀 VsPlayer.grounded（隨快照保存），不用 is_on_floor()——
## 後者只反映最後一次真正的 move_and_slide，快照還原後是過期值 → rollback desync
func _grounded() -> bool:
	return (player as VsPlayer).grounded

func _apply_gravity(delta: float) -> void:
	if not _grounded():
		player.velocity.y += GRAVITY * delta

func _apply_ground_move(_delta: float, input: InputState) -> void:
	if input.move_dir != 0.0:
		player.velocity.x = input.move_dir * MOVE_SPEED
		# facing_dir 在 VsPlayer 上
		(player as VsPlayer).facing_dir = int(sign(input.move_dir))
	else:
		player.velocity.x = 0.0   # 放開方向鍵直接停下，不滑行

func _apply_air_move(input: InputState) -> void:
	if input.move_dir != 0.0:
		player.velocity.x = input.move_dir * AIR_SPEED
		(player as VsPlayer).facing_dir = int(sign(input.move_dir))

## 恢復狀態（衝刺/硬直/起身/防禦…）結束時的共用收尾：地面且有方向輸入 → 直接
## 接 vsrun（支援跑步預輸入，不強制先「無腦」進 idle 一幀）；地面無輸入 → vsidle；
## 未落地 → vsfall。攻擊收招刻意不用這個（規則：攻擊不需要支援預輸入）。
func _recovery_transition(input: InputState) -> StringName:
	if not _grounded():
		return &"vsfall"
	if input.move_dir != 0.0:
		(player as VsPlayer).facing_dir = int(sign(input.move_dir))
		return &"vsrun"
	return &"vsidle"
