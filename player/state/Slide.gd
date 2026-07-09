class_name SlideState
extends State
## 閃避/滑行狀態 (Slide State)
## 處理一般閃避位移、殘影特效，並包含「極限閃避 (魔女時間)」機制。

const SLIDING_SFX = preload("res://sound/SFX/sliding.wav")
const SLIDING_SFX_2 = preload("res://sound/SFX/sprint.wav")
const SLIDING_SFX_3 = preload("res://sound/SFX/attack/Wind_2.wav")
const SUCCESS_SFX = preload("res://sound/SFX/Successfully_dodged.wav")
const PERFECT_DODGE_MARTIAL_ENERGY: float = 1.0 ## 完美閃避給的武藝能量，比一般命中(0.2)高，獎勵技巧性回避

# ==========================================
# 📐 物理與控制變數
# ==========================================
var dodge_dir: float
var ghost_timer: float = 0.0
var current_speed: float = 400.0 
var buffered_direction: int = 0 

var has_perfect_dodged: bool = false 
var is_locked: bool = false 
var sfx_delay_timer: float = 0.0
var has_played_sfx: bool = false
# ==========================================
# 🎬 狀態生命週期
# ==========================================
func enter() -> void:
		
	if player.scabbard:
		player.scabbard.fade_in()
	
	player.play_safe_anim("sliding")
	
	has_perfect_dodged = false
	is_locked = false
	buffered_direction = 0 
	ghost_timer = 0.0
	current_speed = 400.0 
	
	sfx_delay_timer = 0.0
	has_played_sfx = false
	
	var movement := Input.get_axis("move_left", "move_right")
	dodge_dir = sign(movement) if not is_zero_approx(movement) else player.direction
	player.direction = player.Direction.LEFT if dodge_dir < 0 else player.Direction.RIGHT

	player.slide_request_timer.stop()
	player.stats.energy -= 3
	player.slide_cooldown_timer.start()

func physics_update(delta: float) -> void:
	# 只要狀態被切換，physics_update 就會停止執行，絕不會有幽靈音效跑出來！
	if not has_played_sfx and not has_perfect_dodged:
		sfx_delay_timer += delta
		if sfx_delay_timer >= 0.01:
			has_played_sfx = true
			if SLIDING_SFX_2: AudioManager.play_sfx(SLIDING_SFX_2, -12.0, 1.0)
			if SLIDING_SFX_3: AudioManager.play_sfx(SLIDING_SFX_3, -8.0, 1.0)
	player.velocity.x = dodge_dir * current_speed
	player.velocity.y = 0 
	player.custom_move_and_slide()
	
	ghost_timer += delta
	if ghost_timer >= 0.05:
		player.add_ghost(Color(1.0, 1.0, 1.0, 0.4))
		ghost_timer = 0.0

	var move_input = Input.get_axis("move_left", "move_right")
	if not is_zero_approx(move_input):
		buffered_direction = sign(move_input)
	
	if Input.is_action_just_pressed("attack"):
		player.is_combo_requested = true
			
	if not player.animation_player.is_playing() and not is_locked:
		if player.is_on_floor():
			state_machine.transition_to("Idle")
		else:
			state_machine.transition_to("Fall")

func exit() -> void:
	player.velocity.x *= 0.5

	# 🌟 閃避銜接移動：短暫的窗口內接著跑，Run.gd 會直接用全速奔跑起步，不用重新從走路開始爬升
	player.dash_chain_timer.start()

	if not player.is_combo_requested and not player.is_perfect_dodging:
		player.remove_meta("dodge_offset")
		player.remove_meta("saved_combo_step")

# ==========================================
# ⚡ 極限閃避觸發器 (魔女時間)
# ==========================================
func trigger_perfect_dodge() -> void:
	if has_perfect_dodged: return 
		
	if SUCCESS_SFX:
		AudioManager.play_sfx(SUCCESS_SFX, 0.0, 1.0)
		
	has_perfect_dodged = true
	is_locked = true 
	
	if player.has_meta("saved_combo_step"):
		player.set_meta("dodge_offset", true)
		player.set_meta("dodge_combo_deadline", Time.get_ticks_msec() + 1500)
		print("✨ [魔女時間] 獲得連段保留簽證！寬限期刷新為 1.5 秒！")
	
	player.play_safe_anim("perfect_dodge") 
	current_speed = 100.0 
	
	if player.has_method("trigger_time_stop"):
		player.trigger_time_stop(0.5, 0.3) 
	else:
		Engine.time_scale = 0.3 
		
	var tween = create_tween()
	var speed_mult = 1.0 / 0.3 
	tween.set_speed_scale(speed_mult) 
	tween.set_parallel(true)
	tween.tween_property(player.graphics, "modulate:r", 1.0, 0.5)
	tween.tween_property(player.graphics, "modulate:g", 1.0, 0.5)
	tween.tween_property(player.graphics, "modulate:b", 1.0, 0.5)
	
	CombatManager.get_skill_timer(0.5).timeout.connect(func(): is_locked = false)
	
	player.stats.energy += 3
	player.invincible_timer.start(0.5)
	player.is_perfect_dodging = true

	# 🔋 完美閃避才給武藝能量，單純按衝刺沒躲到攻擊不算——獎勵的是「躲過真正的攻擊」這個技巧
	if player.has_method("gain_martial_energy"):
		player.gain_martial_energy(PERFECT_DODGE_MARTIAL_ENERGY)
	
	if CombatManager.has_method("spawn_dodge_spark"):
		CombatManager.spawn_dodge_spark(player.global_position)
	
	if is_instance_valid(player.current_weapon) and player.current_weapon.has_method("gain_iai"):
		player.current_weapon.gain_iai(2)
