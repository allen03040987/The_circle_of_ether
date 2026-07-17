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

## 武藝施放共用檢查（規則：可打斷普攻施放，權限僅次衝刺/防禦）。任何狀態的
## physics_update() 在打斷優先權合適的位置呼叫這個——有輸入、對應槽位有裝
## 武藝、地面限制符合（can_use_in_air）、能量夠、而且不是同一招正在施放中
## （連按同招不重啟，比照主遊戲 is_same_art_still_running 的防呆）—— 全部
## 成立才會扣能量並回傳武藝的狀態名稱（"vsart1"/"vsart2"/"vsart3"）；不然
## 回傳空字串代表不觸發，呼叫端跟平常一樣把空字串當「維持原狀態」處理。
func _check_art_cast(input: InputState) -> StringName:
	var vs := player as VsPlayer
	var slot := 0
	if input.art_1:   slot = 1
	elif input.art_2: slot = 2
	elif input.art_3: slot = 3
	if slot == 0:
		return &""

	var art := vs.get_art_in_slot(slot)
	if art == null:
		return &""
	if not art.can_use_in_air and not _grounded():
		return &""
	if vs.state_machine.current_state == art:
		return &""   # 連按同一招不重啟
	if not vs.use_arts_energy(art.energy_cost):
		return &""

	return StringName("vsart%d" % slot)
