class_name VsPlayerAirAttack
extends VsPlayerState

@export_group("⏳ 冷卻與圖標設定")
# (💡 注意：這裡的 cd_time 在 enter 裡已經用不到了，因為 ready 裡有設過 max 值)
@export var slot_id: String = "UI_Skill_A" # 把原本的 "Attack_Air" 換成這句

var ghost_color: Color = Color(0.4, 0.9, 0.6, 0.5) 
var ghost_spawn_timer: float = 0.0

func can_cast() -> bool:
	# 🌟 老爸會自動檢查 charges > 0
	if not player.is_skill_ready(slot_id): return false
	return true

func enter() -> void:
	super.enter()
	
	# 🌟 新增：進入狀態時，消耗一層！(老爸的 start_cooldown 會自動處理charges -= 1)
	player.start_cooldown(slot_id, 0.0) # 此處 duration 傳 0 即可
	
	player.velocity.y = 0.0 
	player.animation.play("air_attack") 
	
	if player.has_node("Hitboxes/AirAttackHitbox"):
		player.get_node("Hitboxes/AirAttackHitbox").set_deferred("monitoring", true)

func exit() -> void:
	player.deactivate_all_hitboxes()
	
func process_physics(delta: float) -> VsState:
	var interrupt = check_interrupts()
	if interrupt != null:
		return interrupt
	
	# ✈️ 浮空與殘影
	player.velocity.y = 0.0 
	ghost_spawn_timer -= delta
	if ghost_spawn_timer <= 0.0:
		player.spawn_afterimage(ghost_color, 0.3, Vector2(0, -20))
		ghost_spawn_timer = 0.04 

	player.velocity.x = move_toward(player.velocity.x, 0.0, player.air_friction * delta)
	player.custom_move_and_slide()
	
	# 🎯 結束條件判定
	if player.is_on_floor():
		player.velocity.x = 0
		player.jump_count = 0 
		return state_machine.idle_state
		
	if not player.animation.is_playing():
		return state_machine.fall_state
		
	return null
