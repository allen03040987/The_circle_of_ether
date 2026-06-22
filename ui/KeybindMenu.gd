class_name KeybindMenu
extends Control

signal menu_closed


const ACTIONS = {
	"move_left": "向左移動",
	"move_right": "向右移動",
	"jump": "跳躍",
	"attack": "普通攻擊",
	"heavy_attack": "戰技",
	"martial_modifier": "武技輸入",
	"art_1": "武技一",
	"art_2": "武技二",
	"art_3": "武技三",
	"ultimate": "終結",
	"silde": "閃避衝刺",
	"switch_weapon": "切換武器",
	"interact": "交互",
	
}

const SAVE_PATH = "user://keybindings.cfg"

@onready var action_list: VBoxContainer = $ScrollContainer/ActionList
@onready var back_button: Button = $BackButton
@onready var reset_button: Button = $ResetButton
var current_listening_action: String = ""
var current_listening_type: String = "" # "key" 或 "mouse"
var listening_button: Button = null

func _ready() -> void:
	load_keybindings()
	_create_action_list_ui()
	set_process_input(false) # 🌟 修正：改為關閉頂層 input 監聽
	
	if is_instance_valid(back_button):
		back_button.pressed.connect(func():
			hide()
			menu_closed.emit()
		)
	if is_instance_valid(reset_button):
		reset_button.pressed.connect(_on_reset_button_pressed)

func _create_action_list_ui() -> void:
	for child in action_list.get_children():
		child.queue_free()
		
	for action_name in ACTIONS.keys():
		var row = HBoxContainer.new()
		row.custom_minimum_size.y = 35
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# 1. 左側：動作名稱標籤
		var label = Label.new()
		label.text = ACTIONS[action_name]
		label.custom_minimum_size.x = 110
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 10)
		row.add_child(label)
		
		# 2. 中間：鍵盤綁定按鈕
		var key_button = Button.new()
		key_button.custom_minimum_size.x = 110
		key_button.add_theme_font_size_override("font_size", 10)
		key_button.text = _get_action_type_text(action_name, "key")
		key_button.pressed.connect(_on_bind_clicked.bind(action_name, "key", key_button))
		row.add_child(key_button)
		
		# Spacer 稍微隔開兩個按鈕
		var spacer = Control.new()
		spacer.custom_minimum_size.x = 1
		row.add_child(spacer)
		
		# 3. 右側：滑鼠綁定按鈕
		var mouse_button = Button.new()
		mouse_button.custom_minimum_size.x = 110
		mouse_button.add_theme_font_size_override("font_size", 10)
		mouse_button.text = _get_action_type_text(action_name, "mouse")
		mouse_button.pressed.connect(_on_bind_clicked.bind(action_name, "mouse", mouse_button))
		row.add_child(mouse_button)
		
		action_list.add_child(row)

# 分流過濾：只抓取該動作中屬於「鍵盤」或「滑鼠」的單一事件文字
func _get_action_type_text(action_name: String, type: String) -> String:
	var events = InputMap.action_get_events(action_name)
	for event in events:
		if type == "key" and event is InputEventKey:
			return event.as_text()
		elif type == "mouse" and event is InputEventMouseButton:
			return event.as_text()
	return "[ 未綁定 ]"

func _on_bind_clicked(action_name: String, type: String, button: Button) -> void:
	if current_listening_action != "" and is_instance_valid(listening_button):
		listening_button.text = _get_action_type_text(current_listening_action, current_listening_type)
		
	current_listening_action = action_name
	current_listening_type = type
	listening_button = button
	
	if type == "key":
		button.text = "[ 請按下鍵盤... ]"
	else:
		button.text = "[ 請點擊滑鼠... ]"
		
	set_process_input(true) # 🌟 修正：改為開啓頂層 input 監聽

