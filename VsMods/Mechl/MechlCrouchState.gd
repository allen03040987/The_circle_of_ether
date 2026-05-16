class_name MechlCrouchState
extends VsPlayerState

# 繼承基礎設定，蹲下當然可以防禦！
func _ready() -> void:
	can_block = true 

var crouch_stack_timer: float = 0.0
var ultimate_hold_timer: float = 0.0

@export var big_slash_state: VsState # 🌟 在 Inspector 把你的大砍刀狀態拖進來！

func enter() -> void:
	player.velocity.x = 0.0
	player.animation.play("crouch") # 替換成機鎧的蹲下動畫
	
	crouch_stack_timer = 2.0
	ultimate_hold_timer = 20.0

func process_physics(delta: float) -> VsState:
	var interrupt = check_interrupts()
	if interrupt != null: return interrupt

	# ==========================================
	# ⏳ 1. 常規納刀：每 2 秒集一層
	# ==========================================
	if player.current_sheathe_stacks < player.max_sheathe_stacks:
		crouch_stack_timer -= delta
		if crouch_stack_timer <= 0.0:
			player._add_sheathe_stack(true) # true 代表蹲下疊層
			crouch_stack_timer = 2.0        # 重置計時器繼續疊
			
			# 給個小特效或閃光提示玩家疊層了
			player.play_camera_shake(3.0, 0.1)

	# ==========================================
	# ⏳ 2. 終極憋氣：滿 5 層後倒數 20 秒
	# ==========================================
	if player.current_sheathe_stacks == 5 and not player.keep_sheathe_stand:
		ultimate_hold_timer -= delta
		if ultimate_hold_timer <= 0.0:
			player.keep_sheathe_stand = true
			print("✨ 納刀大成！獲得帶刀起身特權！")
			player.play_camera_shake(10.0, 0.2) # 大震動提示

	# ==========================================
	# ⚔️ 3. 鬆開判定：起身或派生大砍刀！
	# ==========================================
	if not Input.is_action_pressed(player.down_key):
		
		# 條件：滿 5 層，但「還沒撐過 20 秒 (特權未開啟)」 ➡️ 提前鬆手！
		if player.current_sheathe_stacks == 5 and not player.keep_sheathe_stand:
			if big_slash_state != null:
				print("💥 提前鬆手！強制派生大砍刀！")
				return big_slash_state
		
		# 其他情況：正常站起來 (包含已經獲得帶刀起身特權)
		return state_machine.idle_state
		
	return null
