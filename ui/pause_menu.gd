extends CanvasLayer

# ==========================================
# 🎒 裝備介面專用變數
# ==========================================
@onready var status_label: Label = $LoadoutPanel/StatusLabel
@onready var apply_button: Button = $LoadoutPanel/ApplyButton

# 左右兩側的武器選單
@onready var weapon_opt_1: OptionButton = $LoadoutPanel/HBoxContainer/WeaponSlot1/WeaponOpt
@onready var weapon_opt_2: OptionButton = $LoadoutPanel/HBoxContainer/WeaponSlot2/WeaponOpt

# 左右兩側的武藝選單陣列
@onready var slot1_arts: Array[OptionButton] = [
	$LoadoutPanel/HBoxContainer/WeaponSlot1/ArtOpt1,
	$LoadoutPanel/HBoxContainer/WeaponSlot1/ArtOpt2,
	$LoadoutPanel/HBoxContainer/WeaponSlot1/ArtOpt3
]

@onready var slot2_arts: Array[OptionButton] = [
	$LoadoutPanel/HBoxContainer/WeaponSlot2/ArtOpt1,
	$LoadoutPanel/HBoxContainer/WeaponSlot2/ArtOpt2,
	$LoadoutPanel/HBoxContainer/WeaponSlot2/ArtOpt3
]

# ==========================================
# 🥋 武器與武藝資料庫 (DB)
# ==========================================
const AVAILABLE_WEAPONS = [
	{"id": "katana", "name": "太刀 (Katana)"},
	{"id": "spear", "name": "長槍 (Spear)"},
	{"id": "talisman", "name": "靈符 (Talisman)"},
	{"id": "sickle", "name": "鎖鐮 (Sickle)"}
]

const AVAILABLE_ARTS = {
	"katana": [
		{"name": "挑飛斬 (11)", "path": "res://player/MartialArts/Katana/Art_Katana_11.gd"},
		{"name": "升龍螺旋 (12)", "path": "res://player/MartialArts/Katana/Art_Katana_12.gd"},
		{"name": "裂地連斬·壹 (20)", "path": "res://player/MartialArts/Katana/Art_Katana_20.gd"},
		{"name": "裂地連斬·貳 (21)", "path": "res://player/MartialArts/Katana/Art_Katana_21.gd"},
		{"name": "斷空劍氣 (22)", "path": "res://player/MartialArts/Katana/Art_Katana_22.gd"}
	],
	"spear": [
		{"name": "向上挑飛 (22)", "path": "res://player/MartialArts/Spear/Art_Spear_22.gd"},
		{"name": "大範圍聚怪 (21)", "path": "res://player/MartialArts/Spear/Art_Spear_21.gd"}
	],
	"talisman": [
		{"name": "靈能護身塔 (20)", "path": "res://player/MartialArts/Talisman/Art_Talisman_20.gd"},
		{"name": "逐風符·昇 (30)", "path": "res://player/MartialArts/Talisman/Art_Talisman_30.gd"},
		{"name": "馭雷符·降 (31)", "path": "res://player/MartialArts/Talisman/Art_Talisman_31.gd"}
	],
	"sickle": []
}

# 暫存玩家的配置
var selected_weapons: Array[String] = ["katana", "spear"]
var selected_arts: Dictionary = {
	"katana": ["", "", ""], "spear": ["", "", ""], 
	"talisman": ["", "", ""], "sickle": ["", "", ""]
}

# ==========================================
# 🔗 節點參考與初始化
# ==========================================
@onready var settings_panel: Control = $SettingsPanel 
@onready var main_pause_ui: Control = $VBoxContainer 
var loadout_panel: Control = null

var _volume_tween: Tween
var _normal_volume: float = 0.0
@onready var _master_bus_idx: int = AudioServer.get_bus_index("Master")

func _ready() -> void:
	_normal_volume = AudioServer.get_bus_volume_db(_master_bus_idx)
	loadout_panel = get_node_or_null("LoadoutPanel")
	
	hide_menu()
	if loadout_panel: loadout_panel.hide()
	
	if loadout_panel and is_instance_valid(weapon_opt_1):
		_setup_ui_styles()
		_populate_weapon_dropdowns()
		
		# 連接訊號
		weapon_opt_1.item_selected.connect(_on_weapon_selected.bind(0))
		weapon_opt_2.item_selected.connect(_on_weapon_selected.bind(1))
		
		for i in range(3):
			slot1_arts[i].item_selected.connect(_on_art_selected.bind(0, i))
			slot2_arts[i].item_selected.connect(_on_art_selected.bind(1, i))
			
		apply_button.pressed.connect(_on_apply_loadout_pressed)

