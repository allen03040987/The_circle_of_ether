extends Control
## 遊戲設定面板 (Settings Panel)

signal back_requested

@onready var walk_toggle: CheckButton = $Panel/ScrollContainer/VBoxContainer/WalkToggle
@onready var shake_toggle: CheckButton = $Panel/ScrollContainer/VBoxContainer/ShakeToggle
@onready var flash_toggle: CheckButton = $Panel/ScrollContainer/VBoxContainer/FlashToggle
@onready var damage_number_toggle: CheckButton = $Panel/ScrollContainer/VBoxContainer/DamageNumberToggle
@onready var music_volume_slider: HSlider = $Panel/ScrollContainer/VBoxContainer/MusicVolumeSlider
@onready var sfx_volume_slider: HSlider = $Panel/ScrollContainer/VBoxContainer/SfxVolumeSlider
@onready var fullscreen_toggle: CheckButton = $Panel/ScrollContainer/VBoxContainer/CheckButton
@onready var dev_mode_toggle: CheckButton = $Panel/ScrollContainer/VBoxContainer/DevModeToggle
@onready var keybind_button: Button = $Panel/ScrollContainer/VBoxContainer/KeybindButton
@onready var keybind_menu: Control = $KeybindMenu
@onready var back_button: Button = $BackButton



# ==========================================
# ⚙️ 初始化 (Initialization)
# ==========================================
func _ready() -> void:
	# 1. 綁定可視狀態改變的訊號
	visibility_changed.connect(_on_visibility_changed)
	
	# 2. 綁定按鈕點擊訊號
	walk_toggle.toggled.connect(_on_walk_toggled)
	shake_toggle.toggled.connect(_on_shake_toggled)
	flash_toggle.toggled.connect(_on_flash_toggled) # 🌟 2. 綁定白光開關的點擊事件
	damage_number_toggle.toggled.connect(_on_damage_number_toggled)
	music_volume_slider.value_changed.connect(_on_music_volume_changed)
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)

	if is_instance_valid(fullscreen_toggle) and not fullscreen_toggle.toggled.is_connected(_on_fullscreen_toggled):
		fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)

	if is_instance_valid(dev_mode_toggle) and not dev_mode_toggle.toggled.is_connected(_on_dev_mode_toggled):
		dev_mode_toggle.toggled.connect(_on_dev_mode_toggled)

	# 3. 初始刷新一次
	_refresh_ui_state()
	
	# 🌟 4. 綁定按鍵設定的點擊與關閉信號
	if is_instance_valid(keybind_button) and not keybind_button.pressed.is_connected(_on_keybind_button_pressed):
		keybind_button.pressed.connect(_on_keybind_button_pressed)
		
	if is_instance_valid(keybind_menu) and not keybind_menu.menu_closed.is_connected(_on_keybind_menu_closed):
		keybind_menu.menu_closed.connect(_on_keybind_menu_closed)
		
	# 🌟 5. 綁定返回按鈕
	if is_instance_valid(back_button) and not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)
# ==========================================
# 🔄 狀態刷新 (State Refresh)
# ==========================================
func _on_visibility_changed() -> void:
	if visible:
		_refresh_ui_state()
		
		# 🌟 核心修復 1：每次打開設定面板，確保回到「按鈕面板顯示、按鍵選單隱藏」的初始狀態
		if has_node("Panel"): $Panel.show()
		if keybind_menu: keybind_menu.hide()

