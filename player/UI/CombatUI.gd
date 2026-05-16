extends Control
## 戰鬥 UI 監視器
## 負責偷看玩家與武器的變數，並更新冷卻進度條、圖示與專屬能量槽。

@export var player: Player

# --- 基礎技能槽 ---
@onready var skill_slots = $HBoxContainer
@onready var skill_1_ui = $HBoxContainer/Skill1
@onready var skill_2_ui = $HBoxContainer/Skill2
@onready var skill_3_ui = $HBoxContainer/Skill3
@onready var ult_ui = $HBoxContainer/Ult
@onready var switch_ui = $HBoxContainer/SwitchWeapon

# --- 外圈能量環 ---
@onready var ult_ring_ui = $HBoxContainer/Ult/EnergyRing
@onready var switch_ring_ui = $HBoxContainer/SwitchWeapon/SwitchRing

# --- 🌟 太刀專屬資源面版 ---
@onready var katana_ui = $KatanaResources
@onready var iai_bar = $KatanaResources/IaiBar
@onready var tsubame_bar = $KatanaResources/TsubameBar

# --- 🌟 長槍專屬資源面版 (新增) ---
@onready var spear_ui = $SpearResources
@onready var pozhen_bar = $SpearResources/PozhenBar
@onready var ult_buff_bar = $SpearResources/UltBuffBar # 用來顯示大招剩餘次數
# --- 內部快取變數 ---
var cached_weapon: Node = null 
var _cached_skill_1_enhanced: bool = false 
var ui_tween: Tween # 負責處理漸變演出的計時器

func _ready() -> void:
	# 遊戲開始時，預設先隱藏專屬 UI，等確認手上的武器再顯示
	if katana_ui: katana_ui.modulate.a = 0.0
	if spear_ui: spear_ui.modulate.a = 0.0
func _process(_delta: float) -> void:
	if not is_instance_valid(player): return
	
	# ==========================================
	# 🔄 1. 通用：武器切換冷卻
	# ==========================================
	var switch_max = player.WEAPON_SWITCH_COOLDOWN
	var switch_current = player.weapon_switch_cooldown_timer
	_update_radial_cooldown(switch_ui, switch_current, switch_max)

	# ==========================================
	# ⚔️ 2. 武器專屬：技能與大招冷卻
	# ==========================================
	var current_weapon = player.get("current_weapon")
	if not is_instance_valid(current_weapon): return
	
	# 🌟 發現切換武器：觸發漸變演出與全面刷新圖示
	if current_weapon != cached_weapon:
		_handle_weapon_ui_transition(current_weapon)
		cached_weapon = current_weapon
		_cached_skill_1_enhanced = false # 重置強化狀態

	# 🌟 動態圖標替換邏輯 (偷看太刀的燕返狀態)
	var is_enhanced = current_weapon.get("is_tsubame_ready") == true
	
	if is_enhanced != _cached_skill_1_enhanced:
		_cached_skill_1_enhanced = is_enhanced
		if is_enhanced and current_weapon.get("skill_1_enhanced_icon"):
			_swap_dynamic_icon(skill_1_ui, current_weapon.get("skill_1_enhanced_icon"), true)
		else:
			_swap_dynamic_icon(skill_1_ui, current_weapon.get("skill_1_icon"), false)

	# 更新三個技能的冷卻
	_update_radial_cooldown(skill_1_ui, current_weapon.get("skill_1_timer"), current_weapon.get("skill_1_cd"))
	_update_radial_cooldown(skill_2_ui, current_weapon.get("skill_2_timer"), current_weapon.get("skill_2_cd"))
	_update_radial_cooldown(skill_3_ui, current_weapon.get("skill_3_timer"), current_weapon.get("skill_3_cd"))
	
	# 更新大招的冷卻
	_update_radial_cooldown(ult_ui, current_weapon.get("ult_timer"), current_weapon.get("ult_cd"))
	
	# ==========================================
	# 🔋 3. 外圈：大招能量與切換(合軸)值累積
	# ==========================================
	var current_weapon_id = current_weapon.get("WEAPON_ID") if current_weapon.get("WEAPON_ID") else ""
	
	var current_energy = 0.0
	var current_switch = 0.0
	
	if current_weapon_id != "" and player.weapon_resources.has(current_weapon_id):
		var resource = player.weapon_resources[current_weapon_id]
		current_energy = resource["energy"]
		current_switch = resource["switch"]
		
	if is_instance_valid(ult_ring_ui):
		ult_ring_ui.value = current_energy
		
	if is_instance_valid(switch_ring_ui):
		switch_ring_ui.value = current_switch
		
	# ==========================================
	# 🗡️ 4. 專屬面版更新 (太刀 / 長槍)
	# ==========================================
	if current_weapon_id == "katana":
		_update_katana_values(current_weapon)
	elif current_weapon_id == "spear":
		_update_spear_values(current_weapon)

