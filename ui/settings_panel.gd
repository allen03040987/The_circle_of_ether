extends Control
## 遊戲設定面板 (Settings Panel)

@onready var walk_toggle: CheckButton = $Panel/VBoxContainer/WalkToggle
@onready var shake_toggle: CheckButton = $Panel/VBoxContainer/ShakeToggle
@onready var flash_toggle: CheckButton = $Panel/VBoxContainer/FlashToggle # 🌟 1. 綁定新的白光開關節點

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
	
	# 3. 初始刷新一次
	_refresh_ui_state()

# ==========================================
# 🔄 狀態刷新 (State Refresh)
# ==========================================
func _on_visibility_changed() -> void:
	if visible:
		_refresh_ui_state()

func _refresh_ui_state() -> void:
	walk_toggle.set_pressed_no_signal(Game.config_default_walking)
	shake_toggle.set_pressed_no_signal(Game.config_enable_screen_shake)
	flash_toggle.set_pressed_no_signal(Game.config_enable_hit_flash) # 🌟 3. 同步白光開關的畫面狀態

# ==========================================
# 📡 UI 互動與訊號廣播 (UI Interaction & Signals)
# ==========================================
func _on_walk_toggled(toggled_on: bool) -> void:
	Game.config_default_walking = toggled_on
	Game.save_settings()
	print("⚙️ 面板設定已儲存：常駐行走 = ", toggled_on)
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
