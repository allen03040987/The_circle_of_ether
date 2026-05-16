class_name ClottySkill_AirU
extends VsPlayerState

# ==========================================
# ⚔️ 空中大招 (空中微浮空 + 時停 + 7連發劍氣)
# ==========================================
@export_group("⚙️ 技能參數")
@export var mp_cost: float = 33.3          
@export var float_speed: float = 50.0      
@export var aura_count: int = 7            
@export var aura_interval: float = 0.1     
@export var ultimate_aura_scene: PackedScene

@export_group("⏳ 冷卻與圖標設定")
@export var cd_time: float = 30.0               # 🌟 大招冷卻時間
@export var slot_id: String = "UI_Ult_2"

var is_waiting_for_second_part: bool = false
var is_firing: bool = false

func can_cast() -> bool:
	if player.is_on_floor(): return false 
	if player.current_mp < mp_cost: return false 
	# 🌟 新增：檢查冷卻
	if not player.is_skill_ready(slot_id): return false 
	return true

func enter() -> void:
	is_waiting_for_second_part = true 
	is_firing = false
	
	# 🌟 新增：啟動大招冷卻！
	player.start_cooldown(slot_id, cd_time)
	
	player.auto_face_opponent()
	player.current_mp -= mp_cost
	
	player.velocity.x = 0.0
	player.velocity.y = float_speed 
	player.play_safe_anim("skill_u_2_strat") 
	
	_trigger_delayed_cinematic()

func _trigger_delayed_cinematic() -> void:
	await get_tree().create_timer(0.1).timeout
	
	if state_machine.current_state != self:
		return
		
	player.animation.seek(0.5, true)
	player.play_ultimate_cinematic(1.2, true)
	
	await get_tree().create_timer(1.55, true, false, true).timeout
	
	if state_machine.current_state == self:
		is_waiting_for_second_part = false
		player.play_safe_anim("skill_u_2")
		_fire_auras()

# 🚀 劍氣機關槍系統 (單機版)
func _fire_auras() -> void:
	is_firing = true
	
	for i in range(aura_count):
		if state_machine.current_state != self:
			break
			
		player.shoot_custom_projectile(ultimate_aura_scene)
		player.velocity.y = -20.0 
		
		if i < aura_count - 1:
			await get_tree().create_timer(aura_interval, false, false, true).timeout
			
	is_firing = false

func exit() -> void:
	player.deactivate_all_hitboxes()
	is_waiting_for_second_part = false 
	is_firing = false
	
	# 單機直接拉回鏡頭
	get_tree().call_group("camera", "cinematic_zoom", player, 1.0, 0.2)
	
func process_physics(delta: float) -> VsState:
	var interrupt = check_interrupts()
	if interrupt != null:
		return interrupt
		
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.air_friction * delta)
	player.velocity.y = move_toward(player.velocity.y, float_speed, 1500.0 * delta)
	
	player.custom_move_and_slide() 
	
	if not player.animation.is_playing() and not is_waiting_for_second_part and not is_firing:
		if player.is_on_floor():
			return state_machine.idle_state 
		else:
			return state_machine.fall_state 
			
	return null