# 🌟 自動字體縮小系統：防止字體過大導致 UI 擠爆
func _setup_ui_styles() -> void:
	var all_opts = [weapon_opt_1, weapon_opt_2] + slot1_arts + slot2_arts
	for opt in all_opts:
		if is_instance_valid(opt):
			opt.add_theme_font_size_override("font_size", 16) # 強制將下拉選單字體縮小為 16
			

# ==========================================
# 🎮 全域輸入與暫停控制
# ==========================================
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var current_scene = get_tree().current_scene
		if not current_scene: return
		
		if current_scene.name == "TitleScreen" or current_scene.name == "Select": return
		if Game.is_transitioning: return
			
		var players = get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			var p = players[0]
			if p.has_node("StateMachine") and p.state_machine.current_state:
				var p_state = p.state_machine.current_state.name.to_lower()
				if p_state in ["dying", "death"]: return
			if p.has_node("CanvasLayer/GameOverScreen") and p.get_node("CanvasLayer/GameOverScreen").visible: return
		
		if settings_panel.visible: _on_back_from_settings()
		elif loadout_panel and loadout_panel.visible: _on_back_from_loadout()
		else: toggle_pause()

func toggle_pause() -> void:
	var new_pause_state = !get_tree().paused
	get_tree().paused = new_pause_state
	visible = new_pause_state
	_set_game_ui_visible(!new_pause_state)
	
	if CombatManager.has_method("set_ui_paused"): CombatManager.set_ui_paused(new_pause_state)
	
	if new_pause_state:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		main_pause_ui.show()
		settings_panel.hide()
		if loadout_panel: loadout_panel.hide()
		_fade_game_volume(-20.0, 0.3)
	else:
		hide_menu()
		_fade_game_volume(_normal_volume, 0.3)

func _set_game_ui_visible(is_visible: bool) -> void:
	get_tree().call_group("HUD", "set_visible", is_visible)
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		var p = players[0]
		if p.has_node("InteractionIcon"): p.get_node("InteractionIcon").visible = not p.interacting_with.is_empty() if is_visible else false
				
func hide_menu() -> void:
	get_tree().paused = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN 
	if CombatManager.has_method("set_ui_paused"): CombatManager.set_ui_paused(false)

func _fade_game_volume(target_db: float, duration: float) -> void:
	if _volume_tween: _volume_tween.kill()
	_volume_tween = create_tween()
	_volume_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var current_vol = AudioServer.get_bus_volume_db(_master_bus_idx)
	_volume_tween.tween_method(func(vol: float): AudioServer.set_bus_volume_db(_master_bus_idx, vol), current_vol, target_db, duration)
	
# ==========================================
# 📡 選單導航信號
# ==========================================
func _on_resume_button_pressed() -> void: toggle_pause()
func _on_settings_button_pressed() -> void: main_pause_ui.hide(); settings_panel.show()
func _on_back_from_settings() -> void: settings_panel.hide(); main_pause_ui.show()
func _on_back_from_loadout() -> void: if loadout_panel: loadout_panel.hide(); main_pause_ui.show()

func _on_quit_button_pressed() -> void:
	get_tree().paused = false          
	hide()                             
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE 
	if CombatManager.has_method("force_reset_time"): CombatManager.force_reset_time()
	if _volume_tween: _volume_tween.kill()
	AudioServer.set_bus_volume_db(_master_bus_idx, _normal_volume)
	Game.back_to_title()

func _on_loadout_button_pressed() -> void:
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		var p = players[0]
		if p.state_machine.current_state.name.to_lower() != "idle":
			print("🚫 [系統] 戰鬥中或處於非待機狀態，無法更換裝備！")
			return
			
		selected_weapons = p.get("equipped_weapon_ids").duplicate()
		if p.has_method("get_all_weapons_martial_arts"):
			selected_arts = p.call("get_all_weapons_martial_arts").duplicate(true)
			
		_sync_ui_to_data()
			
	main_pause_ui.hide()
	if loadout_panel: loadout_panel.show()

# ==========================================
# 🎒 裝備面板核心邏輯 (Dual-Column System)
# ==========================================

# 初始化武器下拉選單內容
func _populate_weapon_dropdowns() -> void:
	weapon_opt_1.clear()
	weapon_opt_2.clear()
	
	for i in range(AVAILABLE_WEAPONS.size()):
		var w_data = AVAILABLE_WEAPONS[i]
		weapon_opt_1.add_item(w_data["name"])
		weapon_opt_1.set_item_metadata(i, w_data["id"])
		weapon_opt_2.add_item(w_data["name"])
		weapon_opt_2.set_item_metadata(i, w_data["id"])

