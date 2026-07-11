extends Control
## 戰鬥 UI 監視器 (重構版)

@export var player: Player

# --- 通用技能槽群組 ---
@onready var skill_slots = $HBoxContainer
@onready var switch_ui = $HBoxContainer/SwitchWeapon
# 🌟 新增：使用陣列統一管理 3 個獨立的武藝卡帶 UI 節點
@onready var art_uis: Array[TextureProgressBar] = [
	$HBoxContainer/Art1,
	$HBoxContainer/Art2,
	$HBoxContainer/Art3
]
# 🌟 每個圖標右下角顯示的能量需求數字
@onready var art_cost_labels: Array[Label] = [
	$HBoxContainer/Art1/CostLabel,
	$HBoxContainer/Art2/CostLabel,
	$HBoxContainer/Art3/CostLabel
]
# 🌟 血包圖標是獨立節點（不在 HBoxContainer 裡），刻意放在比 KatanaResources 等武器面板更左邊的位置——
# 畫面配置是最右邊武藝能量+武藝圖標+切換鍵、中間武器專屬面板、最左邊才是道具
@onready var health_item_ui: TextureProgressBar = $HealthItemUI
@onready var health_item_charge_label: Label = $HealthItemUI/ChargeLabel
# 🌟 每個圖標各自追蹤自己目前播放中的顏色 tween，播新的之前先把舊的殺掉，
# 不然「按著修飾鍵的呼吸燈」跟「能量不足的紅色警示」兩個效果同時搶同一個 modulate 屬性會互相打架、糊成一團
var _art_color_tweens: Array[Tween] = [null, null, null]

# --- 專屬資源面板 ---
@onready var katana_ui = $KatanaResources
@onready var dodge_bar = $KatanaResources/DodgeBar 

@onready var spear_ui = $SpearResources
@onready var pozhen_bar = $SpearResources/PozhenBar

@onready var talisman_ui = $TalismanResources
@onready var talisman_charge_bar = $TalismanResources/ChargeBar
@onready var talisman_enhanced_bar = $TalismanResources/EnhancedBar

# --- 武藝能量（全域資源，不分武器，一直顯示） ---
@onready var martial_energy_bar: ProgressBar = $MartialEnergyBar
@onready var martial_energy_label: Label = $MartialEnergyLabel

# --- 內部快取變數 ---
var cached_weapon: Node = null 
var ui_tween: Tween 

func _ready() -> void:
	if katana_ui: katana_ui.modulate.a = 0.0
	if spear_ui: spear_ui.modulate.a = 0.0
	if talisman_ui: talisman_ui.modulate.a = 0.0

	# 🌟 耗能數字預設隱藏，只有按著武藝修飾鍵時才跟著圖標一起淡入（見 _on_player_martial_mode_changed）
	for label in art_cost_labels:
		if is_instance_valid(label): label.modulate.a = 0.0

	# 🌟 核心對接：監聽大腦的組合鍵訊號，啟動技能圖標高亮特效
	if is_instance_valid(player):
		if not player.martial_mode_changed.is_connected(_on_player_martial_mode_changed):
			player.martial_mode_changed.connect(_on_player_martial_mode_changed)
		if player.has_signal("martial_art_denied") and not player.martial_art_denied.is_connected(_on_martial_art_denied):
			player.martial_art_denied.connect(_on_martial_art_denied)

func _process(_delta: float) -> void:
	if not is_instance_valid(player): return

	# 0. 血包圖標與剩餘次數（跟武器無關，永遠顯示）
	_update_health_item_ui()

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
		var m_slots = current_weapon.get("martial_slots")
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

				# 🌟 圖標右下角顯示這個武藝的能量需求
				var cost_label = art_cost_labels[i] if i < art_cost_labels.size() else null
				if is_instance_valid(cost_label) and m_slots is Array and m_slots.size() > i and is_instance_valid(m_slots[i]):
					var cost = m_slots[i].get("energy_cost") if "energy_cost" in m_slots[i] else 0.0
					cost_label.text = str(roundi(cost)) if float(cost) == roundi(cost) else ("%.1f" % cost)
			else:
				art_ui.hide()
		
	# 5. 各武器專屬量表更新
	match current_weapon_id:
		"katana": _update_katana_values(current_weapon)
		"spear": _update_spear_values(current_weapon)
		"talisman": _update_talisman_values(current_weapon)

	# 6. 武藝能量（跟武器無關，永遠顯示）
	_update_martial_energy_bar()

