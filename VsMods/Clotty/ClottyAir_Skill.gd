class_name VsPlayerAirDiagonalSlash
extends VsPlayerState

@export_group("🚀 斜衝砍設定")
@export var dash_speed_x: float = 800.0  
@export var dash_speed_y: float = 800.0  
@export var max_dash_time: float = 0.15   
@export var bounce_force: float = -500.0 
# (💡 cd_time 的數值現在由 PlayerClotty.gd 的 ready 統一管控了)
@export var slot_id: String = "UI_Skill_B" # 🌟 換上萬用插槽制服！

var ghost_color: Color = Color(0.4, 0.9, 0.6, 0.5) 
var ghost_spawn_timer: float = 0.0
var dash_timer: float = 0.0
var is_landing: bool = false 
var locked_facing_dir: float = 1.0 

func can_cast() -> bool:
	if state_machine.current_state == self: return false 
	# 🌟 檢查有沒有層數
	if not player.is_skill_ready(slot_id): return false
	return true

func enter() -> void:
	player.auto_face_opponent()
	super.enter()
	dash_timer = 0.0
	is_landing = false 
	locked_facing_dir = player.get_node("Graphics").scale.x 
	
	# 🌟 進入狀態時消耗一層！
	player.start_cooldown(slot_id, 0.0) 
	
	player.play_safe_anim("air_skill") 
	
	if player.has_node("Hitboxes/DiagonalSlashHitbox"):
		player.get_node("Hitboxes/DiagonalSlashHitbox").set_deferred("monitoring", true)

func exit() -> void:
	player.deactivate_all_hitboxes()
	
func process_input(event: InputEvent) -> VsState:
	if not is_landing: return null 
	return super(event)
	
func process_physics(delta: float) -> VsState:
	if is_landing:
		player.velocity.x = move_toward(player.velocity.x, 0.0, player.ground_friction * delta)
		var interrupt = check_interrupts()
		if interrupt != null: return interrupt
			
		if not player.animation.is_playing():
			return state_machine.idle_state
		return null

	# 🚀 空中往下衝刺 (霸體 + 鎖死面向)
	player.get_node("Graphics").scale.x = locked_facing_dir
	dash_timer += delta
	player.velocity.x = dash_speed_x * locked_facing_dir
	player.velocity.y = dash_speed_y
	
	ghost_spawn_timer -= delta
	if ghost_spawn_timer <= 0.0:
		player.spawn_afterimage(ghost_color, 0.3, Vector2(0, -20))
		ghost_spawn_timer = 0.04 
		
	player.custom_move_and_slide()
	
	if player.is_on_floor():
		player.velocity.x = 0 
		player.deactivate_all_hitboxes() 
		is_landing = true 
		player.play_safe_anim("air_skill_end") 
		return null
		
	if dash_timer >= max_dash_time:
		player.velocity.x = 0 
		player.velocity.y = bounce_force 
		player.jump_count += 1
		return state_machine.fall_state 
		
	return null
