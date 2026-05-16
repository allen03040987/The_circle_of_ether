class_name PlayerClotty
extends VsPlayer 

@export_group("⚡ 刻羅帝能量設定")
@export var max_energy: int = 16 
var current_energy: int = 0
var passive_energy_counter: int = 0
var is_awakened: bool = false
var awaken_timer: float = 0.0
var last_state_name: String = ""

# ==========================================
# 🔄 生命週期 (初始化技能層數)
# ==========================================
func _ready() -> void:
	super._ready() 
	
	# 🌟 改用萬用插槽名稱！
	init_skill_slot("UI_Skill_A", 5.0, 2)  # 空中普攻 (2層)
	init_skill_slot("UI_Skill_B", 5.0, 1)  # 斜衝砍 (1層)
	init_skill_slot("UI_Ult_1", 30.0, 1)   # 地面大招
	init_skill_slot("UI_Ult_2", 30.0, 1)   # 空中大招
	
# ==========================================
# 🏃‍♂️ 衝刺集氣與覺醒迴圈 (純單機版)
# ==========================================
func _process(delta: float) -> void:
	super._process(delta) 
	
	# 1. 衝刺集氣
	var current_state = vs_state_machine.current_state
	if current_state != null and current_state.name != last_state_name:
		if current_state.name in ["small_dash_state", "BigDashState"]:
			if current_energy < max_energy:
				current_energy += 1
			passive_energy_counter += 1
			print("⚡ 刻羅帝充能：主能量 ", current_energy, "/", max_energy, " | 黑球之力計數：", passive_energy_counter)
			
		last_state_name = current_state.name
		
	# 2. 覺醒倒數與零冷卻視覺
	if is_awakened:
		awaken_timer -= delta
		if awaken_timer <= 0.0:
			end_awakening()

# ==========================================
# 👑 零冷卻外掛 (欺騙老爸與 UI)
# ==========================================
func is_skill_ready(slot_name: String) -> bool:
	if is_awakened: return true 
	return super.is_skill_ready(slot_name)

func get_cooldown_percent(slot_name: String) -> float:
	if is_awakened: return 0.0 
	return super.get_cooldown_percent(slot_name)

# 🌟 新增：覺醒時欺騙 UI，顯示無限大層數 (例如 9)
func get_skill_charges(slot_name: String) -> int:
	if is_awakened: return 9 
	return super.get_skill_charges(slot_name)

# ==========================================
# 🔮 被動攔截器 (改為 8 次)
# ==========================================
func _physics_process(delta: float) -> void:
	super._physics_process(delta) 
	if passive_energy_counter >= 8:
		if vs_state_machine.current_state != null and "Idle" in vs_state_machine.current_state.name:
			var passive_state = vs_state_machine.get_node_or_null("Skill_passive")
			if passive_state:
				passive_energy_counter -= 8
				vs_state_machine.current_state.exit()
				vs_state_machine.current_state = passive_state
				passive_state.enter()

# ==========================================
# ⏳ THE WORLD！時空覺醒大招
# ==========================================
func activate_the_world() -> void:
	is_awakened = true
	# 🌟 移除這裡的 current_energy = 0，保留能量！
	awaken_timer = 12.0
	print("⏳ THE WORLD！刻羅帝時空覺醒！")
	is_global_guard_break = true 
	
	if opponent != null:
		opponent.animation.speed_scale = 0.4
		opponent.custom_time_scale = 0.4 
	
func end_awakening() -> void:
	is_awakened = false
	is_global_guard_break = false
	
	# 🌟 移到這裡！時緩結束的瞬間，能量才瞬間抽乾歸零！
	current_energy = 0 
	print("⏳ 時間開始流動。能量歸零！")
	
	if opponent != null:
		opponent.animation.speed_scale = 1.0
		opponent.custom_time_scale = 1.0
