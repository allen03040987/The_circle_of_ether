class_name ClottySkill_K1
extends VsPlayerState

# ==========================================
# ⏱️ 一刀兩斷 (Time Stop Slash)
# ==========================================
@export_group("⚙️ 技能參數")
@export var mp_cost: float = 33.3 
@export var cd_time: float = 30.0               # 🌟 大招冷卻時間
@export var slot_id: String = "UI_Ult_1"

var is_waiting_for_second_part: bool = false

func can_cast() -> bool:
	if not player.is_on_floor(): return false 
	if player.current_mp < mp_cost: return false 
	# 🌟 新增：檢查冷卻好了沒
	if not player.is_skill_ready(slot_id): return false 
	return true

func enter() -> void:
	is_waiting_for_second_part = true 
	
	# 🌟 新增：扣魔力的同時，啟動冷卻！
	player.start_cooldown(slot_id, cd_time)
	
	player.auto_face_opponent()
	player.current_mp -= mp_cost
	
	player.play_safe_anim("skill_u_start") 
	player.velocity.x = 0.0
	
	_trigger_delayed_cinematic()

# 🎬 專屬過場導演系統 (純單機版)
func _trigger_delayed_cinematic() -> void:
	await get_tree().create_timer(0.2).timeout
	
	if state_machine.current_state != self:
		return
		
	# 確保畫面推到了最後一幀
	player.animation.seek(0.5, true)
	
	# 🌟 啟動 1.2 秒時停黑幕與特寫 (呼叫老爸的單機版時停)
	player.play_ultimate_cinematic(1.2, true)
	
	await get_tree().create_timer(1.55, true, false, true).timeout
	
	if state_machine.current_state == self:
		is_waiting_for_second_part = false
		# 🎬 2. 播放「第二段」揮刀動畫
		player.play_safe_anim("skill_u")

func exit() -> void:
	player.deactivate_all_hitboxes()
	is_waiting_for_second_part = false 
	
	# 🌟 單機版：直接把鏡頭拉回 1.0
	get_tree().call_group("camera", "cinematic_zoom", player, 1.0, 0.2)
	
func process_physics(delta: float) -> VsState:
	var interrupt = check_interrupts()
	if interrupt != null:
		return interrupt
		
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.ground_friction * delta)
	player.custom_move_and_slide() 
	
	if not player.animation.is_playing() and not is_waiting_for_second_part:
		return state_machine.idle_state
		
	return null