func _refresh_ui_state() -> void:
	walk_toggle.set_pressed_no_signal(Game.config_auto_run)
	shake_toggle.set_pressed_no_signal(Game.config_enable_screen_shake)
	flash_toggle.set_pressed_no_signal(Game.config_enable_hit_flash) # 🌟 3. 同步白光開關的畫面狀態
	damage_number_toggle.set_pressed_no_signal(Game.config_enable_damage_numbers)
	music_volume_slider.set_value_no_signal(Game.config_music_volume)
	sfx_volume_slider.set_value_no_signal(Game.config_sfx_volume)


	var current_mode = DisplayServer.window_get_mode()
	var is_fullscreen = (current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	if is_instance_valid(fullscreen_toggle):
		fullscreen_toggle.set_pressed_no_signal(is_fullscreen)
	if is_instance_valid(dev_mode_toggle):
		dev_mode_toggle.set_pressed_no_signal(Game.config_dev_mode)
# ==========================================
# 📡 UI 互動與訊號廣播 (UI Interaction & Signals)
# ==========================================
func _on_walk_toggled(toggled_on: bool) -> void:
	Game.config_auto_run = toggled_on
	Game.save_settings()
	print("⚙️ 面板設定已儲存：自動奔跑 = ", toggled_on)
	Game.settings_changed.emit()

func _on_shake_toggled(toggled_on: bool) -> void:
	Game.config_enable_screen_shake = toggled_on
	Game.save_settings()
	print("⚙️ 面板設定已儲存：螢幕震動 = ", toggled_on)
	Game.settings_changed.emit()

# 🌟 4. 處理白光開關被點擊的邏輯
func _on_flash_toggled(toggled_on: bool) -> void:
	Game.config_enable_hit_flash = toggled_on
	Game.save_settings()
	print("⚙️ 面板設定已儲存：受擊白光 = ", toggled_on)

	# 廣播訊號，Enemy 的腳本會去讀這個值！
	Game.settings_changed.emit()

func _on_damage_number_toggled(toggled_on: bool) -> void:
	Game.config_enable_damage_numbers = toggled_on
	Game.save_settings()
	print("⚙️ 面板設定已儲存：顯示傷害飄字 = ", toggled_on)
	Game.settings_changed.emit()

func _on_music_volume_changed(value: float) -> void:
	Game.config_music_volume = value
	Game.apply_audio_volumes()
	Game.save_settings()
	Game.settings_changed.emit()

func _on_sfx_volume_changed(value: float) -> void:
	Game.config_sfx_volume = value
	Game.apply_audio_volumes()
	Game.save_settings()
	Game.settings_changed.emit()


# ==========================================
# ⌨️ 自定義按鍵選單切換邏輯
# ==========================================
func _on_keybind_button_pressed() -> void:
	if has_node("Panel"): $Panel.hide() 
	if is_instance_valid(back_button): back_button.hide() # 🌟 核心修正：打開按鍵選單時，把外層的返回鍵藏起來！
	
	if keybind_menu: keybind_menu.show()

func _on_keybind_menu_closed() -> void:
	if keybind_menu: keybind_menu.hide() # 🌟 保險起見，強制確認隱藏
	
	if has_node("Panel"): $Panel.show()
	if is_instance_valid(back_button): back_button.show() # 🌟 核心修正：關閉按鍵選單時，把外層的返回鍵還原回來

# ==========================================
# 🖥️ 視窗模式控制
# ==========================================
func _on_dev_mode_toggled(toggled_on: bool) -> void:
	Game.config_dev_mode = toggled_on
	Game.save_settings()
	print("⚙️ 面板設定已儲存：開發模式 = ", toggled_on)
	Game.settings_changed.emit()

func _on_fullscreen_toggled(toggled_on: bool) -> void:
	if toggled_on:
		# 切換為無邊框全螢幕 (Alt+Tab 切換最順暢的模式)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		# 切換回視窗化
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		
		# 貼心優化：退回視窗化時，自動將視窗置中，避免視窗卡在螢幕邊緣
		var screen_center = DisplayServer.screen_get_position() + DisplayServer.screen_get_size() / 2
		var window_size = DisplayServer.window_get_size()
		DisplayServer.window_set_position(screen_center - window_size / 2)
		
	# 如果你的 Game.gd (全域設定檔) 有準備儲存全螢幕的變數，也可以在這裡呼叫存檔
	Game.config_fullscreen = toggled_on
	Game.save_settings()
	
# ==========================================
# 🚪 返回鍵邏輯
# ==========================================
func _on_back_button_pressed() -> void:
	# 發送廣播，告訴外面的世界「我要返回了」
	back_requested.emit()

