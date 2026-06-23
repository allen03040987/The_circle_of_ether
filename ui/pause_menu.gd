extends CanvasLayer

# ==========================================
# 🔗 節點參考與初始化
# ==========================================
@onready var settings_panel: Control = $SettingsPanel 
@onready var main_pause_ui: Control = $VBoxContainer 
@onready var loadout_panel = $LoadoutPanel

var _volume_tween: Tween
var _normal_volume: float = 0.0
@onready var _master_bus_idx: int = AudioServer.get_bus_index("Master")

func _ready() -> void:
	_normal_volume = AudioServer.get_bus_volume_db(_master_bus_idx)
	hide_menu()
	if loadout_panel: 
		loadout_panel.hide()
		# 🌟 連接新場景的關閉信號
		loadout_panel.menu_closed.connect(_on_back_from_loadout)
		
	if settings_panel and not settings_panel.back_requested.is_connected(_on_back_from_settings):
		settings_panel.back_requested.connect(_on_back_from_settings)
		
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
		
		if settings_panel.visible: 
			# 🌟 核心修正：總機要先檢查設定面板裡面的「按鍵選單」是不是開著的
			if settings_panel.get("keybind_menu") and settings_panel.keybind_menu.visible:
				settings_panel._on_keybind_menu_closed() # 是開著的，就只准關按鍵選單
			else:
				_on_back_from_settings() # 沒開按鍵選單，才允許關閉整個設定面板
				
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
	# 🌟 核心升級：從 HIDDEN(僅隱藏) 改為 CAPTURED(隱藏並鎖定於螢幕正中心)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED 
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
func _on_back_from_loadout() -> void: main_pause_ui.show() # 僅需顯示主選單，關閉與隱藏由新場景腳本自己處理

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
			
		main_pause_ui.hide()
		# 🌟 完美的職責分工：把核心 Player 節點丟過去，讓新場景自己去讀取並刷新選單內容
		if loadout_panel: 
			loadout_panel.open_menu(p)
