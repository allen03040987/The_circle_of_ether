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

# ==========================================
# 🎮 主選單輸入 (Menu Input)
# ==========================================
func _unhandled_input(event: InputEvent) -> void:
	# 快捷鍵：在主選單按下 ESC 直接關閉遊戲程式
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()

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