# ==========================================
# 📡 訊號接收：組合鍵高亮呼吸燈 / 能量不足警示
# ==========================================
const HIGHLIGHT_COLOR := Color(0.8, 1.0, 0.9, 1.0) ## 按著修飾鍵時的高亮色：淡藍綠色 (取代原本偏黃的配色)
const DENIED_COLOR := Color(1.8, 0.35, 0.35, 1.0)  ## 能量不足時的警示色：紅色

func _on_player_martial_mode_changed(is_active: bool) -> void:
	# 當玩家按下修改鍵(Alt/Shift)時，讓 3 個武藝圖標整體放大並變色提示，耗能數字也跟著一起淡入/淡出
	for i in range(art_uis.size()):
		var art_ui = art_uis[i]
		if is_instance_valid(art_ui) and art_ui.visible:
			_kill_color_tween(i)
			var tween = create_tween().set_parallel(true)
			_art_color_tweens[i] = tween
			var cost_label = art_cost_labels[i] if i < art_cost_labels.size() else null
			if is_active:
				tween.tween_property(art_ui, "modulate", HIGHLIGHT_COLOR, 0.12) # 淡藍綠色漸入
				tween.tween_property(art_ui, "scale", Vector2(1.1, 1.1), 0.12)   # 明顯放大
				if is_instance_valid(cost_label):
					tween.tween_property(cost_label, "modulate:a", 1.0, 0.12)   # 耗能數字跟著淡入
			else:
				tween.tween_property(art_ui, "modulate", Color.WHITE, 0.15)     # 漸出回白
				tween.tween_property(art_ui, "scale", Vector2(1.0, 1.0), 0.15)
				if is_instance_valid(cost_label):
					tween.tween_property(cost_label, "modulate:a", 0.0, 0.15)   # 耗能數字跟著淡出

## 該槽位確實有裝備武藝，但按下當下能量不夠——圖標紅色閃爍漸出 + 搖晃提示玩家
func _on_martial_art_denied(slot_index: int) -> void:
	var idx = slot_index - 1
	if idx < 0 or idx >= art_uis.size(): return
	var art_ui = art_uis[idx]
	if not is_instance_valid(art_ui) or not art_ui.visible: return

	_kill_color_tween(idx)
	var color_tween = create_tween()
	_art_color_tweens[idx] = color_tween
	color_tween.tween_property(art_ui, "modulate", DENIED_COLOR, 0.05)
	color_tween.tween_property(art_ui, "modulate", Color.WHITE, 0.35).set_trans(Tween.TRANS_SINE)

	# 搖晃：以圖標當下的 position 為基準左右快速擺動幾下
	var base_pos = art_ui.position
	var shake_tween = create_tween()
	shake_tween.tween_property(art_ui, "position", base_pos + Vector2(-5, 0), 0.035)
	shake_tween.tween_property(art_ui, "position", base_pos + Vector2(5, 0), 0.035)
	shake_tween.tween_property(art_ui, "position", base_pos + Vector2(-3, 0), 0.035)
	shake_tween.tween_property(art_ui, "position", base_pos + Vector2(3, 0), 0.035)
	shake_tween.tween_property(art_ui, "position", base_pos, 0.03)

const CAST_AFTERIMAGE_COLOR := Color(0.3, 2.2, 0.9, 0.9) ## 武藝施放成功的殘影色：偏亮的綠色（HDR 強度撞出發光感）