# 根據暫存資料，同步所有下拉選單的顯示狀態
func _sync_ui_to_data() -> void:
	if selected_weapons.size() < 2: selected_weapons = ["katana", "spear"] # 防呆
	
	# 設定武器下拉選單
	_set_opt_by_metadata(weapon_opt_1, selected_weapons[0])
	_set_opt_by_metadata(weapon_opt_2, selected_weapons[1])
	
	# 刷新兩邊的武藝下拉選單
	_refresh_art_dropdowns(0)
	_refresh_art_dropdowns(1)
	
	if status_label: status_label.text = "配置你的主副武器與武藝："

# 武器變更時：智慧防撞與同步更新
func _on_weapon_selected(item_index: int, slot_index: int) -> void:
	var new_weapon_id = AVAILABLE_WEAPONS[item_index]["id"]
	var other_slot = 1 if slot_index == 0 else 0
	
	# 如果選了另一邊已經裝備的武器，智慧互換兩者位置！
	if selected_weapons[other_slot] == new_weapon_id:
		selected_weapons[other_slot] = selected_weapons[slot_index]
	
	selected_weapons[slot_index] = new_weapon_id
	_sync_ui_to_data()

# 武藝變更時：寫入暫存字典，並防止重複裝備
func _on_art_selected(item_index: int, main_slot_index: int, art_slot_index: int) -> void:
	var w_id = selected_weapons[main_slot_index]
	var ui_slots = slot1_arts if main_slot_index == 0 else slot2_arts
	var selected_path = ui_slots[art_slot_index].get_item_metadata(item_index)
	
	# ==========================================
	# 🌟 新增：防止重複裝備武藝的智慧互換邏輯
	# ==========================================
	if selected_path != "": # 允許玩家重複選擇「未裝備武藝」(空字串)
		for i in range(3):
			# 如果發現其他槽位已經裝備了這個武藝
			if i != art_slot_index and selected_arts[w_id][i] == selected_path:
				# 把那個被搶走武藝的槽位，換成我們現在這個槽位原本裝的武藝
				var old_path = selected_arts[w_id][art_slot_index]
				selected_arts[w_id][i] = old_path
				break # 最多只會跟一個槽位重複，處理完就可以跳出迴圈
	
	# 正式寫入新的武藝路徑
	selected_arts[w_id][art_slot_index] = selected_path
	print("🥋 UI 配置快取：[", w_id, "] 的槽位 ", art_slot_index + 1, " 修改為 -> ", selected_path)
	
	# 🌟 強制刷新一次該欄位的 UI，確保剛剛發生「互換」的下拉選單文字正確更新！
	_refresh_art_dropdowns(main_slot_index)

# 刷新指定欄位的武藝下拉選單 (0=左欄, 1=右欄)
func _refresh_art_dropdowns(main_slot_index: int) -> void:
	var w_id = selected_weapons[main_slot_index]
	var target_arts_ui = slot1_arts if main_slot_index == 0 else slot2_arts
	var current_chosen_paths = selected_arts[w_id]
	var art_list = AVAILABLE_ARTS.get(w_id, [])
	
	for slot_idx in range(3):
		var opt_btn = target_arts_ui[slot_idx]
		opt_btn.clear()
		opt_btn.add_item("-- 未裝備武藝 --")
		opt_btn.set_item_metadata(0, "")
		
		# 如果這個武器根本沒有武藝可以選（例如鐮刀），直接禁用該下拉選單
		if art_list.size() == 0:
			opt_btn.disabled = true
			continue
			
		opt_btn.disabled = false
		var saved_path = current_chosen_paths[slot_idx]
		var select_target_id = 0
		
		for i in range(art_list.size()):
			var art_data = art_list[i]
			var item_id = i + 1
			opt_btn.add_item(art_data["name"])
			opt_btn.set_item_metadata(item_id, art_data["path"])
			
			if art_data["path"] == saved_path:
				select_target_id = item_id
				
		opt_btn.selected = select_target_id

func _set_opt_by_metadata(opt: OptionButton, meta_value: String) -> void:
	for i in range(opt.item_count):
		if opt.get_item_metadata(i) == meta_value:
			opt.selected = i
			return

# 打包發送設定
func _on_apply_loadout_pressed() -> void:
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		var p = players[0]
		
		var current_equipped = p.get("equipped_weapon_ids")
		var current_arts = p.call("get_all_weapons_martial_arts") if p.has_method("get_all_weapons_martial_arts") else {}
		
		if current_equipped == selected_weapons and current_arts == selected_arts:
			print("♻️ [系統] 裝備與武藝皆無更動！")
			_on_back_from_loadout()
			return
			
		if p.has_method("equip_loadout_with_arts"):
			p.call("equip_loadout_with_arts", selected_weapons.duplicate(), selected_arts.duplicate(true))
		else:
			p.equip_loadout(selected_weapons.duplicate())
			
		print("✅ 雙武器與武藝組件同步更新成功！")
		_on_back_from_loadout()
