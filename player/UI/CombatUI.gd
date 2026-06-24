extends Control
## 戰鬥 UI 監視器 (重構版)

@export var player: Player

# --- 通用技能槽群組 ---
@onready var skill_slots = $HBoxContainer
@onready var ult_ui = $HBoxContainer/Ult
@onready var switch_ui = $HBoxContainer/SwitchWeapon
@onready var ult_ring_ui = $HBoxContainer/Ult/EnergyRing

# 🌟 新增：使用陣列統一管理 3 個獨立的武藝卡帶 UI 節點
@onready var art_uis: Array[TextureProgressBar] = [
	$HBoxContainer/Art1,
	$HBoxContainer/Art2,
	$HBoxContainer/Art3
]

# --- 專屬資源面板 ---
@onready var katana_ui = $KatanaResources
@onready var dodge_bar = $KatanaResources/DodgeBar # 🌟 替換為專屬的閃避資源條

@onready var spear_ui = $SpearResources
@onready var pozhen_bar = $SpearResources/PozhenBar
@onready var ult_buff_bar = $SpearResources/UltBuffBar 

@onready var talisman_ui = $TalismanResources
@onready var talisman_charge_bar = $TalismanResources/ChargeBar 
@onready var talisman_enhanced_bar = $TalismanResources/EnhancedBar 

# --- 內部快取變數 ---
var cached_weapon: Node = null 
var ui_tween: Tween 

func _ready() -> void:
	if katana_ui: katana_ui.modulate.a = 0.0
	if spear_ui: spear_ui.modulate.a = 0.0
	if talisman_ui: talisman_ui.modulate.a = 0.0
	
	# 🌟 核心對接：監聽大腦的組合鍵訊號，啟動技能圖標高亮特效
	if is_instance_valid(player):
		if not player.martial_mode_changed.is_connected(_on_player_martial_mode_changed):
			player.martial_mode_changed.connect(_on_player_martial_mode_changed)

func _process(_delta: float) -> void:
	if not is_instance_valid(player): return
	
	# 1. 武器切換冷卻更新
	_update_radial_cooldown(switch_ui, player.weapon_switch_cooldown_timer, player.WEAPON_SWITCH_COOLDOWN)

	# 2. 取得當前武器本體與身分代號
	var current_weapon = player.get("current_weapon")
	if not is_instance_valid(current_weapon): return
	var current_weapon_id = current_weapon.get("WEAPON_ID") if current_weapon.get("WEAPON_ID") else ""
	
	# 偵測到武器切換，觸發 UI 過渡動畫
	if current_weapon != cached_weapon:
		_handle_weapon_ui_transition(current_weapon)
		cached_weapon = current_weapon

	# 🌟 3. 武藝卡帶神經迴圈更新
	if current_weapon.has_method("get_dynamic_skill_icon"):
		for i in range(3):
			var slot_id = i + 1
			var art_ui = art_uis[i]
			
			# 🛡️ 核心防呆：如果編輯器裡沒有放這個節點，就直接跳過，絕對不准崩潰！
			if not is_instance_valid(art_ui): continue
			
			var icon = current_weapon.get_dynamic_skill_icon(slot_id)
			
			if icon:
				if art_ui.texture_under != icon:
					_swap_dynamic_icon(art_ui, icon)
				art_ui.show()
				_update_radial_cooldown(art_ui, 0.0, 1.0)
			else:
				art_ui.hide()

	# 4. 大招與通用能量環更新
	_update_radial_cooldown(ult_ui, current_weapon.get("ult_timer"), current_weapon.get("ult_cd"))
	
	var current_energy = 0.0
	if current_weapon_id != "" and player.weapon_resources.has(current_weapon_id):
		current_energy = player.weapon_resources[current_weapon_id].get("energy", 0.0)
		
	if is_instance_valid(ult_ring_ui): 
		ult_ring_ui.value = current_energy
		
	# 5. 各武器專屬量表更新
	match current_weapon_id:
		"katana": _update_katana_values(current_weapon)
		"spear": _update_spear_values(current_weapon)
		"talisman": _update_talisman_values(current_weapon)

