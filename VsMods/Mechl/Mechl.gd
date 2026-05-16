class_name PlayerMechl
extends VsPlayer

@export_group("⚔️ 機鎧專屬機制")
@export var max_sheathe_stacks: int = 5    # 最大納刀層數
var current_sheathe_stacks: int = 0        # 當前納刀層數
var keep_sheathe_stand: bool = false       # 是否蹲滿20秒，獲得帶刀起身特權
var is_sheathe_active_in_combo: bool = false

# 防禦疊層專用計時器
var post_guard_timer: float = 0.0
var is_waiting_post_guard: bool = false

# 🌟 自動追蹤雷達：用來記住上一幀是什麼狀態
var _previous_state: VsState = null

func _ready() -> void:
	super._ready()
	var sprite = get_node_or_null("Graphics/Sprite2D")
	# 如果有需要翻轉圖片，可以在這裡加 sprite.flip_h = true

func _process(delta: float) -> void:
	super._process(delta)
	
	# ==========================================
	# 📡 狀態雷達：免改狀態機腳本的神級自動結算！
	# ==========================================
	# 🌟 直接去肚子裡找狀態機節點 (請確認你的狀態機節點名稱是不是 VsStateMachine)
	var fsm = get_node_or_null("VsStateMachine") 
	
	if fsm != null and "current_state" in fsm:
		if fsm.current_state != _previous_state:
			_on_state_changed(_previous_state, fsm.current_state)
			_previous_state = fsm.current_state

	# ==========================================
	# 🛡️ 防禦成功脫離後的 0.3 秒判定
	# ==========================================
	if is_waiting_post_guard:
		post_guard_timer -= delta
		if post_guard_timer <= 0.0:
			is_waiting_post_guard = false
			_add_sheathe_stack(false) # false 代表這是防禦給的，最多只能疊到 4 層

# 🌟 狀態雷達觸發的事件
func _on_state_changed(old_state: VsState, new_state: VsState) -> void:
	if new_state == null: return
	
	# 把狀態的名字轉成小寫來判斷，這樣最安全，不用管節點確實叫什麼
	var state_name = new_state.name.to_lower()
	
	# 如果新狀態是 待機(idle)、移動(run) 或 蹲下(crouch)，代表連段徹底結束了！
	if "idle" in state_name or "run" in state_name or "crouch" in state_name:
		check_combo_end()

# 供 MechlGuardState 離開時呼叫
func start_post_guard_stack() -> void:
	is_waiting_post_guard = true
	post_guard_timer = 0.3

# ==========================================
# ⚔️ 納刀核心邏輯
# ==========================================
func _add_sheathe_stack(from_crouch: bool = true) -> void:
	var limit = max_sheathe_stacks if from_crouch else 4
	
	if current_sheathe_stacks < limit:
		current_sheathe_stacks += 1
		print("⚔️ 納刀疊層！目前層數：", current_sheathe_stacks)

func consume_sheathe_stacks() -> void:
	current_sheathe_stacks = 0
	keep_sheathe_stand = false
	print("💥 納刀解放！層數歸零。")

# ==========================================
# 🩸 動態判定框強化 (Dynamic Hitbox Buffing)
# ==========================================
func buff_hitbox(hitbox: VsHitbox, base_damage: float) -> void:
	if current_sheathe_stacks > 0:
		is_sheathe_active_in_combo = true # 🌟 標記：我這套連段拔刀了！
	
	if current_sheathe_stacks == 0:
		hitbox.damage = base_damage
		return
		
	var base_buff_rate = 0.2 
	var atk_multiplier = 1.0

	match current_sheathe_stacks:
		1:
			atk_multiplier = 1.0 + base_buff_rate
		2:
			atk_multiplier = 1.0 + (base_buff_rate * 2.0)
			hitbox.bleed_damage = 10.0 
		3:
			atk_multiplier = 1.0 + (base_buff_rate * 3.0)
			hitbox.bleed_damage = 15.0
			hitbox.guard_break = true  
		4:
			atk_multiplier = 1.0 + (base_buff_rate * 4.0)
			hitbox.bleed_damage = 20.0
			hitbox.guard_break = true
		5:
			atk_multiplier = 1.0 + (base_buff_rate * 6.0) 
			hitbox.bleed_damage = 30.0
			hitbox.guard_break = true
			
	hitbox.damage = base_damage * atk_multiplier
	print("🔥 納刀強化完畢！當前傷害：", hitbox.damage, " | 破防：", hitbox.guard_break)

# ==========================================
# 🛑 連段結束結算
# ==========================================
func check_combo_end() -> void:
	if is_sheathe_active_in_combo:
		consume_sheathe_stacks() # 真正扣除層數與特權
		is_sheathe_active_in_combo = false
		print("🛑 乾淨俐落！連段結束回到待機，正式扣除納刀層數！")
