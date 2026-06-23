extends Control 

# 🎵 🌟 新增：主選單音效設定
@export_group("音效設定")
@export var menu_bgm: AudioStream        # 主選單的背景音樂
@export var bgm_volume: float = -5.0     # 音樂音量
@export var hover_sfx: AudioStream       # 滑鼠游標滑過按鈕的聲音
@export var click_sfx: AudioStream       # 點擊按鈕的聲音

# ==========================================
# 🔗 節點參考 (Node References)
# ==========================================
@onready var v: VBoxContainer = $V
@onready var new_game: Button = $V/NewGame
@onready var load_game: Button = $V/LoadGame
@onready var vs_game: Button = $V/VsGame

@onready var settings_button: Button = $V/SettingsButton
@onready var settings_panel: Control = $SettingsPanel

# ==========================================
# ⚙️ 初始化 (Initialization)
# ==========================================
func  _ready() -> void:
	# 🎵 🌟 1. 遊戲一開，主選單音樂直接奏響！
	if menu_bgm:
		AudioManager.play_bgm(menu_bgm, bgm_volume)
		
	# 2. 確保一進主選單，滑鼠絕對會顯示出來
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# 2. 強制壓制全域暫停選單 (避免它不小心跑出來擋路)
	if has_node("/root/PauseMenu"):
		var pm = get_node("/root/PauseMenu")
		pm.hide()
		pm.visible = false
		get_tree().paused = false # 買個保險，確保時間流動正常
	
	# 3. 讀檔按鈕狀態判定
	load_game.disabled = not Game.has_save() 
	
	# 4. 啟用鍵盤/手把導航焦點，並 🌟 綁定 UI 音效！
	new_game.grab_focus() 
	for button: Button in v.get_children():
		button.mouse_entered.connect(button.grab_focus)
		
		# 🎵 🌟 綁定滑鼠滑過與點擊的音效
		if hover_sfx:
			button.focus_entered.connect(func(): AudioManager.play_sfx(hover_sfx, -10.0))
		if click_sfx:
			button.pressed.connect(func(): AudioManager.play_sfx(click_sfx, -5.0))
	
	# 🌟 新增：綁定設定按鈕與面板的返回信號
	if is_instance_valid(settings_button) and is_instance_valid(settings_panel):
		settings_panel.hide() # 預設隱藏
		if not settings_button.pressed.is_connected(_on_settings_button_pressed):
			settings_button.pressed.connect(_on_settings_button_pressed)
		if not settings_panel.back_requested.is_connected(_on_settings_back_requested):
			settings_panel.back_requested.connect(_on_settings_back_requested)
			
# ==========================================
# 🎮 主選單輸入 (Menu Input)
# ==========================================
func _unhandled_input(event: InputEvent) -> void:
	# 快捷鍵：在主選單按下 ESC 的邏輯分流
	if event.is_action_pressed("ui_cancel"):
		
		# 🌟 核心防護：如果設定面板正開著，ESC 是關閉面板
		if is_instance_valid(settings_panel) and settings_panel.visible:
			get_viewport().set_input_as_handled() # 消耗事件
			_on_settings_back_requested()
			
		# 如果在最外層主選單，ESC 才是關閉遊戲程式
		else:
			get_tree().quit()

# ==========================================
# ⚙️ 設定面板切換邏輯
# ==========================================
func _on_settings_button_pressed() -> void:
	v.hide() # 隱藏主選單的按鈕群，避免畫面重疊
	if settings_panel:
		settings_panel.show()

func _on_settings_back_requested() -> void:
	if settings_panel:
		settings_panel.hide()
	v.show() # 重新顯示主選單按鈕
	
	# 貼心優化：返回時自動幫玩家聚焦回第一個按鈕，支援鍵盤無縫操作
	if is_instance_valid(new_game):
		new_game.grab_focus()
# ==========================================
# 📡 按鈕訊號接收 (Button Signals)
# ==========================================
## 啟動新遊戲
func _on_new_game_pressed() -> void: 
	Game.new_game()

## 讀取存檔
func _on_load_game_pressed() -> void: 
	Game.load_game()

## 離開遊戲程式
func _on_exit_game_pressed() -> void: 
	get_tree().quit()

## 進入格鬥對戰模式
func _on_vs_game_pressed() -> void: 
	print("⚔️ 進入格鬥對戰模式！")
	
	# 🎵 🌟 讓主選單音樂在 1 秒內漸出消失，營造進入戰鬥的緊張感
	AudioManager.stop_bgm(1.0) 
	
	# 直接跳轉到選角大廳
	get_tree().change_scene_to_file("res://VsMods/ui/select.tscn")
