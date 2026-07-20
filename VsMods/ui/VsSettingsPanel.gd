class_name VsSettingsPanel
extends Control
## VsMods 專屬設定面板（精簡版，跟 VsMods 曫停選單同一種風格：全程式碼建立
## 節點）。刻意不套用主遊戲 ui/settings_panel.tscn——那份面板有一堆跟 VsMods
## 無關的選項（自動奔跑、傷害飄字、驚嘆號大小…），全部塞進來對戰中的暫停選單
## 反而讓人分不清哪些跟這個模式有關。這裡只放使用者實際要的三項：霸體輪廓、
## 震動、改按鍵——霸體輪廓/震動兩個開關讀寫的是 Game.config_enable_status_outline
## / Game.config_enable_screen_shake，跟主遊戲共用同一份設定（VsPlayer 的
## _update_status_outline()/vfx_shake() 早就在讀這兩個值，這裡只是補上能調
## 的入口，不是新開一條設定）。

signal closed

const VIEW_W := 384
const VIEW_H := 216
const PW := 150
const PH := 100

var _keybind_menu: VsKeybindMenu

## 共用開啟入口——包一層獨立 CanvasLayer 蓋在 parent 現有畫面之上，關閉時
## 自動整層 queue_free()。呼叫端（vs_world 暫停選單／LobbyScreen「設定」鍵）
## 都用這個，不用各自重複「建 CanvasLayer→掛 panel→接 closed 訊號→queue_free」
## 這段樣板。回傳建立的 CanvasLayer，呼叫端如果需要拿來判斷「選單開著嗎」
## （例如 vs_world 的滑鼠鎖定邏輯）可以自己存起來，用 tree_exited 訊號得知
## 何時被關閉；不需要的話可以不接收回傳值。
static func open_over(parent: Node, layer: int = 21) -> CanvasLayer:
	var canvas := CanvasLayer.new()
	canvas.layer = layer
	parent.add_child(canvas)
	var panel := VsSettingsPanel.new()
	panel.closed.connect(func(): canvas.queue_free())
	canvas.add_child(panel)
	return canvas

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

## Esc 關閉——VsKeybindMenu 是這個節點的子節點，兩者都各自處理 ui_cancel：
## 按鍵選單開著時，它自己的 _unhandled_input() 會先收到事件（子節點先於父節點）
## 並呼叫 set_input_as_handled()，這裡就不會再收到，等於「先關掉按鍵選單那層，
## 不會一次跳兩層」；按鍵選單沒開著時才會輪到這裡處理，直接關掉整個設定面板。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color        = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2((VIEW_W - PW) / 2.0, (VIEW_H - PH) / 2.0)
	panel.size     = Vector2(PW, PH)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text                 = "設定"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	vbox.add_child(title)

	var outline_toggle := CheckButton.new()
	outline_toggle.text = "霸體輪廓特效"
	outline_toggle.add_theme_font_size_override("font_size", 9)
	outline_toggle.set_pressed_no_signal(Game.config_enable_status_outline)
	outline_toggle.toggled.connect(_on_outline_toggled)
	vbox.add_child(outline_toggle)

	var shake_toggle := CheckButton.new()
	shake_toggle.text = "畫面震動"
	shake_toggle.add_theme_font_size_override("font_size", 9)
	# ⚠ 這裡刻意反著接：實測勾選＝震動關閉、取消勾選＝震動開啟，跟 Game.
	# config_enable_screen_shake 這個名字暗示的方向相反（根因待查，可能是
	# PixelTheme 的 checkbox_checked.png/checkbox_unchecked.png 兩張圖畫反了，
	# 或別的視覺層問題）——使用者要求先用反接的方式讓「勾選＝有震動」這個
	# 直覺對上實際效果，不用等根因查清楚，之後若要正本清源，回來對調兩張圖或
	# 找出真正的反相點，記得同時把這裡的反接拿掉。
	shake_toggle.set_pressed_no_signal(not Game.config_enable_screen_shake)
	shake_toggle.toggled.connect(_on_shake_toggled)
	vbox.add_child(shake_toggle)

	var keybind_btn := Button.new()
	keybind_btn.text = "更改按鍵"
	keybind_btn.add_theme_font_size_override("font_size", 9)
	keybind_btn.pressed.connect(_open_keybind_menu)
	vbox.add_child(keybind_btn)

	var back_btn := Button.new()
	back_btn.text = "返回"
	back_btn.add_theme_font_size_override("font_size", 9)
	back_btn.pressed.connect(func(): closed.emit())
	vbox.add_child(back_btn)

func _on_outline_toggled(toggled_on: bool) -> void:
	Game.config_enable_status_outline = toggled_on
	Game.save_settings()
	Game.settings_changed.emit()

func _on_shake_toggled(toggled_on: bool) -> void:
	Game.config_enable_screen_shake = not toggled_on   # 反接，見上方勾選框註解
	Game.save_settings()
	Game.settings_changed.emit()

func _open_keybind_menu() -> void:
	if not is_instance_valid(_keybind_menu):
		_keybind_menu = VsKeybindMenu.new()
		_keybind_menu.closed.connect(func():
			_keybind_menu.queue_free()
		)
		add_child(_keybind_menu)
