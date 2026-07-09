extends State
## 滑牆狀態 (Wall Slide State)
## 當角色在空中接觸牆壁，且持續朝牆壁方向推動搖桿時觸發。

# 🔒 鎖定的牆壁法線 (Wall Normal)
# 牆壁法線就是「垂直於牆壁朝外的方向」。例如在右邊的牆上，法線是向左(-1)。
# 🌟 秘訣 1：絕對不要在 physics_update 裡每幀重抓！
# 如果牆壁是由多塊 Tile 拼成的，接縫處的法線可能會瞬間算錯，導致角色掉下來。
var locked_wall_normal: float

# 🎵 🌟 滑牆音效專用變數
const SLIDE_SFX = preload("res://sound/SFX/slide.wav") # 👈 請換成你的音檔路徑
var slide_audio_player: AudioStreamPlayer

# ==========================================
# 🎬 狀態生命週期：進入狀態
# ==========================================
func enter() -> void:
	player.play_safe_anim("wall_sliding")
	
	# 🎯 抓取並鎖定法線 (只在進入的瞬間抓一次)
	locked_wall_normal = player.get_wall_normal().x
	
	# 🧭 強制設定獨立的射線 (wall_slide_checker) 指向牆壁內部
	# Godot 內建的 is_on_wall() 有時候會抽風，我們用這根實體射線作為雙重保險
	var wall_dir := Vector2(-locked_wall_normal, 0)
	player.wall_slide_checker.target_position = wall_dir * 20
	player.wall_slide_checker.force_raycast_update()
	
	# 🌟 決定面向：滑牆時，身體永遠面向與牆壁相反的方向 (背對或側對牆壁)
	player.direction = player.Direction.LEFT if locked_wall_normal < 0 else player.Direction.RIGHT
	
	# 🎵 🌟 動態生成滑牆音效播放器，並預設為靜音播放
	slide_audio_player = AudioStreamPlayer.new()
	slide_audio_player.stream = SLIDE_SFX
	slide_audio_player.bus = "SFX"
	slide_audio_player.volume_db = -60.0 # 人類聽不到的音量
	add_child(slide_audio_player)
	slide_audio_player.play()
	
# ==========================================
# 🏃 物理更新 (每秒 60 次)
# ==========================================
func physics_update(delta: float) -> void:
	var movement := Input.get_axis("move_left", "move_right")
	
	# 🌟 秘訣 2：補回水平推力！
	# 必須讓玩家能持續往牆壁「擠」，系統的 is_on_wall() 才會判定為 true，才不會掉下來！
	player.velocity.x = move_toward(player.velocity.x, movement * player.RUN_SPEED, player.AIR_ACCELERATION * delta)
	
	# 1. 🍎 處理摩擦力重力：滑牆時的重力只有平常的 1/4 ( default_gravity / 4.0 )
	player.velocity.y += (player.default_gravity / 4.0) * delta
	
	# 2. 🛑 滑牆速度控制
	if state_machine.state_time < 0.15 and player.velocity.y < 0:
		# 如果角色原本是往上飛的 (例如往上跳撞到牆)，先快速消除向上的力量，讓他「黏」住
		player.velocity.y *= 0.8
	else:
		# 限制最高下滑速度 (170.0)，這就是為什麼能在牆上慢慢滑的原因
		player.velocity.y = min(player.velocity.y, 170.0)
		
	player.custom_move_and_slide()
	
	# 🎵 🌟 滑牆音效無縫漸變邏輯
	if is_instance_valid(slide_audio_player):
		var target_volume = -60.0 # 預設目標為靜音
		
		# 只有當角色「往下墜 (velocity.y > 10)」且「貼在牆上」時，才會有摩擦聲
		if player.velocity.y > 10.0 and player.is_on_wall():
			target_volume = -10.0 # 目標音量 (你可以自己微調，例如 -5.0 或 -15.0)
			
		# 每幀將目前音量往目標音量拉近。80.0 代表每秒漸變 80 分貝 (大約 0.6 秒可以完成漸出入)
		slide_audio_player.volume_db = move_toward(
			slide_audio_player.volume_db, 
			target_volume, 
			80.0 * delta
		)
		
	# ==========================================
	# 🚦 狀態切換決策
	# ==========================================
	
	# ⚡ 閃避 (離開牆壁)
	if player.slide_request_timer.time_left > 0 and player.stats.energy >= 3:
		if player.slide_cooldown_timer.is_stopped():
			state_machine.transition_to("Slide")
			return

	# 預輸入：格擋
	if player.guard_request_timer.time_left > 0:
		state_machine.transition_to("Guard")
		return

	# 🚀 牆跳
	if player.jump_request_timer.time_left > 0:
		state_machine.transition_to("WallJump")
		return
		
	# 🌍 落地
	if player.is_on_floor():
		state_machine.transition_to("Idle")
		return
		
	# 🕳️ 脫離牆壁：玩家主動放開方向鍵，或者射線離開了牆壁 (例如牆壁到底了)
	if not player.is_on_wall() or not player.wall_slide_checker.is_colliding():
		state_machine.transition_to("Fall")
		
# ==========================================
# 🎬 狀態生命週期：離開狀態
# ==========================================
func exit() -> void:
	# 🎵 離開牆壁時，讓摩擦聲在 0.2 秒內快速收尾並銷毀喇叭！
	if is_instance_valid(slide_audio_player):
		var tween = create_tween()
		tween.tween_property(slide_audio_player, "volume_db", -60.0, 0.2)
		# Tween 結束後，把這個免洗喇叭清掉，不留記憶體垃圾
		tween.tween_callback(slide_audio_player.queue_free)
