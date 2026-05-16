class_name VsPlayerAttackState
extends VsPlayerState

## 攻擊狀態 (Attack State)
## 處理招式動畫播放、地面摩擦力、預輸入緩衝 (Input Buffer) 與連段派生邏輯。

# 🌟 普攻 (J 鍵) 派生路線設定 (在 Inspector 填入下一個狀態節點)
@export var next_combo_state: VsPlayerState 
@export var next_combo_df: VsPlayerState    
@export var next_combo_db: VsPlayerState    

# 🌟 技能 (K 鍵) 派生路線設定
@export var next_skill_neutral: VsPlayerState 
@export var next_skill_df: VsPlayerState      
@export var next_skill_db: VsPlayerState      

@export_group("⚔️ 招式基礎設定")
@export var attack_anim: String = "attack_1" 
## 🎯 讓每招自己選要用哪個判定框！
@export var attack_hitbox_path: NodePath = "Hitboxes/AttackHitbox" 
## 🎯 這招的基礎傷害！
@export var base_damage: float = 10.0    
## 基礎流血值 (預設 0 就是不流血)
@export var base_bleed: float = 0.0            
## 基礎破防 (預設 false 就是不破防                          
@export var base_guard_break: bool = false
## 🌟 基礎破霸體
@export var base_armor_break: bool = false     
## 🌟 命中縮減CD秒數     
@export var base_hit_cd_reduce: float = 0.0    

# --- 預輸入緩衝記憶體 ---
var is_combo_requested := false 
var is_skill_requested := false 
var requested_skill_motion := "" 
var requested_combo_motion := "" 

func enter() -> void:
	# 進入狀態時，清空上一次的搓招記憶
	is_combo_requested = false 
	is_skill_requested = false 
	requested_skill_motion = "" 
	requested_combo_motion = "" 
	
	player.animation.play(attack_anim)
	
	# 攻擊起手時清除 X 軸動能，並關閉連段窗口 (由動畫決定何時開啟)
	player.velocity.x = 0.0 
	player.can_combo = false 
	
	# ==========================================
	# 🌟 萬用 Buff 擴充槽：讓公用腳本支援所有角色的被動！
	# ==========================================
	var my_hitbox = get_node_or_null(attack_hitbox_path) as VsHitbox
	if my_hitbox != null:
		# 1. 每次出招，先把傷害重置回這招的基礎值 (防止上一招的流血或傷害殘留)
		my_hitbox.damage = base_damage
		my_hitbox.bleed_damage = 0.0
		my_hitbox.guard_break = false
		my_hitbox.armor_break = base_armor_break     
		my_hitbox.hit_cd_reduce = base_hit_cd_reduce  
		
		# 2. 鴨子型別：問老爸會不會自己上 Buff？(完美相容機鎧的納刀！)
		if player.has_method("buff_hitbox"):
			player.buff_hitbox(my_hitbox, base_damage)
		

func exit() -> void:
	# 離開攻擊狀態時 (包含被打斷)，強制關閉身上所有判定框，防止幽靈傷害！
	player.deactivate_all_hitboxes()

# ==========================================
# 🎯 核心神技：取得戰鬥朝向 (永遠以對手為「前」)
# ==========================================
func get_combat_facing_input() -> String:
	var holding_down = Input.is_action_pressed(player.down_key)
	var holding_left = Input.is_action_pressed(player.left_key)
	var holding_right = Input.is_action_pressed(player.right_key)
	
	# 取得玩家目前面向，若有對手則強制以對手位置做為相對的「前」
	var combat_facing = player.get_node("Graphics").scale.x
	if player.opponent != null:
		var dir_to_opponent = sign(player.opponent.global_position.x - player.global_position.x)
		if dir_to_opponent != 0:
			combat_facing = dir_to_opponent

	var holding_forward = (combat_facing == 1.0 and holding_right) or (combat_facing == -1.0 and holding_left)
	var holding_backward = (combat_facing == 1.0 and holding_left) or (combat_facing == -1.0 and holding_right)
	
	if holding_down and holding_forward: return "df"  # 下前 (Down-Forward)
	elif holding_down and holding_backward: return "db" # 下後 (Down-Backward)
	return "neutral" # 原地

# ==========================================
# 🏃 物理與派生運算
# ==========================================
func process_physics(delta: float) -> VsState:
	# 🌟 預輸入緩衝 (Input Buffer)：全域 Input 輪詢，解決 P2 吃鍵問題
	# 只要在這個狀態下按了鍵，就先「拍照存證」，等動畫開啟 can_combo 窗口時再結算
	if Input.is_action_just_pressed(player.skill_key):
		is_skill_requested = true 
		requested_skill_motion = get_combat_facing_input()
		
	if Input.is_action_just_pressed(player.attack_key):
		is_combo_requested = true 
		requested_combo_motion = get_combat_facing_input()
	
	# 處理攻擊時的地面煞車摩擦力 (若有 strike_impulse 推力，會在這裡慢慢減速)
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.ground_friction * delta)

	# 檢查是否有高優先級打斷 (如衝刺取消)
	var interrupt_state = super(delta) 
	if interrupt_state != null:
		return interrupt_state 
	
	# ==========================================
	# ⚔️ 連段派生執行 (等待 AnimationPlayer 開啟 can_combo)
	# ==========================================
	if player.can_combo:
		
		# 優先判定技能 (K) 派生
		if is_skill_requested:
			if requested_skill_motion == "df" and next_skill_df != null and next_skill_df.can_cast(): 
				return next_skill_df
			elif requested_skill_motion == "db" and next_skill_db != null and next_skill_db.can_cast(): 
				return next_skill_db
			elif next_skill_neutral != null and next_skill_neutral.can_cast(): 
				return next_skill_neutral
				
		# 判定普攻 (J) 派生
		if is_combo_requested:
			if requested_combo_motion == "df" and next_combo_df != null: return next_combo_df
			elif requested_combo_motion == "db" and next_combo_db != null: return next_combo_db
			elif next_combo_state != null: return next_combo_state 
		
	# 若沒接招且動畫播完，回歸待機
	if not player.animation.is_playing():
		return state_machine.idle_state
			
	return null
