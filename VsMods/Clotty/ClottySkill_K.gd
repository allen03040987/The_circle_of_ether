class_name ClottySkill_K
extends VsPlayerState

# ==========================================
# 💀 死亡切割
# ==========================================
@export_group("⚙️ 技能參數")
@export var mp_cost: float = 33.3          
@export var forward_speed: float = 200.0   
@export var friction_rate: float = 0.1     
@export var ghost_color: Color = Color(0.4, 0.9, 0.6, 0.5) 

var ghost_spawn_timer: float = 0.0

@export_group("🔗 派生連段設定")
@export var attack4_state: VsState    
@export var hitbox_node: VsHitbox     

var is_dashing: bool = false
var hit_confirmed: bool = false 

func can_cast() -> bool:
	if not player.is_on_floor(): return false 
	if player.current_mp < mp_cost: return false 
	return true      

func enter() -> void:
	player.current_mp -= mp_cost
	player.animation.play("skill_K") 
	
	var facing_dir = player.get_node("Graphics").scale.x
	player.velocity.x = facing_dir * forward_speed
	
	is_dashing = true
	hit_confirmed = false        
	player.set_can_combo(false) 
	
	# 洗掉這把刀的記憶
	if hitbox_node != null and "hit_targets" in hitbox_node:
		hitbox_node.hit_targets.clear()
		
	player.set_pass_through(true)

func exit() -> void:
	player.set_pass_through(false)
	player.deactivate_all_hitboxes()

func process_physics(delta: float) -> VsState:
	var interrupt = check_interrupts()
	if interrupt != null:
		return interrupt
		
	# 突進煞車處理
	if is_dashing:
		player.velocity.x = move_toward(player.velocity.x, 0.0, player.ground_friction * friction_rate * delta)
		ghost_spawn_timer -= delta
		if ghost_spawn_timer <= 0.0:
			player.spawn_afterimage(ghost_color, 0.3, Vector2(0, -20))
			ghost_spawn_timer = 0.04 
		if abs(player.velocity.x) < 10.0:
			is_dashing = false
			
	player.custom_move_and_slide()
	
	# 🌟 打擊確認 (Hit Confirm)
	if hitbox_node != null and hitbox_node.hit_targets.size() > 0:
		hit_confirmed = true
		
	if hit_confirmed and player.can_combo and Input.is_action_just_pressed(player.attack_key):
		if attack4_state != null:
			return attack4_state # 強制切換到普攻第四段！
			
	if not player.animation.is_playing():
		return state_machine.idle_state
		
	return null
