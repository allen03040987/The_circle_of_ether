extends Panel

signal menu_closed # 🌟 宣告一個信號，用來告訴暫停選單「我關閉了」

# ==========================================
# 🎒 裝備介面專用變數
# ==========================================
@onready var status_label: Label = $StatusLabel
@onready var apply_button: Button = $ApplyButton

@onready var weapon_opt_1: OptionButton = $HBoxContainer/WeaponSlot1/WeaponOpt
@onready var weapon_opt_2: OptionButton = $HBoxContainer/WeaponSlot2/WeaponOpt

@onready var slot1_arts: Array[OptionButton] = [
	$HBoxContainer/WeaponSlot1/ArtOpt1,
	$HBoxContainer/WeaponSlot1/ArtOpt2,
	$HBoxContainer/WeaponSlot1/ArtOpt3
]

@onready var slot2_arts: Array[OptionButton] = [
	$HBoxContainer/WeaponSlot2/ArtOpt1,
	$HBoxContainer/WeaponSlot2/ArtOpt2,
	$HBoxContainer/WeaponSlot2/ArtOpt3
]

@onready var back_button: Button = $BackButton

# ==========================================
# 🥋 武器與武藝資料庫 (DB)
# ==========================================
const AVAILABLE_WEAPONS = [
	{"id": "katana", "name": "太刀 (Katana)"},
	{"id": "spear", "name": "長槍 (Spear)"},
	{"id": "talisman", "name": "靈符 (Talisman)"},
	{"id": "sickle", "name": "鎖鐮 (Sickle)"}
]

const AVAILABLE_ARTS = {
	"katana": [
		{"name": "挑飛斬 (11)", "path": "res://player/MartialArts/Katana/Art_Katana_11.gd"},
		{"name": "升龍螺旋 (12)", "path": "res://player/MartialArts/Katana/Art_Katana_12.gd"},
		{"name": "裂地連斬·壹 (20)", "path": "res://player/MartialArts/Katana/Art_Katana_20.gd"},
		{"name": "裂地連斬·貳 (21)", "path": "res://player/MartialArts/Katana/Art_Katana_21.gd"},
		{"name": "斷空劍氣 (22)", "path": "res://player/MartialArts/Katana/Art_Katana_22.gd"}
	],
	"spear": [
		{"name": "向上挑飛 (22)", "path": "res://player/MartialArts/Spear/Art_Spear_22.gd"},
		{"name": "大範圍聚怪 (21)", "path": "res://player/MartialArts/Spear/Art_Spear_21.gd"}
	],
	"talisman": [
		{"name": "靈能護身塔 (20)", "path": "res://player/MartialArts/Talisman/Art_Talisman_20.gd"},
		{"name": "逐風符·昇 (30)", "path": "res://player/MartialArts/Talisman/Art_Talisman_30.gd"},
		{"name": "馭雷符·降 (31)", "path": "res://player/MartialArts/Talisman/Art_Talisman_31.gd"}
	],
	"sickle": []
}

var selected_weapons: Array[String] = ["katana", "spear"]
var selected_arts: Dictionary = {
	"katana": ["", "", ""], "spear": ["", "", ""], 
	"talisman": ["", "", ""], "sickle": ["", "", ""]
}

func _ready() -> void:
	if is_instance_valid(weapon_opt_1):
		_setup_ui_styles()
		_populate_weapon_dropdowns()
		
		weapon_opt_1.item_selected.connect(_on_weapon_selected.bind(0))
		weapon_opt_2.item_selected.connect(_on_weapon_selected.bind(1))
		
		for i in range(3):
			slot1_arts[i].item_selected.connect(_on_art_selected.bind(0, i))
			slot2_arts[i].item_selected.connect(_on_art_selected.bind(1, i))
			
		apply_button.pressed.connect(_on_apply_loadout_pressed)
	
	if is_instance_valid(back_button) and not back_button.pressed.is_connected(close_menu):
		back_button.pressed.connect(close_menu)
		
# 🌟 提供給外部（如 PauseMenu）呼叫的開啓介面
func open_menu(player_node: Node) -> void:
	selected_weapons = player_node.get("equipped_weapon_ids").duplicate()
	if player_node.has_method("get_all_weapons_martial_arts"):
		selected_arts = player_node.call("get_all_weapons_martial_arts").duplicate(true)
	
	_sync_ui_to_data()
	show()

func close_menu() -> void:
	hide()
	menu_closed.emit() # 通知外部介面已關閉

