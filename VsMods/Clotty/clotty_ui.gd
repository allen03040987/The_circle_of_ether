extends Control

var player: VsPlayer

@onready var skill_container = $SkillContainer
@onready var skill_a_cd = $SkillContainer/SkillA_CD
@onready var label_a_charge = $SkillContainer/SkillA_CD/ChargeLabel
@onready var skill_b_cd = $SkillContainer/SkillB_CD
@onready var label_b_charge = $SkillContainer/SkillB_CD/ChargeLabel
@onready var ult1_cd = $SkillContainer/Ult1_CD
@onready var ult2_cd = $SkillContainer/Ult2_CD

# ==========================================
# 🌟 高級能量條節點綁定 (疊圖版)
# ==========================================
@onready var energy_container = $EnergyContainer       # 能量條總群組 (用來調整 P2 位置)
@onready var energy_states = $EnergyContainer/States   # 裝著 8 張狀態圖的容器
@onready var max_effect = $EnergyContainer/MaxEffect   # 滿層發光特效

func _ready() -> void:
	await get_tree().process_frame
	if player != null and player.player_id == 2:
		# 1. 技能圖標容器鏡像反轉
		skill_container.alignment = BoxContainer.ALIGNMENT_END
		skill_container.layout_direction = Control.LAYOUT_DIRECTION_RTL
		
		# 🌟 2. 拯救 P2 凸出去的能量條！
		# 強制把能量條往左邊推移「它自己的寬度」，達成完美靠右對齊！
		if energy_container != null:
			energy_container.position.x -= energy_container.size.x

func _process(_delta: float) -> void:
	if player == null: return
	
	skill_a_cd.value = player.get_cooldown_percent("UI_Skill_A")
	skill_b_cd.value = player.get_cooldown_percent("UI_Skill_B")
	ult1_cd.value = player.get_cooldown_percent("UI_Ult_1")
	ult2_cd.value = player.get_cooldown_percent("UI_Ult_2")
	
	_update_charge_label(label_a_charge, "UI_Skill_A")
	_update_charge_label(label_b_charge, "UI_Skill_B")
	
	# ==========================================
	# 🌟 更新能量條 (圖層替換版)
	# ==========================================
	if "current_energy" in player and "max_energy" in player:
		_update_custom_energy_bar(player.current_energy, player.max_energy)


func _update_charge_label(label: Label, slot_name: String) -> void:
	if label == null: return
	if not player.skill_cooldowns.has(slot_name):
		label.visible = false
		return
		
	var current_charges = player.skill_cooldowns[slot_name]["charges"]
	var max_charges = player.skill_cooldowns[slot_name]["max_charges"]
	
	if max_charges <= 1:
		label.visible = false
		return
		
	label.visible = true
	label.text = str(current_charges)
	if current_charges <= 0:
		label.add_theme_color_override("font_color", Color.RED)
	else:
		label.add_theme_color_override("font_color", Color.WHITE)


# ==========================================
# 🛠️ 狀態圖替換系統 (16轉8 視覺壓縮版)
# ==========================================
func _update_custom_energy_bar(current: int, maximum: int) -> void:
	if energy_states == null: return
	
	var state_images = energy_states.get_children()
	
	for img in state_images:
		img.visible = false
		
	# 🌟 魔法數學：每 2 點能量切換一張圖！
	# (例如：1,2->圖1 / 3,4->圖2 ... 15,16->圖8)
	if current > 0:
		var img_index = (current - 1) / 2
		# 防呆：確保算出來的索引沒有超出你放的圖片數量
		if img_index < state_images.size():
			state_images[img_index].visible = true
		
	# 滿層大招發光特效
	if max_effect != null:
		if current >= maximum:
			max_effect.visible = true
		else:
			max_effect.visible = false