# ==========================================
# 🎬 視覺過場：武器切換漸變 (Animation)
# ==========================================
func _handle_weapon_ui_transition(new_weapon: Node) -> void:
	if ui_tween and ui_tween.is_valid(): ui_tween.kill()
	ui_tween = create_tween().set_parallel(true)
	
	# 1. 整個技能列的閃爍漸變
	if skill_slots:
		skill_slots.modulate.a = 0.5
		ui_tween.tween_property(skill_slots, "modulate:a", 1.0, 0.3)
	
	# 2. 專屬面版的滑動與淡入淡出
	var w_id = new_weapon.get("WEAPON_ID")
	
	# 先將兩個面版都設為隱藏動畫的目標
	if katana_ui: ui_tween.tween_property(katana_ui, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	if spear_ui: ui_tween.tween_property(spear_ui, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	
	# 針對當前武器顯示對應面版
	if w_id == "katana" and katana_ui:
		katana_ui.show()
		katana_ui.position.y += 5
		ui_tween.tween_property(katana_ui, "position:y", katana_ui.position.y - 5, 0.2)
		ui_tween.tween_property(katana_ui, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
		if spear_ui: ui_tween.chain().tween_callback(spear_ui.hide)
			
	elif w_id == "spear" and spear_ui:
		spear_ui.show()
		spear_ui.position.y += 5
		ui_tween.tween_property(spear_ui, "position:y", spear_ui.position.y - 5, 0.2)
		ui_tween.tween_property(spear_ui, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
		if katana_ui: ui_tween.chain().tween_callback(katana_ui.hide)
		
	else:
		# 拿其他沒有專屬 UI 的武器，全部隱藏
		if katana_ui: ui_tween.chain().tween_callback(katana_ui.hide)
		if spear_ui: ui_tween.chain().tween_callback(spear_ui.hide)

	_refresh_weapon_icons(new_weapon)
	
func _update_spear_values(weapon: Node) -> void:
	var pozhen = weapon.get("current_pozhen")
	var is_ult = weapon.get("is_ult_active")
	var ult_count = weapon.get("ult_attack_count")
	
	# 🌟 1. 處理破陣值 (Max 40)
	if pozhen != null and is_instance_valid(pozhen_bar): 
		pozhen_bar.value = (float(pozhen) / 40.0) * 100.0
		
	# 🌟 2. 處理大招剩餘次數 (Max 16)
	if is_instance_valid(ult_buff_bar):
		if is_ult:
			ult_buff_bar.show() # 開大招時才顯示計數條
			var max_attacks = weapon.get("MAX_ULT_ATTACKS") if weapon.get("MAX_ULT_ATTACKS") else 16
			
			# 計算剩餘次數的百分比 (打越多次，進度條越少)
			var remaining_percent = (float(max_attacks - ult_count) / float(max_attacks)) * 100.0
			ult_buff_bar.value = remaining_percent
		else:
			ult_buff_bar.hide() # 沒開大招時自動隱藏
			
# ==========================================
# 📊 數值更新區
# ==========================================
func _update_katana_values(weapon: Node) -> void:
	var iai = weapon.get("current_iai")
	var tsubame = weapon.get("current_tsubame")
	
	# 假設最大值都是 60 點，轉換為 100% 進度條
	if iai != null and is_instance_valid(iai_bar): 
		iai_bar.value = (float(iai) / 60.0) * 100.0
	if tsubame != null and is_instance_valid(tsubame_bar): 
		tsubame_bar.value = (float(tsubame) / 60.0) * 100.0

# ==========================================
# 🛠️ 輔助功能區 (UI 控制邏輯)
# ==========================================
func _refresh_weapon_icons(weapon: Node) -> void:
	_apply_icon(skill_1_ui, weapon.get("skill_1_icon"))
	_apply_icon(skill_2_ui, weapon.get("skill_2_icon"))
	_apply_icon(skill_3_ui, weapon.get("skill_3_icon"))
	_apply_icon(ult_ui, weapon.get("ult_icon"))

func _apply_icon(ui_element: TextureProgressBar, icon_texture: Texture2D) -> void:
	if not is_instance_valid(ui_element):
		return
		
	if icon_texture != null:
		ui_element.texture_under = icon_texture
		ui_element.texture_progress = icon_texture
		ui_element.tint_progress = Color(0.15, 0.15, 0.15, 0.8) 
		ui_element.show()
	else:
		ui_element.hide()
		
func _update_radial_cooldown(ui_element: TextureProgressBar, current_timer: Variant, max_cd: Variant) -> void:
	if not is_instance_valid(ui_element):
		return
		
	if current_timer == null or max_cd == null or max_cd <= 0.0:
		ui_element.value = 0
		return
		
	var percent = (float(current_timer) / float(max_cd)) * 100.0
	ui_element.value = percent
	
func _swap_dynamic_icon(ui_element: TextureProgressBar, icon_texture: Texture2D, is_highlighted: bool) -> void:
	if not is_instance_valid(ui_element) or icon_texture == null: 
		return
		
	ui_element.texture_under = icon_texture
	ui_element.texture_progress = icon_texture
	
