class_name VsKeybindMenu
extends Control
## VsMods 專屬按鍵設定選單（P1/P2）。跟主遊戲 ui/KeybindMenu.gd 是同一套機制
## （InputMap 動態綁定 + ConfigFile 持久化，共用同一個 user://keybindings.cfg
## 檔案跟 "Controls" section——動作清單不同，鍵值用 action_name 當 key 不會撞），
## 刻意不共用同一支腳本／場景，避免改動風險外溢到主遊戲設定選單。全程式碼
## 建立節點，比照 VsMods 其他 UI（BattleHud 等）的慣例。
##
## ⚠ 這份清單要跟 globals/game.gd::_load_custom_keybindings_at_launch() 的
## actions 陣列保持同步——那邊負責開機時把這裡存的自訂鍵重新套用回 InputMap，
## 這裡新增/刪除動作要記得回去同步改。

signal closed

## art_1/art_2/art_3/martial_modifier 跟主遊戲單人模式共用同一組 InputMap
## 動作（P1 武藝鍵），改這裡也會影響單人模式，反之亦然——這是共用輸入的
## 既有事實，不是 bug，UI 文字上直接標明避免使用者疑惑。
const ACTIONS_P1: Dictionary = {
	"p1_left": "P1 左移",
	"p1_right": "P1 右移",
	"p1_jump": "P1 跳躍",
	"p1_down": "P1 蹲下",
	"p1_attack": "P1 普攻",
	"p1_skill": "P1 技能",
	"p1_big_dash": "P1 閃避",
	"p1_small_dash": "P1 防禦",
	"martial_modifier": "P1 武藝修飾鍵（與單人模式共用）",
	"art_1": "P1 武藝一（與單人模式共用）",
	"art_2": "P1 武藝二（與單人模式共用）",
	"art_3": "P1 武藝三（與單人模式共用）",
}
const ACTIONS_P2: Dictionary = {
	"p2_left": "P2 左移",
	"p2_right": "P2 右移",
	"p2_jump": "P2 跳躍",
	"p2_down": "P2 蹲下",
	"p2_attack": "P2 普攻",
	"p2_skill": "P2 技能",
	"p2_special": "P2 武藝一",
	"p2_ultimate": "P2 武藝二",
	"p2_custom": "P2 武藝三",
	"p2_big_dash": "P2 閃避",
	"p2_small_dash": "P2 防禦",
}

const SAVE_PATH := "user://keybindings.cfg"
const VIEW_W := 384
const VIEW_H := 216
const PW := 320
const PH := 190

var _action_list: VBoxContainer
## action_name -> {"key": Button, "mouse": Button}，供即時刷新/還原預設用
var _buttons: Dictionary = {}

var current_listening_action: String = ""
var current_listening_type:   String = ""
var listening_button: Button = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process_input(false)
	_build_ui()
	load_keybindings()

## Esc 關閉整個按鍵選單——只在「沒有正在監聽新按鍵」時處理，正在監聽時
## ui_cancel 已經被 _input()（只在監聽期間靠 set_process_input(true) 啟用）
## 攔下並呼叫 set_input_as_handled()，這裡收不到那個事件，效果是「取消這格
## 監聽」而不是「關掉整個選單」，兩層各自處理不會互相搶。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color        = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2((VIEW_W - PW) / 2.0, (VIEW_H - PH) / 2.0)
	panel.size     = Vector2(PW, PH)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text                 = "按鍵設定"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PW - 8, PH - 44)
	vbox.add_child(scroll)

	_action_list = VBoxContainer.new()
	_action_list.add_theme_constant_override("separation", 2)
	_action_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_action_list)

	_add_section_label("P1")
	for action_name in ACTIONS_P1:
		_add_action_row(action_name, ACTIONS_P1[action_name])
	_add_section_label("P2")
	for action_name in ACTIONS_P2:
		_add_action_row(action_name, ACTIONS_P2[action_name])

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var reset_btn := Button.new()
	reset_btn.text = "還原預設"
	reset_btn.add_theme_font_size_override("font_size", 9)
	reset_btn.pressed.connect(_on_reset_pressed)
	btn_row.add_child(reset_btn)

	var back_btn := Button.new()
	back_btn.text = "返回"
	back_btn.add_theme_font_size_override("font_size", 9)
	back_btn.pressed.connect(func(): closed.emit())
	btn_row.add_child(back_btn)

func _add_section_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_action_list.add_child(lbl)

