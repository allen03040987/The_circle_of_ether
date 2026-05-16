extends Control
## 遊戲設定面板 (Settings Panel)

@onready var walk_toggle: CheckButton = $Panel/VBoxContainer/WalkToggle

# ==========================================
# ⚙️ 初始化 (Initialization)
# ==========================================
func _ready() -> void:
	# 1. 綁定可視狀態改變的訊號 (只要打開/關閉面板就會觸發)
	visibility_changed.connect(_on_visibility_changed)
	
	# 2. 綁定按鈕被玩家手動點擊時的訊號
	walk_toggle.toggled.connect(_on_walk_toggled)
	
	# 3. 初始刷新一次
	_refresh_ui_state()

# ==========================================
# 🔄 狀態刷新 (State Refresh)
# ==========================================
## 當面板顯示或隱藏時自動觸發
func _on_visibility_changed() -> void:
	if visible: # 只有在「打開面板」的那一瞬間才刷新
		_refresh_ui_state()

func _refresh_ui_state() -> void:

	walk_toggle.set_pressed_no_signal(Game.config_default_walking)

# ==========================================
# 📡 UI 互動與訊號廣播 (UI Interaction & Signals)
# ==========================================
func _on_walk_toggled(toggled_on: bool) -> void:
	Game.config_default_walking = toggled_on
	Game.save_settings()
	print("⚙️ 面板設定已儲存：常駐行走 = ", toggled_on)
	
	# 廣播給 Player 讓它即刻生效
	Game.settings_changed.emit()