## 武藝真的成功放出來時（能量閘門通過），在圖標後方炸出一個放大淡出的綠色殘影
func _on_weapon_martial_art_cast(slot_index: int) -> void:
	var idx = slot_index - 1
	if idx < 0 or idx >= art_uis.size(): return
	var art_ui = art_uis[idx]
	if not is_instance_valid(art_ui) or not art_ui.visible: return

	# 🛡️ 掛在圖標自己底下（而不是丟給 HBoxContainer 當兄弟節點）——
	# HBoxContainer 是 Container，多塞一個子節點進去會觸發重新排版，把旁邊的圖標一起擠歪
	var afterimage := TextureRect.new()
	afterimage.texture = art_ui.texture_under
	afterimage.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	afterimage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	afterimage.size = art_ui.size
	afterimage.position = Vector2.ZERO
	afterimage.pivot_offset = art_ui.size / 2.0
	afterimage.modulate = CAST_AFTERIMAGE_COLOR
	art_ui.add_child(afterimage)

	var tween = create_tween().set_parallel(true)
	tween.tween_property(afterimage, "scale", Vector2(1.5, 1.5), 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(afterimage, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(afterimage.queue_free)

func _kill_color_tween(idx: int) -> void:
	var old_tween = _art_color_tweens[idx]
	if is_instance_valid(old_tween) and old_tween.is_valid():
		old_tween.kill()

# ==========================================
# 🎬 視覺過場：武器切換漸變
# ==========================================
func _handle_weapon_ui_transition(new_weapon: Node) -> void:
	# 🌟 施放成功特效訊號跟著武器本體走，換武器時要先解掉舊武器的連接，再接上新武器的
	if is_instance_valid(cached_weapon) and cached_weapon.has_signal("martial_art_cast") and cached_weapon.martial_art_cast.is_connected(_on_weapon_martial_art_cast):
		cached_weapon.martial_art_cast.disconnect(_on_weapon_martial_art_cast)
	if is_instance_valid(new_weapon) and new_weapon.has_signal("martial_art_cast") and not new_weapon.martial_art_cast.is_connected(_on_weapon_martial_art_cast):
		new_weapon.martial_art_cast.connect(_on_weapon_martial_art_cast)

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
## 血包圖標：跟裝備的武器無關，永遠顯示；圖標本身跟著 HealthPack.tscn 上設定的 icon 走
func _update_health_item_ui() -> void:
	if not is_instance_valid(health_item_ui): return

	var h_item = player.get("health_item")
	if not is_instance_valid(h_item):
		health_item_ui.hide()
		return

	var h_icon = h_item.get("icon")
	if h_icon:
		if health_item_ui.texture_under != h_icon:
			_swap_dynamic_icon(health_item_ui, h_icon)
		health_item_ui.show()
	else:
		health_item_ui.hide()

	if is_instance_valid(health_item_charge_label):
		health_item_charge_label.text = str(h_item.get("current_charges")) + "/" + str(h_item.get("max_charges"))

func _update_spear_values(weapon: Node) -> void:
	var pozhen = weapon.get("current_pozhen")
	var max_pozhen = weapon.get("MAX_POZHEN") if weapon.get("MAX_POZHEN") else 120.0

	if pozhen != null and is_instance_valid(pozhen_bar):
		pozhen_bar.value = (float(pozhen) / float(max_pozhen)) * 100.0
			
## 武藝能量：全域資源，不分武器，跟太刀劍意值(current_iai)是兩回事
func _update_martial_energy_bar() -> void:
	if not is_instance_valid(martial_energy_bar): return

	var current_energy = player.get("martial_energy")
	var max_energy = player.get("MAX_MARTIAL_ENERGY")

	# 🛡️ 防呆機制：const 透過 .get() 抓不到時，預設給 10
	if max_energy == null or max_energy <= 0:
		max_energy = 10.0
	if current_energy == null:
		current_energy = 0.0

	martial_energy_bar.value = (float(current_energy) / float(max_energy)) * 100.0

	if is_instance_valid(martial_energy_label):
		# 🔧 能量都是 0.2/1.0 這種小數增量，四捨五入成整數顯示會誤導（例如打3下明明才 0.6，卻顯示成 1）
		martial_energy_label.text = "武藝能量 %.1f/%d" % [current_energy, roundi(max_energy)]

func _update_katana_values(weapon: Node) -> void:
	# 抓取太刀本體的劍意值 (Iai)
	var current_iai = weapon.get("current_iai")
	var max_iai = weapon.get("MAX_IAI")

	# 🛡️ 防呆機制：如果萬一抓不到最大值，預設給 20
	if max_iai == null or max_iai <= 0:
		max_iai = 20

	# 計算百分比並更新進度條
	if current_iai != null and is_instance_valid(dodge_bar):
		dodge_bar.value = (float(current_iai) / float(max_iai)) * 100.0
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
	pass

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