# 攔截返回鍵
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		accept_event() # 阻止事件繼續傳遞給暫停選單
		close_menu()

func _setup_ui_styles() -> void:
	var all_opts = [weapon_opt_1, weapon_opt_2] + slot1_arts + slot2_arts
	for opt in all_opts:
		if is_instance_valid(opt):
			opt.add_theme_font_size_override("font_size", 16) 

func _populate_weapon_dropdowns() -> void:
	weapon_opt_1.clear()
	weapon_opt_2.clear()
	for i in range(AVAILABLE_WEAPONS.size()):
		var w_data = AVAILABLE_WEAPONS[i]
		weapon_opt_1.add_item(w_data["name"])
		weapon_opt_1.set_item_metadata(i, w_data["id"])
		weapon_opt_2.add_item(w_data["name"])
		weapon_opt_2.set_item_metadata(i, w_data["id"])

func _sync_ui_to_data() -> void:
	if selected_weapons.size() < 2: selected_weapons = ["katana", "spear"]
	_set_opt_by_metadata(weapon_opt_1, selected_weapons[0])
	_set_opt_by_metadata(weapon_opt_2, selected_weapons[1])
	_refresh_art_dropdowns(0)
	_refresh_art_dropdowns(1)
	if status_label: status_label.text = "配置你的主副武器與武藝："

func _on_weapon_selected(item_index: int, slot_index: int) -> void:
	var new_weapon_id = AVAILABLE_WEAPONS[item_index]["id"]
	var other_slot = 1 if slot_index == 0 else 0
	if selected_weapons[other_slot] == new_weapon_id:
		selected_weapons[other_slot] = selected_weapons[slot_index]
	selected_weapons[slot_index] = new_weapon_id
	_sync_ui_to_data()

func _on_art_selected(item_index: int, main_slot_index: int, art_slot_index: int) -> void:
	var w_id = selected_weapons[main_slot_index]
	var ui_slots = slot1_arts if main_slot_index == 0 else slot2_arts
	var selected_path = ui_slots[art_slot_index].get_item_metadata(item_index)
	
	if selected_path != "": 
		for i in range(3):
			if i != art_slot_index and selected_arts[w_id][i] == selected_path:
				var old_path = selected_arts[w_id][art_slot_index]
				selected_arts[w_id][i] = old_path
				break 
				
	selected_arts[w_id][art_slot_index] = selected_path
	_refresh_art_dropdowns(main_slot_index)

func _refresh_art_dropdowns(main_slot_index: int) -> void:
	var w_id = selected_weapons[main_slot_index]
	var target_arts_ui = slot1_arts if main_slot_index == 0 else slot2_arts
	var current_chosen_paths = selected_arts[w_id]
	var art_list = AVAILABLE_ARTS.get(w_id, [])
	
	for slot_idx in range(3):
		var opt_btn = target_arts_ui[slot_idx]
		opt_btn.clear()
		opt_btn.add_item("-- 未裝備武藝 --")
		opt_btn.set_item_metadata(0, "")
		
		if art_list.size() == 0:
			opt_btn.disabled = true
			continue
			
		opt_btn.disabled = false
		var saved_path = current_chosen_paths[slot_idx]
		var select_target_id = 0
		
		for i in range(art_list.size()):
			var art_data = art_list[i]
			var item_id = i + 1
			opt_btn.add_item(art_data["name"])
			opt_btn.set_item_metadata(item_id, art_data["path"])
			if art_data["path"] == saved_path: select_target_id = item_id
		opt_btn.selected = select_target_id

func _set_opt_by_metadata(opt: OptionButton, meta_value: String) -> void:
	for i in range(opt.item_count):
		if opt.get_item_metadata(i) == meta_value:
			opt.selected = i
			return

func _on_apply_loadout_pressed() -> void:
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		var p = players[0]
		var current_equipped = p.get("equipped_weapon_ids")
		var current_arts = p.call("get_all_weapons_martial_arts") if p.has_method("get_all_weapons_martial_arts") else {}
		
		if current_equipped == selected_weapons and current_arts == selected_arts:
			print("♻️ [系統] 裝備與武藝皆無更動！")
			close_menu()
			return
			
		if p.has_method("equip_loadout_with_arts"):
			p.call("equip_loadout_with_arts", selected_weapons.duplicate(), selected_arts.duplicate(true))
		else:
			p.equip_loadout(selected_weapons.duplicate())
			
		print("✅ 雙武器與武藝組件同步更新成功！")
		close_menu()
