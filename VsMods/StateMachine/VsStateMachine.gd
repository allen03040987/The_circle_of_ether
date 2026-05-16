class_name VsStateMachine 
extends Node2D

## 戰鬥專用節點狀態機 (Node-based State Machine)
## 負責集中管理角色的所有狀態節點，並控制狀態的進入、執行與退出。
signal state_changed(old_state, new_state)

var current_state: VsState # 目前正在執行的狀態
@export var starting_state: VsState # 角色出生時的預設狀態 (通常是 Idle)

# ==========================================
# 🌟 狀態註冊表 (全域集中管理，Inspector 填洞區)
# ==========================================
@export_group("基礎狀態")
@export var idle_state: VsState   
@export var run_state: VsState    
@export var jump_state: VsState   
@export var fall_state: VsState   
@export var attack_state: VsState 
@export var hurt_state: VsState   
@export var down_state: VsState   
@export var getup_state: VsState 
@export var big_dash_state: VsState
@export var small_dash_state: VsState 
@export var crouch_state: VsState
@export var guard_state: VsState

@export_group("⚔️ 專屬技能模塊")
@export var skill_neutral: VsState      
@export var skill_k1: VsState    
@export var skill_k2: VsState
@export var skill_k3: VsState
@export var attack_bd: VsState    

@export_group("✈️ 空戰模塊")
@export var air_attack: VsState 
@export var air_skill: VsState  

@export_group("🔥 終極與特殊技能")
@export var ultimate_state: VsState 
@export var ultimate_state_2: VsState
@export var special_state: VsState
@export var custom_state: VsState           
   
# ========== 初始化狀態 ==========
func init() -> void: 
	if starting_state:
		change_state(starting_state)
		
# ========== 狀態機生命週期 (轉交給當前狀態執行) ==========
func process_frame(delta: float) -> void:  
	if current_state: 
		var new_state: VsState = current_state.process_frame(delta) 
		if new_state: change_state(new_state) 
	
func process_input(event: InputEvent) -> void:
	if current_state:
		var new_state: VsState = current_state.process_input(event) 
		if new_state: change_state(new_state)
	
func process_physics(delta: float) -> void:
	if current_state:
		var new_state: VsState = current_state.process_physics(delta) 
		if new_state: change_state(new_state)
		
# ========== 核心切換邏輯 ==========
func change_state(new_state: VsState) -> void:
	if current_state != null:
		current_state.exit()
		
	var old_state = current_state # 記住上一個狀態
	current_state = new_state
	current_state.enter()
	
	# 🌟 狀態切換時，廣播給全天下知道！
	emit_signal("state_changed", old_state, new_state)
