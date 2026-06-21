extends Control
## 戰鬥 UI 監視器
## 負責偷看玩家與武器的變數，並更新冷卻進度條、圖示與專屬能量槽。

@export var player: Player

# --- 基礎技能槽 ---
@onready var skill_slots = $HBoxContainer
@onready var skill_1_ui = $HBoxContainer/Skill1
@onready var ult_ui = $HBoxContainer/Ult
@onready var switch_ui = $HBoxContainer/SwitchWeapon

# --- 外圈能量環 ---
@onready var ult_ring_ui = $HBoxContainer/Ult/EnergyRing


# --- 🌟 太刀專屬資源面版 ---
@onready var katana_ui = $KatanaResources
@onready var iai_bar = $KatanaResources/IaiBar
@onready var tsubame_bar = $KatanaResources/TsubameBar

# --- 🌟 長槍專屬資源面版 ---
@onready var spear_ui = $SpearResources
@onready var pozhen_bar = $SpearResources/PozhenBar
@onready var ult_buff_bar = $SpearResources/UltBuffBar 


# --- 🌟 符咒專屬資源面版 ---

@onready var talisman_ui = $TalismanResources
@onready var talisman_charge_bar = $TalismanResources/ChargeBar # 顯示 0/50 靈符值
@onready var talisman_enhanced_bar = $TalismanResources/EnhancedBar # 顯示強化型態狀態



# --- 內部快取變數 ---
var cached_weapon: Node = null 
var _cached_skill_1_enhanced: bool = false 
var _cached_s2_step: int = 0 # 🌟 記憶技能二打到第幾段
var _cached_s3_step: int = 0 # 🌟 記憶技能三打到第幾段
var ui_tween: Tween 

func _ready() -> void:
	if katana_ui: katana_ui.modulate.a = 0.0
	if spear_ui: spear_ui.modulate.a = 0.0
	if talisman_ui: talisman_ui.modulate.a = 0.0

func _process(_delta: float) -> void:
	if not is_instance_valid(player): return
	
	# ==========================================
	# 🔄 1. 通用：武器切換冷卻
	# ==========================================
	var switch_max = player.WEAPON_SWITCH_COOLDOWN
	var switch_current = player.weapon_switch_cooldown_timer
	_update_radial_cooldown(switch_ui, switch_current, switch_max)

	# ==========================================
	# ⚔️ 2. 武器專屬：技能與大招冷卻與動態圖標
	# ==========================================
	var current_weapon = player.get("current_weapon")
	if not is_instance_valid(current_weapon): return
	var current_weapon_id = current_weapon.get("WEAPON_ID") if current_weapon.get("WEAPON_ID") else ""
	
	# 🌟 發現切換武器：觸發漸變演出與全面刷新圖示
	if current_weapon != cached_weapon:
		_handle_weapon_ui_transition(current_weapon)
		cached_weapon = current_weapon
		

	# ==========================================
	# 🌟 動態圖標替換邏輯 (極致解耦版)
	# ==========================================
	# UI 直接向武器索取目前的圖標，如果跟畫面上不一樣就換掉！
	if current_weapon.has_method("get_dynamic_skill_icon"):
		
		var icon_1 = current_weapon.get_dynamic_skill_icon(1)
		if icon_1 and skill_1_ui.texture_under != icon_1:
			_swap_dynamic_icon(skill_1_ui, icon_1)

	# --- 🌟 冷卻條邏輯 (含連段寬限期提示) ---
	_update_radial_cooldown(skill_1_ui, current_weapon.get("skill_1_timer"), current_weapon.get("skill_1_cd"))
	_update_radial_cooldown(ult_ui, current_weapon.get("ult_timer"), current_weapon.get("ult_cd"))
	
	
	
	# ==========================================
	# 🔋 3. 外圈：大招能量累積
	# ==========================================
	var current_energy = 0.0
	
	if current_weapon_id != "" and player.weapon_resources.has(current_weapon_id):
		var resource = player.weapon_resources[current_weapon_id]
		# 🌟 安全讀取：現在武器帳戶裡只有純粹的大招能量了
		current_energy = resource["energy"]
		
	if is_instance_valid(ult_ring_ui): ult_ring_ui.value = current_energy
		
	# ==========================================
	# 🗡️ 4. 專屬面版更新 (太刀 / 長槍)
	# ==========================================
	if current_weapon_id == "katana": _update_katana_values(current_weapon)
	elif current_weapon_id == "spear": _update_spear_values(current_weapon)
	elif current_weapon_id == "talisman": _update_talisman_values(current_weapon)
