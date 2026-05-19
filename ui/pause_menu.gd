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

# 🎵 暫停音量控制變數
var _volume_tween: Tween
var _normal_volume: float = 0.0
@onready var _master_bus_idx: int = AudioServer.get_bus_index("Master")

# 改為不強制綁定，等 _ready 時再安全獲取
var loadout_panel: Control = null

# ==========================================
# ⚙️ 初始化 (Initialization)
# ==========================================
func _ready() -> void:
	# 🌟 記錄遊戲原本的 Master 音量
	_normal_volume = AudioServer.get_bus_volume_db(_master_bus_idx)
	
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
		
		var current_scene = get_tree().current_scene
		if not current_scene: return
		
		# ==========================================
		# 🛡️ 出場限制防護牆 (The Bouncer's List)
		# ==========================================
		# 1. 標題畫面絕對不准暫停！
		if current_scene.name == "TitleScreen":
			return
			
		if current_scene.name == "Select":
			return
			
		
			
		# 2. 轉場期間 (Game.is_transitioning) 絕對不准暫停！
		if Game.is_transitioning:
			print("🚫 [PauseMenu] 轉場中，拒絕暫停！")
			return
			
		var players = get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			var p = players[0]
			
			# 3. 領域展開 (時停/大招) 期間拒絕暫停！
			if p.get("is_input_locked") == true:
				print("🚫 [PauseMenu] 領域展開中，系統拒絕暫停！")
				return 
				
			# 4. 玩家死掉 (Dying/Death) 時絕對不准暫停！(防止死亡畫面被暫停卡死)
			if p.has_node("StateMachine") and p.state_machine.current_state:
				var p_state = p.state_machine.current_state.name.to_lower()
				if p_state in ["dying", "death"]:
					print("🚫 [PauseMenu] 玩家已陣亡，拒絕暫停！")
					return
					
			# 5. 如果有 GameOverScreen 且正在顯示，拒絕暫停！
			if p.has_node("CanvasLayer/GameOverScreen") and p.get_node("CanvasLayer/GameOverScreen").visible:
				return
		
		# ==========================================
		# 🚦 放行區 (進入選單邏輯)
		# ==========================================
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
		
		# 🌟 新增：暫停時，在 0.3 秒內將遊戲總音量降低（例如降到 -20 dB，留有一點模糊背景音）
		# 如果希望完全靜音，可以把 -20.0 改成 -60.0
		_fade_game_volume(-20.0, 0.3)
	else:
		var current_scale = 1.0
		var players = get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			var p = players[0]
			if p.get("current_time_scale") != null:
				current_scale = p.current_time_scale
		
		Engine.time_scale = current_scale
		hide_menu()
		
		# 🌟 新增：離開暫停時，在 0.3 秒內將音量平滑拉回正常！
		_fade_game_volume(_normal_volume, 0.3)

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

# 處理音量平滑漸變的工具函數
func _fade_game_volume(target_db: float, duration: float) -> void:
	if _volume_tween:
		_volume_tween.kill() # 確保前一次的漸變不會互相衝突
		
	_volume_tween = create_tween()
	# 核心：確保這個 Tween 在遊戲暫停 (tree.paused = true) 時也能正常運作！
	_volume_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	
	var current_vol = AudioServer.get_bus_volume_db(_master_bus_idx)
	_volume_tween.tween_method(
		func(vol: float): AudioServer.set_bus_volume_db(_master_bus_idx, vol),
		current_vol,
		target_db,
		duration
	)
	
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
	
	# 🌟 新增防護：退出前立刻把音量還原，並清空計時器
	if _volume_tween: _volume_tween.kill()
	AudioServer.set_bus_volume_db(_master_bus_idx, _normal_volume)
	
	Game.back_to_title()
