extends Control
## 格鬥模式入口：選擇本機雙人 / 主機 / 加入房間。
## 線上模式連線成功後直接進 vs_world（跳過選角畫面），
## 離線模式進 SelectScreen 選武藝。

const VIEW_W := 384
const VIEW_H := 216

var _status_label:  Label
var _code_edit:     LineEdit
var _connect_timer: float = 0.0   # 連線等待計時，用於顯示進度
var _connecting:    bool  = false

func _ready() -> void:
	_build_ui()
	VsNetworkManager.room_created.connect(_on_room_created)
	VsNetworkManager.connected.connect(_on_connected)
	VsNetworkManager.connection_error.connect(_on_error)

func _process(delta: float) -> void:
	if not _connecting:
		return
	_connect_timer += delta
	_status_label.text = "連線中... %.0f 秒\n（伺服器首次喚醒最長需 60 秒）" % _connect_timer

# ── 建立 UI ───────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.07, 0.07)
	add_child(bg)

	_label("格鬥模式", 0, 28, VIEW_W, 16, HORIZONTAL_ALIGNMENT_CENTER)

	var bw := 120
	var bx := (VIEW_W - bw) / 2
	var by := 65

	_btn("本機雙人", Vector2(bx, by), Vector2(bw, 18)).pressed.connect(_on_offline)
	by += 26

	_btn("主機 (Host)", Vector2(bx, by), Vector2(bw, 18)).pressed.connect(_on_host)
	by += 26

	# 加入行：代碼輸入 + 按鈕並排
	var edit := LineEdit.new()
	edit.placeholder_text = "6位房間代碼"
	edit.position  = Vector2(bx - 4, by)
	edit.size      = Vector2(84, 18)
	edit.max_length = 6
	edit.add_theme_font_size_override("font_size", 10)
	add_child(edit)
	_code_edit = edit

	_btn("加入", Vector2(bx + 86, by), Vector2(36, 18)).pressed.connect(_on_join)
	by += 30

	# 狀態文字
	_status_label = _label("", 0, by, VIEW_W, 14, HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.modulate = Color(0.75, 0.75, 0.75)

	# 返回
	_btn("← 返回", Vector2(6, VIEW_H - 24), Vector2(56, 16)).pressed.connect(_on_back)

	# 開發提示
	_label("（開發測試：先在終端機執行 python server/signaling_server.py）",
		0, VIEW_H - 12, VIEW_W, 10, HORIZONTAL_ALIGNMENT_CENTER).modulate = Color(0.4, 0.4, 0.4)

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
	if code.length() != 6:
		_status("請輸入 6 位房間代碼")
		return
	_start_connecting()
	VsNetworkManager.join_game(code)

func _start_connecting() -> void:
	_connecting    = true
	_connect_timer = 0.0

func _on_back() -> void:
	get_tree().change_scene_to_file("res://ui/title_screen.tscn")

# ── VsNetworkManager 信號 ─────────────────────────────────────────────────────
func _on_room_created(code: String) -> void:
	_connecting = false
	_status("房間代碼：%s\n把這串代碼傳給對方，等待加入..." % code)

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

func _btn(text: String, pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.text     = text
	b.position = pos
	b.size     = sz
	b.add_theme_font_size_override("font_size", 10)
	add_child(b)
	return b

func _label(text: String, x: int, y: int, w: int, fsize: int,
		align: HorizontalAlignment) -> Label:
	var lbl := Label.new()
	lbl.text                    = text
	lbl.position                = Vector2(x, y)
	lbl.size                    = Vector2(w, fsize + 4)
	lbl.horizontal_alignment    = align
	lbl.add_theme_font_size_override("font_size", fsize)
	add_child(lbl)
	return lbl
