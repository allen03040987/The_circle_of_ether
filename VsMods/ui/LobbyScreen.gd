extends Control
## 格鬥模式入口：選擇本機雙人 / 主機 / 加入房間。
## 線上模式連線成功後直接進 vs_world（跳過選角畫面），
## 離線模式進 SelectScreen 選武藝。
## 所有元素都是 LobbyScreen.tscn 裡真正的節點（無動態清單，比 SelectScreen
## 單純，全部可以直接在編輯器排版），按鈕點擊透過 .tscn 的 [connection] 宣告接。

@onready var _status_label: Label    = $StatusLabel
@onready var _code_edit:    LineEdit = $CodeEdit
@onready var _copy_btn:     Button   = $CopyButton

var _connect_timer: float = 0.0   # 連線等待計時，用於顯示進度
var _connecting:    bool  = false
var _room_code:     String = ""

func _ready() -> void:
	VsNetworkManager.room_created.connect(_on_room_created)
	VsNetworkManager.connected.connect(_on_connected)
	VsNetworkManager.connection_error.connect(_on_error)

func _process(delta: float) -> void:
	if not _connecting:
		return
	_connect_timer += delta
	_status_label.text = "連線中... %.0f 秒\n（伺服器首次喚醒最長需 60 秒）" % _connect_timer

# ── 按鈕動作 ──────────────────────────────────────────────────────────────────
func _on_offline() -> void:
	VsNetworkManager.start_offline()
	VsGameManager.selection_confirmed = false
	get_tree().change_scene_to_file("res://VsMods/ui/SelectScreen.tscn")

func _on_host() -> void:
	_start_connecting()
	VsNetworkManager.host_game()

func _on_join() -> void:
	var code: String = _code_edit.text.strip_edges().to_upper()
	if code.length() != 1:
		_status("請輸入 1 位房間代碼")
		return
	_start_connecting()
	VsNetworkManager.join_game(code)

func _start_connecting() -> void:
	_connecting    = true
	_connect_timer = 0.0

func _on_back() -> void:
	# 真正離開整個 VsMods 流程，這裡才是還原主遊戲 PauseMenu 的時機——見
	# ui/title_screen.gd::_on_vs_game_pressed() 的停用註解
	PauseMenu.process_mode = Node.PROCESS_MODE_INHERIT
	get_tree().change_scene_to_file("res://ui/title_screen.tscn")

func _on_settings() -> void:
	VsSettingsPanel.open_over(self)

# ── VsNetworkManager 信號 ─────────────────────────────────────────────────────
func _on_room_created(code: String) -> void:
	_connecting = false
	_room_code = code
	_copy_btn.visible = true
	_status("房間代碼：%s\n把這串代碼傳給對方，等待加入..." % code)

func _on_copy_code() -> void:
	DisplayServer.clipboard_set(_room_code)
	_copy_btn.text = "已複製！"
	get_tree().create_timer(1.5).timeout.connect(func(): _copy_btn.text = "複製代碼")

func _on_connected() -> void:
	_connecting = false
	_status("已連線！")
	VsGameManager.selection_confirmed = false
	get_tree().change_scene_to_file("res://VsMods/ui/SelectScreen.tscn")

func _on_error(msg: String) -> void:
	_connecting = false
	_status("錯誤：" + msg)

# ── 輔助 ──────────────────────────────────────────────────────────────────────
func _status(text: String) -> void:
	_status_label.text = text
