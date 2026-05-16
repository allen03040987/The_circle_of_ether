class_name BossRetreatAttackState
extends BossState

# 招式參數設定
@export var retreat_duration: float = 0.6 # 後跳持續時間

var current_phase: String = "retreat"
var timer: float = 0.0

# ==========================================
# 🎬 狀態初始化
# ==========================================
func enter() -> void:
	current_phase = "retreat"
	timer = retreat_duration
	
	# 1. 鎖定玩家面向 (這決定了後跳的方向)
	boss.face_player() 
	
	# 2. 播放後跳/閃避動畫 (如果沒有專屬的，可以用 walk 或 idle 替代，主要是物理上有後退感)
	boss.play_safe_anim("dash_back")
	

# ==========================================
# 🏃 物理更新與階段派生
# ==========================================
func physics_update(delta: float) -> void:
	# 重力是永恆的
	boss.velocity.y += boss.default_gravity * delta
	
	if current_phase == "retreat":
		_handle_retreat(delta)
	elif current_phase == "attack":
		_handle_attack(delta)
		
	# ✅ 遵守最高指導原則！
	boss.custom_move_and_slide()

# --- 階段 1：後跳遠離 ---
func _handle_retreat(delta: float) -> void:
	timer -= delta
	
	if timer <= 0:
		var roll = randf() # 擲骰子
		
		# 🔴 30% 機率：後撤接 A5 突刺！(極具壓迫感的回馬槍)
		if roll < 0.30:
			state_machine.transition_to("DashAttack")
			
		# 🟡 30% 機率：原本的 A4 劈砍 (帶 3 根地刺)
		elif roll < 0.60:
			current_phase = "attack"
			boss.play_safe_anim("attack_4")
			
		# 🟢 20% 機率：後撤接 A6 蔓延地刺 (逼迫玩家跳躍或翻滾)
		elif roll < 0.80:
			# 利用大腦的標籤系統，把 A6 的指令傳給近戰狀態
			boss.set_meta("next_melee", "A6")
			state_machine.transition_to("MeleeAttack")
			
		# ⚪ 20% 機率：無作為 (單純拉開距離，退回大腦重新觀察)
		else:
			state_machine.transition_to("Decision")

# --- 階段 2：煞車與劈砍 ---
func _handle_attack(delta: float) -> void:
	# 攻擊時的腳步摩擦力煞車 (讓他停下來砍，或甚至給一點微小的向前衝力)
	boss.velocity.x = move_toward(boss.velocity.x, 0.0, boss.acceleration * delta)
	
	# 動畫播完就退回大腦決策
	if not boss.animation_player.is_playing():
		state_machine.transition_to("Decision")

# ==========================================
# 🛡️ 狀態離開防呆
# ==========================================
func exit() -> void:
	boss.disable_hitbox()
