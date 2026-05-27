extends State
## 閃避/滑行狀態 (Slide State)
## 處理一般閃避位移、殘影特效，並包含遭攻擊瞬間觸發的「極限閃避 (魔女時間)」機制。

const sliding_SFX = preload("res://sound/SFX/sliding.wav")
const Successfully_SFX = preload("res://sound/SFX/Successfully_dodged.wav")

# 基礎物理變數
var dodge_dir: float
var ghost_timer: float = 0.0
var current_speed: float = 400.0 

# 魔女時間專用鎖
var has_perfect_dodged: bool = false 
var is_locked: bool = false # 當觸發極限閃避時，將角色鎖在這個狀態中，延長閃避動畫

# 🌟 方向記憶體：用來記住玩家在閃避時偷偷按下的方向鍵，供閃避結束後的下一個動作使用
var buffered_direction: int = 0 

# ==========================================
# 🎬 狀態生命週期：進入狀態
# ==========================================
func enter() -> void:
	# 🌟 改動：不要馬上播，呼叫延遲播放函數
	_play_delayed_sfx()
		
	if player.scabbard:
		player.scabbard.fade_in()
	
	player.play_safe_anim("sliding")
	
	# 重置內部狀態
	has_perfect_dodged = false
	is_locked = false
	buffered_direction = 0 
	ghost_timer = 0.0
	current_speed = 400.0 # 一般閃避的高速
	
	# 🧭 智能方向判定
	if player.is_on_wall():
		# 牆邊閃避：強制朝向遠離牆壁的方向閃，防止卡牆
		var wall_normal = player.get_wall_normal().x
		dodge_dir = sign(wall_normal) if wall_normal != 0 else -player.direction
	else:
		# 平地閃避：有按方向就照方向，沒按方向就照目前面朝方向
		var movement := Input.get_axis("move_left", "move_right")
		dodge_dir = sign(movement) if not is_zero_approx(movement) else player.direction
			
	# 強制轉身面向閃避方向
	player.direction = player.Direction.LEFT if dodge_dir < 0 else player.Direction.RIGHT

	# 停止閃避預輸入，扣除體力，並開始閃避 CD
	player.slide_request_timer.stop()
	player.stats.energy -= 3
	player.slide_cooldown_timer.start()

# ==========================================
# 🏃 物理更新 (每秒 60 次)
# ==========================================
func physics_update(delta: float) -> void:
	# 🌟 絕對特權：大招可以強行打斷閃避！
	# (這是動作遊戲的王道設定，確保玩家隨時可以甩大招保命)
	if player.is_ult_requested:
		state_machine.transition_to("WeaponAttack")
		return
		
	# 執行位移 (Y軸鎖死，強制水平移動)
	player.velocity.x = dodge_dir * current_speed
	player.velocity.y = 0 
	player.custom_move_and_slide()
	
	# 👻 殘影生成系統 (每 0.05 秒拉出一個殘影)
	ghost_timer += delta
	if ghost_timer >= 0.05:
		player.add_ghost()
		ghost_timer = 0.0

	# 偷偷記錄玩家按下的方向，為接下來的動作做準備
	var move_input = Input.get_axis("move_left", "move_right")
	if not is_zero_approx(move_input):
		buffered_direction = sign(move_input)
	
	# ⚔️ 核心預輸入：劫持攻擊判定
	if Input.is_action_just_pressed("attack"):
		# 🌟 修改：廢除獨立的反擊衍生，無論是一般閃避還是完美閃避，全部視為常規連段預輸入！
		player.is_combo_requested = true
			
	# ==========================================
	# 🚦 狀態切換決策 (狀態結算)
	# ==========================================
	# 只有在動畫播完，而且「沒有被極限閃避鎖住」的情況下，才允許結束閃避
	if not player.animation_player.is_playing() and not is_locked:
		if player.is_on_floor():
			state_machine.transition_to("Idle")
		else:
			state_machine.transition_to("Fall")

# ==========================================
# 🚪 狀態生命週期：離開狀態
# ==========================================
func exit() -> void:
	# 閃避結束時，強制煞車 (保留 50% 慣性)，讓手感更俐落
	player.velocity.x *= 0.5
	player.is_perfect_dodging = false

	# 🌟 新增：如果閃避結束時玩家沒有按下攻擊（沒有預輸入連段），則清除連段偏移快取
	if not player.is_combo_requested:
		player.remove_meta("dodge_offset")
		player.remove_meta("saved_combo_step")

# ==========================================
# ⚡ 極限閃避觸發器 (由 Player.gd 裡的受擊系統呼叫)
# ==========================================
func trigger_perfect_dodge() -> void:
	if has_perfect_dodged: return 
		
	if Successfully_SFX:
		AudioManager.play_sfx(Successfully_SFX, -10.0, 1.0)
		
	# 1. 啟動魔女時間專屬標記與鎖定
	has_perfect_dodged = true
	is_locked = true 
	
	# 2. 改變動畫與速度
	player.play_safe_anim("perfect_dodge") 
	current_speed = 100.0 # 進入魔女時間後，閃避位移大幅減弱，營造頓挫感
	
	# 3. 呼叫大腦的「泛用時停系統」
	# 🌟 這種寫法極其安全，就算大招時停也正在運作，大腦會自己判斷誰的優先級高！
	if player.has_method("trigger_time_stop"):
		player.trigger_time_stop(0.5, 0.3) 
	else:
		Engine.time_scale = 0.3 # 防呆
		
	# 4. 變色特效 (抗時停寫法)
	var tween = create_tween()
	var speed_mult = 1.0 / 0.3 
	tween.set_speed_scale(speed_mult) 
	tween.set_parallel(true)
	tween.tween_property(player.graphics, "modulate:r", 1.0, 0.5)
	tween.tween_property(player.graphics, "modulate:g", 1.0, 0.5)
	tween.tween_property(player.graphics, "modulate:b", 1.0, 0.5)
	
	# 🌟 核心修改 2：把定時炸彈拆掉！不要在這裡強行恢復時間！
	# 時間到了，Player.gd 的 _process 會自動處理。我們這裡只解除閃避鎖定。
	CombatManager.get_skill_timer(0.5).timeout.connect(
		func(): 
			is_locked = false 
	)
	
	player.stats.energy += 3 
	player.invincible_timer.start(0.5)
	player.is_perfect_dodging = true
	
	if CombatManager.has_method("spawn_dodge_spark"):
		CombatManager.spawn_dodge_spark(player.global_position)

# ==========================================
# 🎵 延遲音效處理
# ==========================================
func _play_delayed_sfx() -> void:
	# 稍微等待 0.05 秒 (大約 3 幀)
	await get_tree().create_timer(0.01).timeout
	
	# 🌟 核心防護：確保過了這 3 幀之後，玩家「還在閃避狀態」，且「沒有觸發魔女時間」，才播一般的閃避聲！
	if state_machine.current_state == self and not has_perfect_dodged:
		if sliding_SFX:
			AudioManager.play_sfx(sliding_SFX, -10.0, 1.0)