func _add_action_row(action_name: String, display_name: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 20

	var label := Label.new()
	label.text                = display_name
	label.custom_minimum_size.x = 170
	label.add_theme_font_size_override("font_size", 9)
	row.add_child(label)

	var key_button := Button.new()
	key_button.custom_minimum_size.x = 65
	key_button.add_theme_font_size_override("font_size", 9)
	key_button.text = _get_action_type_text(action_name, "key")
	key_button.pressed.connect(_on_bind_clicked.bind(action_name, "key", key_button))
	row.add_child(key_button)

	var mouse_button := Button.new()
	mouse_button.custom_minimum_size.x = 65
	mouse_button.add_theme_font_size_override("font_size", 9)
	mouse_button.text = _get_action_type_text(action_name, "mouse")
	mouse_button.pressed.connect(_on_bind_clicked.bind(action_name, "mouse", mouse_button))
	row.add_child(mouse_button)

	_action_list.add_child(row)
	_buttons[action_name] = {"key": key_button, "mouse": mouse_button}

func _get_action_type_text(action_name: String, type: String) -> String:
	for event in InputMap.action_get_events(action_name):
		if type == "key" and event is InputEventKey:
			return event.as_text()
		elif type == "mouse" and event is InputEventMouseButton:
			return event.as_text()
	return "[ 未綁定 ]"

func _on_bind_clicked(action_name: String, type: String, button: Button) -> void:
	if current_listening_action != "" and is_instance_valid(listening_button):
		listening_button.text = _get_action_type_text(current_listening_action, current_listening_type)
	current_listening_action = action_name
	current_listening_type   = type
	listening_button = button
	button.text = "[ 請按下鍵盤... ]" if type == "key" else "[ 請點擊滑鼠... ]"
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if current_listening_action == "": return

	if event is InputEventKey and event.is_pressed() and (event.keycode == KEY_BACKSPACE or event.keycode == KEY_DELETE):
		get_viewport().set_input_as_handled()
		_clear_current_binding()
		return

	var is_keyboard_match := current_listening_type == "key" and event is InputEventKey and event.is_pressed() and not event.is_echo()
	var is_mouse_match := current_listening_type == "mouse" and event is InputEventMouseButton and event.is_pressed()
	if not (is_keyboard_match or is_mouse_match): return

	if event.is_action("ui_cancel"):
		get_viewport().set_input_as_handled()
		_end_listening()
		return

	get_viewport().set_input_as_handled()

	var clean_event: InputEvent = null
	if event is InputEventKey:
		var k := InputEventKey.new()
		k.keycode          = event.keycode
		k.physical_keycode = event.physical_keycode
		clean_event = k
	elif event is InputEventMouseButton:
		var m := InputEventMouseButton.new()
		m.button_index = event.button_index
		clean_event = m

	if clean_event:
		var remaining: Array = []
		for existing in InputMap.action_get_events(current_listening_action):
			if current_listening_type == "key" and not (existing is InputEventKey):
				remaining.append(existing)
			elif current_listening_type == "mouse" and not (existing is InputEventMouseButton):
				remaining.append(existing)
		InputMap.action_erase_events(current_listening_action)
		for re in remaining:
			InputMap.action_add_event(current_listening_action, re)
		InputMap.action_add_event(current_listening_action, clean_event)
		_save_keybinding(current_listening_action, current_listening_type, clean_event)

	_end_listening()

func _clear_current_binding() -> void:
	var remaining: Array = []
	for existing in InputMap.action_get_events(current_listening_action):
		if current_listening_type == "key" and not (existing is InputEventKey):
			remaining.append(existing)
		elif current_listening_type == "mouse" and not (existing is InputEventMouseButton):
			remaining.append(existing)
	InputMap.action_erase_events(current_listening_action)
	for re in remaining:
		InputMap.action_add_event(current_listening_action, re)
	_save_keybinding(current_listening_action, current_listening_type, null)
	_end_listening()

func _end_listening() -> void:
	if is_instance_valid(listening_button):
		listening_button.text = _get_action_type_text(current_listening_action, current_listening_type)
	current_listening_action = ""
	current_listening_type   = ""
	listening_button = null
	set_process_input(false)

func _save_keybinding(action_name: String, type: String, event: InputEvent) -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	var save_key := action_name + "_" + type
	if event == null:
		if config.has_section_key("Controls", save_key):
			config.erase_section_key("Controls", save_key)
	elif event is InputEventKey:
		config.set_value("Controls", save_key, {"type": "key", "keycode": event.keycode, "physical_keycode": event.physical_keycode})
	elif event is InputEventMouseButton:
		config.set_value("Controls", save_key, {"type": "mouse", "button_index": event.button_index})
	config.save(SAVE_PATH)

func load_keybindings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK: return
	for action_name in ACTIONS_P1.keys() + ACTIONS_P2.keys():
		var has_key   := config.has_section_key("Controls", action_name + "_key")
		var has_mouse := config.has_section_key("Controls", action_name + "_mouse")
		if not (has_key or has_mouse): continue
		InputMap.action_erase_events(action_name)
		if has_key:
			var k_data = config.get_value("Controls", action_name + "_key")
			var k := InputEventKey.new()
			k.keycode          = k_data.get("keycode", 0)
			k.physical_keycode = k_data.get("physical_keycode", 0)
			InputMap.action_add_event(action_name, k)
		if has_mouse:
			var m_data = config.get_value("Controls", action_name + "_mouse")
			var m := InputEventMouseButton.new()
			m.button_index = m_data.get("button_index", 0)
			InputMap.action_add_event(action_name, m)

## 只清 VsMods 這份清單涉及的動作，不動主遊戲自己的按鍵——跟主遊戲
## KeybindMenu._on_reset_button_pressed() 整檔案砍掉不同，那樣做會連主遊戲
## 已經自訂好的按鍵一起清掉，超出使用者按下「還原預設」時預期的範圍。
func _on_reset_pressed() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		for action_name in ACTIONS_P1.keys() + ACTIONS_P2.keys():
			# erase_section_key() 對不存在的 key 會噴 error（不是靜默 no-op），
			# 大部分動作原本就沒被自訂過，不先檢查會洗一整排「key 不存在」的
			# 錯誤訊息——實測按一次「還原預設」就噴了二十幾條，純噪音
			if config.has_section_key("Controls", action_name + "_key"):
				config.erase_section_key("Controls", action_name + "_key")
			if config.has_section_key("Controls", action_name + "_mouse"):
				config.erase_section_key("Controls", action_name + "_mouse")
		config.save(SAVE_PATH)

	# InputMap.load_from_project_settings() 會把「所有」動作（含主遊戲的）都
	# 蓋回專案預設，所以要接著重新套用主遊戲那份自訂設定，不能就這樣放著
	InputMap.load_from_project_settings()
	Game._load_custom_keybindings_at_launch()

	for action_name in _buttons:
		_buttons[action_name]["key"].text   = _get_action_type_text(action_name, "key")
		_buttons[action_name]["mouse"].text = _get_action_type_text(action_name, "mouse")
