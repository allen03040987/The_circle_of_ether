extends State
## 跑動煞車滑行 (Run Stop)
## 從 Run 放開移動鍵的瞬間，不直接卡死回 Idle，而是讓水平速度在動畫前 SLIDE_DURATION 秒內
## 從放開當下的速度線性滑到 0，做出「煞不住車」的滑行感；滑完之後原地停住，把剩下的動畫撥完
## 才真的轉去 Idle（動畫之後補上，暫定 anim 名稱 "run_stop"）。
## 期間任何操作（移動、跳躍、閃避、格擋、攻擊）都能直接打斷，不會卡住手感。

const SLIDE_DURATION: float = 0.3

var _start_speed: float = 0.0
var _elapsed: float = 0.0

func enter() -> void:
	_start_speed = player.velocity.x
	_elapsed = 0.0
	player.animation_player.stop()
	player.play_safe_anim("run_stop")

func physics_update(delta: float) -> void:
	_elapsed += delta
	var t = clampf(_elapsed / SLIDE_DURATION, 0.0, 1.0)
	player.velocity.x = lerp(_start_speed, 0.0, t)

	if not player.is_on_floor():
		player.velocity.y += player.default_gravity * delta
	player.custom_move_and_slide()

	# ==========================================
	# 🚦 狀態切換決策：任何操作都能直接打斷煞車滑行
	# ==========================================
	var movement := Input.get_axis("move_left", "move_right")
	if not is_zero_approx(movement):
		state_machine.transition_to("Run")
		return

	if not player.is_on_floor():
		player.coyote_timer.start()
		state_machine.transition_to("Fall")
		return

	if player.jump_request_timer.time_left > 0:
		state_machine.transition_to("Jump")
		return

	if player.slide_request_timer.time_left > 0 and player.stats.energy >= 3:
		if player.slide_cooldown_timer.is_stopped():
			state_machine.transition_to("Slide")
			return

	if player.guard_request_timer.time_left > 0:
		state_machine.transition_to("Guard")
		return

	if player.is_combo_requested or player.is_heavy_requested:
		state_machine.transition_to("WeaponAttack")
		return

	# 滑行只佔動畫前段，速度歸零後原地把剩下的動畫撥完，撥完才真的回 Idle
	if not player.animation_player.is_playing():
		state_machine.transition_to("Idle")