# ==========================================
# 🎬 視覺過場：武器切換漸變 (Animation)
# ==========================================
func _handle_weapon_ui_transition(new_weapon: Node) -> void:
	if ui_tween and ui_tween.is_valid(): ui_tween.kill()
	ui_tween = create_tween().set_parallel(true)
	
	if skill_slots:
		skill_slots.modulate.a = 0.5
		ui_tween.tween_property(skill_slots, "modulate:a", 1.0, 0.3)
	
	var w_id = new_weapon.get("WEAPON_ID")
	
	# 先把所有面板淡出
	if katana_ui: ui_tween.tween_property(katana_ui, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	if spear_ui: ui_tween.tween_property(spear_ui, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	if talisman_ui: ui_tween.tween_property(talisman_ui, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE) # 🌟 符咒也加入淡出陣列
	
	if w_id == "katana" and katana_ui:
		katana_ui.show()
		katana_ui.position.y += 5
		ui_tween.tween_property(katana_ui, "position:y", katana_ui.position.y - 5, 0.2)
		ui_tween.tween_property(katana_ui, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
		
		# 隱藏其他人
		if spear_ui: ui_tween.chain().tween_callback(spear_ui.hide)
		if talisman_ui: ui_tween.chain().tween_callback(talisman_ui.hide)
		
	elif w_id == "spear" and spear_ui:
		spear_ui.show()
		spear_ui.position.y += 5
		ui_tween.tween_property(spear_ui, "position:y", spear_ui.position.y - 5, 0.2)
		ui_tween.tween_property(spear_ui, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
		
		if katana_ui: ui_tween.chain().tween_callback(katana_ui.hide)
		if talisman_ui: ui_tween.chain().tween_callback(talisman_ui.hide)
		
	elif w_id == "talisman" and talisman_ui:
		talisman_ui.show()
		talisman_ui.position.y += 5
		ui_tween.tween_property(talisman_ui, "position:y", talisman_ui.position.y - 5, 0.2)
		ui_tween.tween_property(talisman_ui, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
		
		if katana_ui: ui_tween.chain().tween_callback(katana_ui.hide)
		if spear_ui: ui_tween.chain().tween_callback(spear_ui.hide)
		
	else:
		if katana_ui: ui_tween.chain().tween_callback(katana_ui.hide)
		if spear_ui: ui_tween.chain().tween_callback(spear_ui.hide)
		if talisman_ui: ui_tween.chain().tween_callback(talisman_ui.hide)

	_refresh_weapon_icons(new_weapon)
	
# ==========================================
# 📊 數值更新區
# ==========================================
func _update_spear_values(weapon: Node) -> void:
	var pozhen = weapon.get("current_pozhen")
	var is_ult = weapon.get("is_ult_active")
	var ult_count = weapon.get("ult_attack_count")
	
	if pozhen != null and is_instance_valid(pozhen_bar): 
		pozhen_bar.value = (float(pozhen) / 40.0) * 100.0
	if is_instance_valid(ult_buff_bar):
		if is_ult:
			ult_buff_bar.show()
			var max_attacks = weapon.get("MAX_ULT_ATTACKS") if weapon.get("MAX_ULT_ATTACKS") else 16
			ult_buff_bar.value = (float(max_attacks - ult_count) / float(max_attacks)) * 100.0
		else:
			ult_buff_bar.hide() 
			
func _update_katana_values(weapon: Node) -> void:
	var iai = weapon.get("current_iai")
	var tsubame = weapon.get("current_tsubame")
	if iai != null and is_instance_valid(iai_bar): iai_bar.value = (float(iai) / 60.0) * 100.0
	if tsubame != null and is_instance_valid(tsubame_bar): tsubame_bar.value = (float(tsubame) / 60.0) * 100.0

func _update_talisman_values(weapon: Node) -> void:
	var charge = weapon.get("current_talisman_charge")
	var is_enhanced = weapon.get("is_enhanced_mode")
	
	# 更新 0~50 點的靈符值
	if charge != null and is_instance_valid(talisman_charge_bar): 
		talisman_charge_bar.value = (float(charge) / 50.0) * 100.0
		
	# 更新強化狀態 (滿管代表強化中，空管代表普通型態)
	if is_enhanced != null and is_instance_valid(talisman_enhanced_bar):
		if is_enhanced:
			talisman_enhanced_bar.show()
			talisman_enhanced_bar.value = 100.0 # 滿狀態
		else:
			talisman_enhanced_bar.hide()
# ==========================================
# 🛠️ 輔助功能區 (UI 控制邏輯)
# ==========================================
func _refresh_weapon_icons(weapon: Node) -> void:
	_apply_icon(skill_1_ui, weapon.get("skill_1_icon"))
	_apply_icon(ult_ui, weapon.get("ult_icon"))

func _apply_icon(ui_element: TextureProgressBar, icon_texture: Texture2D) -> void:
	if not is_instance_valid(ui_element): return
	if icon_texture != null:
		ui_element.texture_under = icon_texture
		ui_element.texture_progress = icon_texture
		ui_element.tint_progress = Color(0.15, 0.15, 0.15, 0.8) 
		ui_element.show()
	else:
		ui_element.hide()
		
func _update_radial_cooldown(ui_element: TextureProgressBar, current_timer: Variant, max_cd: Variant, is_combo_grace: bool = false) -> void:
	if not is_instance_valid(ui_element): return
	
	if current_timer == null or max_cd == null or max_cd <= 0.0 or current_timer <= 0.0:
		ui_element.value = 0
		return
		
	var percent = (float(current_timer) / float(max_cd)) * 100.0
	ui_element.value = percent
	
	# 🌟 新增視覺回饋：如果是連段寬限期，將半透明黑色遮罩改為半透明橘色！
	if is_combo_grace:
		ui_element.tint_progress = Color(0.8, 0.4, 0.1, 0.6) # 橘紅色提示快點按
	else:
		ui_element.tint_progress = Color(0.15, 0.15, 0.15, 0.8) # 正常冷卻灰黑色
	
func _swap_dynamic_icon(ui_element: TextureProgressBar, icon_texture: Texture2D) -> void:
	if not is_instance_valid(ui_element) or icon_texture == null: return
	ui_element.texture_under = icon_texture
	ui_element.texture_progress = icon_texture