func _input(event: InputEvent) -> void: 
	if current_listening_action == "": return
	
	# 🌟 新增功能：按下 Delete 或 Backspace 時，清除該槽位的綁定
	if event is InputEventKey and event.is_pressed() and (event.keycode == KEY_BACKSPACE or event.keycode == KEY_DELETE):
		get_viewport().set_input_as_handled()
		_clear_current_binding()
		return
	
	var is_keyboard_match = current_listening_type == "key" and event is InputEventKey and event.is_pressed() and not event.is_echo()
	var is_mouse_match = current_listening_type == "mouse" and event is InputEventMouseButton and event.is_pressed()
	
	if not (is_keyboard_match or is_mouse_match): return
	
	if event.is_action("ui_cancel"):
		get_viewport().set_input_as_handled() 
		_end_listening()
		return
		
	get_viewport().set_input_as_handled() 
	
	var clean_event: InputEvent = null
	if event is InputEventKey:
		var k = InputEventKey.new()
		k.keycode = event.keycode
		k.physical_keycode = event.physical_keycode
		clean_event = k
	elif event is InputEventMouseButton:
		var m = InputEventMouseButton.new()
		m.button_index = event.button_index
		clean_event = m
		
	if clean_event:
		var remaining_events = []
		for existing_event in InputMap.action_get_events(current_listening_action):
			if current_listening_type == "key" and not (existing_event is InputEventKey):
				remaining_events.append(existing_event)
			elif current_listening_type == "mouse" and not (existing_event is InputEventMouseButton):
				remaining_events.append(existing_event)
				
		InputMap.action_erase_events(current_listening_action)
		for re_event in remaining_events:
			InputMap.action_add_event(current_listening_action, re_event)
			
		InputMap.action_add_event(current_listening_action, clean_event)
		save_keybinding(current_listening_action, current_listening_type, clean_event)
	
	_end_listening()
	
# 🌟 新增：清除單一按鍵/滑鼠槽位的綁定
func _clear_current_binding() -> void:
	# 1. 把同類型的舊事件從 InputMap 移除
	var remaining_events = []
	for existing_event in InputMap.action_get_events(current_listening_action):
		if current_listening_type == "key" and not (existing_event is InputEventKey):
			remaining_events.append(existing_event)
		elif current_listening_type == "mouse" and not (existing_event is InputEventMouseButton):
			remaining_events.append(existing_event)
			
	InputMap.action_erase_events(current_listening_action)
	for re_event in remaining_events:
		InputMap.action_add_event(current_listening_action, re_event)
		
	# 2. 將 ConfigFile 裡的該項設定抹除 (傳入 null 代表清除)
	save_keybinding(current_listening_action, current_listening_type, null)
	
	# 3. 關閉監聽並刷新 UI
	_end_listening()

func _end_listening() -> void:
	if is_instance_valid(listening_button):
		listening_button.text = _get_action_type_text(current_listening_action, current_listening_type)
	current_listening_action = ""
	current_listening_type = ""
	listening_button = null
	set_process_input(false)

# ==========================================
# 💾 ConfigFile 獨立槽位儲存
# ==========================================
func save_keybinding(action_name: String, type: String, event: InputEvent) -> void:
	var config = ConfigFile.new()
	config.load(SAVE_PATH)
	
	var save_key = action_name + "_" + type
	
	# 🌟 修改：如果 event 是 null，代表玩家取消綁定，從檔案中刪除該鍵
	if event == null:
		if config.has_section_key("Controls", save_key):
			config.erase_section_key("Controls", save_key)
	elif event is InputEventKey:
		config.set_value("Controls", save_key, {"type": "key", "keycode": event.keycode, "physical_keycode": event.physical_keycode})
	elif event is InputEventMouseButton:
		config.set_value("Controls", save_key, {"type": "mouse", "button_index": event.button_index})
		
	config.save(SAVE_PATH)

func load_keybindings() -> void:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) != OK: return
	
	for action_name in ACTIONS.keys():
		# 每次載入前，將該招式的預設對應完全清空，準備寫入自定義的雙軌資料
		var has_any_custom = config.has_section_key("Controls", action_name + "_key") or config.has_section_key("Controls", action_name + "_mouse")
		if not has_any_custom: continue
		
		InputMap.action_erase_events(action_name)
		
		# 嘗試載入鍵盤
		if config.has_section_key("Controls", action_name + "_key"):
			var k_data = config.get_value("Controls", action_name + "_key")
			var k = InputEventKey.new()
			k.keycode = k_data.get("keycode", 0)
			k.physical_keycode = k_data.get("physical_keycode", 0)
			InputMap.action_add_event(action_name, k)
			
		# 嘗試載入滑鼠
		if config.has_section_key("Controls", action_name + "_mouse"):
			var m_data = config.get_value("Controls", action_name + "_mouse")
			var m = InputEventMouseButton.new()
			m.button_index = m_data.get("button_index", 0)
			InputMap.action_add_event(action_name, m)

# ==========================================
# 🔄 系統重置功能
# ==========================================
func _on_reset_button_pressed() -> void:
	# 1. 刪除本機的儲存檔案
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("keybindings.cfg"):
		dir.remove("keybindings.cfg")
		
	# 2. 強制讓 InputMap 讀取專案設定的預設值
	InputMap.load_from_project_settings()
	
	# 3. 重新生成 UI，畫面瞬間刷新！
	_create_action_list_ui()
	print("🔄 [按鍵系統] 已成功還原為系統預設按鍵。")