# ==========================================
# 📡 訊號接收：組合鍵高亮呼吸燈
# ==========================================
func _on_player_martial_mode_changed(is_active: bool) -> void:
	# 當玩家按下修改鍵(Alt/Shift)時，讓 3 個武藝圖標整體放大並變色提示
	for art_ui in art_uis:
		if is_instance_valid(art_ui) and art_ui.visible:
			var tween = create_tween().set_parallel(true)
			if is_active:
				tween.tween_property(art_ui, "modulate", Color(1.5, 1.3, 0.8, 1.0), 0.1) # 閃爍金白光
				tween.tween_property(art_ui, "scale", Vector2(1.05, 1.05), 0.1)          # 微微放大
			else:
				tween.tween_property(art_ui, "modulate", Color.WHITE, 0.15)
				tween.tween_property(art_ui, "scale", Vector2(1.0, 1.0), 0.15)

# ==========================================
# 🎬 視覺過場：武器切換漸變
# ==========================================
func _handle_weapon_ui_transition(new_weapon: Node) -> void:
	if ui_tween and ui_tween.is_valid(): ui_tween.kill()
	ui_tween = create_tween().set_parallel(true)
	
	if skill_slots:
		skill_slots.modulate.a = 0.5
		ui_tween.tween_property(skill_slots, "modulate:a", 1.0, 0.3)
	
	var w_id = new_weapon.get("WEAPON_ID")
	
	if katana_ui: ui_tween.tween_property(katana_ui, "modulate:a", 0.0, 0.2)
	if spear_ui: ui_tween.tween_property(spear_ui, "modulate:a", 0.0, 0.2)
	if talisman_ui: ui_tween.tween_property(talisman_ui, "modulate:a", 0.0, 0.2)
	
	var target_panel: Control = null
	match w_id:
		"katana": target_panel = katana_ui
		"spear": target_panel = spear_ui
		"talisman": target_panel = talisman_ui
		
	if target_panel:
		target_panel.show()
		target_panel.position.y += 5
		ui_tween.tween_property(target_panel, "position:y", target_panel.position.y - 5, 0.2)
		ui_tween.tween_property(target_panel, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
		
		# 動態回呼清理隱藏其他面板
		var panels = [katana_ui, spear_ui, talisman_ui]
		for p in panels:
			if p and p != target_panel: ui_tween.chain().tween_callback(p.hide)
	else:
		if katana_ui: ui_tween.chain().tween_callback(katana_ui.hide)
		if spear_ui: ui_tween.chain().tween_callback(spear_ui.hide)
		if talisman_ui: ui_tween.chain().tween_callback(talisman_ui.hide)

	_refresh_weapon_icons(new_weapon)

# ==========================================
# 📊 專屬數值刷新
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
	# 抓取我們剛剛在太刀本體寫的閃避次數變數
	var current_dodges = weapon.get("current_iai")
	var max_dodges = weapon.get("MAX_IAI")
	
	# 🛡️ 防呆機制：如果萬一抓不到最大值，預設給 20
	if max_dodges == null or max_dodges <= 0:
		max_dodges = 20
		
	# 計算百分比並更新進度條
	if current_dodges != null and is_instance_valid(dodge_bar): 
		dodge_bar.value = (float(current_dodges) / float(max_dodges)) * 100.0
func _update_talisman_values(weapon: Node) -> void:
	var charge = weapon.get("current_talisman_charge")
	var is_enhanced = weapon.get("is_enhanced_mode")
	
	if charge != null and is_instance_valid(talisman_charge_bar): 
		talisman_charge_bar.value = (float(charge) / 50.0) * 100.0
		
	if is_enhanced != null and is_instance_valid(talisman_enhanced_bar):
		if is_enhanced:
			talisman_enhanced_bar.show()
			talisman_enhanced_bar.value = 100.0
		else:
			talisman_enhanced_bar.hide()

# ==========================================
# 🛠️ UI 輔助底層控制
# ==========================================
func _refresh_weapon_icons(weapon: Node) -> void:
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
	ui_element.tint_progress = Color(0.8, 0.4, 0.1, 0.6) if is_combo_grace else Color(0.15, 0.15, 0.15, 0.8)
	
func _swap_dynamic_icon(ui_element: TextureProgressBar, icon_texture: Texture2D) -> void:
	if not is_instance_valid(ui_element) or icon_texture == null: return
	ui_element.texture_under = icon_texture
	ui_element.texture_progress = icon_texture
