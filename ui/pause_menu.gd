extends CanvasLayer

# ==========================================
# 🎒 裝備介面專用變數
# ==========================================
@onready var status_label: Label = $LoadoutPanel/StatusLabel
@onready var btn_katana: Button = $LoadoutPanel/HBoxContainer/BtnKatana
@onready var btn_spear: Button = $LoadoutPanel/HBoxContainer/BtnSpear
@onready var btn_talisman: Button = $LoadoutPanel/HBoxContainer/BtnTalisman
@onready var apply_button: Button = $LoadoutPanel/ApplyButton

# 暫存玩家在面板上選了哪些武器
var selected_weapons: Array[String] = []

# ==========================================
# 🔗 節點參考 (Node References)
# ==========================================
@onready var settings_panel: Control = $SettingsPanel 
@onready var main_pause_ui: Control = $VBoxContainer 

# 改為不強制綁定，等 _ready 時再安全獲取
var loadout_panel: Control = null

# ==========================================
# ⚙️ 初始化 (Initialization)
# ==========================================
func _ready() -> void:
	# 使用 get_node_or_null，這樣就算你還沒做裝備介面也不會報錯！
	loadout_panel = get_node_or_null("LoadoutPanel")
	
	hide_menu()
	if loadout_panel: loadout_panel.hide()
	
	if loadout_panel:
		btn_katana.pressed.connect(_on_weapon_toggle.bind("katana"))
		btn_spear.pressed.connect(_on_weapon_toggle.bind("spear"))
		btn_talisman.pressed.connect(_on_weapon_toggle.bind("talisman"))
		apply_button.pressed.connect(_on_apply_loadout_pressed)
		
# ==========================================
# 🎮 全域輸入攔截 (Global Input)
# ==========================================
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if get_tree().current_scene != null and get_tree().current_scene.name == "TitleScreen":
			return
			
		var players = get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			var p = players[0]
			if p.get("is_input_locked") == true:
				print("🚫 [PauseMenu] 領域展開中，系統拒絕暫停！")
				return 
			
		# 如果在設定或裝備介面，按 Esc 就退回暫停主選單
		if settings_panel.visible:
			_on_back_from_settings()
		elif loadout_panel and loadout_panel.visible:
			_on_back_from_loadout()
		else:
			toggle_pause()

# ==========================================
# ⏸️ 暫停邏輯控制 (Pause Controls)
# ==========================================
func toggle_pause() -> void:
	var new_pause_state = !get_tree().paused
	get_tree().paused = new_pause_state
	visible = new_pause_state
	
	_set_game_ui_visible(!new_pause_state)
	
	if new_pause_state:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		main_pause_ui.show()
		settings_panel.hide()
		if loadout_panel: loadout_panel.hide()
		Engine.time_scale = 1.0 
	else:
		var current_scale = 1.0
		var players = get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			var p = players[0]
			if p.get("current_time_scale") != null:
				current_scale = p.current_time_scale
		
		Engine.time_scale = current_scale
		hide_menu()

func _set_game_ui_visible(is_visible: bool) -> void:
	get_tree().call_group("HUD", "set_visible", is_visible)
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		var p = players[0]
		if p.has_node("InteractionIcon"):
			if is_visible:
				p.get_node("InteractionIcon").visible = not p.interacting_with.is_empty()
			else:
				p.get_node("InteractionIcon").visible = false
				
func hide_menu() -> void:
	get_tree().paused = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN 

# ==========================================
# 📡 按鈕訊號接收 (Button Signals)
# ==========================================
func _on_resume_button_pressed() -> void:
	toggle_pause()

func _on_settings_button_pressed() -> void:
	main_pause_ui.hide()
	settings_panel.show()

func _on_back_from_settings() -> void:
	settings_panel.hide()
	main_pause_ui.show()

func _on_loadout_button_pressed() -> void:
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		var p = players[0]
		var current_state = p.state_machine.current_state.name.to_lower()
		
		if current_state != "idle":
			print("🚫 [系統] 戰鬥中或處於非待機狀態，無法更換裝備！")
			return
			
		# 🌟 讀取玩家當前的裝備，載入到面板的暫存陣列裡
		selected_weapons = p.get("equipped_weapon_ids").duplicate()
		_update_loadout_ui() # 刷新畫面文字
			
	print("🎒 [系統] 玩家處於安全待機狀態，允許開啟裝備介面！")
	main_pause_ui.hide()
	if loadout_panel: loadout_panel.show()

# ==========================================
# 🎒 裝備面板邏輯 (Loadout System)
# ==========================================

# 1. 玩家點擊單個武器按鈕時觸發
func _on_weapon_toggle(weapon_id: String) -> void:
	# 如果這把武器已經被選了，就取消選擇
	if weapon_id in selected_weapons:
		selected_weapons.erase(weapon_id)
	else:
		# 如果還沒選，且目前已經選滿 2 把了，就把最舊的那把踢掉 (pop_front)
		if selected_weapons.size() >= 2:
			selected_weapons.pop_front()
		# 加入新選的武器
		selected_weapons.append(weapon_id)
		
	_update_loadout_ui()

# 2. 更新面板上的文字提示 (與按鈕狀態)
func _update_loadout_ui() -> void:
	if status_label:
		# 把陣列轉成逗號分隔的字串，方便玩家看
		var display_text = ", ".join(selected_weapons)
		if selected_weapons.size() == 0:
			display_text = "無"
		status_label.text = "目前選擇：" + display_text
		
# 3. 按下「確認裝備」時觸發
func _on_apply_loadout_pressed() -> void:
	# 防呆：不准空手出門！
	if selected_weapons.size() == 0:
		status_label.text = "⚠️ 請至少選擇一把武器！"
		return
		
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		var p = players[0]
		# 🌟 呼叫 Player 的裝備函數，把陣列傳進去！
		p.equip_loadout(selected_weapons.duplicate())
		print("✅ 裝備更新成功：", selected_weapons)
		
		# 換裝完畢，自動關閉裝備介面退回暫停主選單
		_on_back_from_loadout()
		
func _on_back_from_loadout() -> void:
	if loadout_panel: loadout_panel.hide()
	main_pause_ui.show()

func _on_quit_button_pressed() -> void:
	get_tree().paused = false          
	hide()                             
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE 
	Game.back_to_title()
