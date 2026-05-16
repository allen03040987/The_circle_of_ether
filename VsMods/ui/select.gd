extends Control

@onready var fight_button: Button = $fight_button
@onready var p_1_char_select: OptionButton = $p1_char_select
@onready var p_2_char_select: OptionButton = $p2_char_select

@onready var p_1_skill_select: OptionButton = $p1_skill_select
@onready var p_2_skill_select: OptionButton = $p2_skill_select


func _ready() -> void:
	# ==========================================
	# 1. 塞入選項 (角色)
	# ==========================================
	p_1_char_select.add_item("刻羅帝 (Clotty)")
	p_1_char_select.add_item("機鎧（Mechl）")
	
	p_2_char_select.add_item("刻羅帝 (Clotty)")
	p_2_char_select.add_item("機鎧（Mechl）")
	
	# ==========================================
	# 2. 塞入選項 (技能)
	# ==========================================
	var skills = [ "通用回血 (Universal Heal)"]
	for skill in skills:
		p_1_skill_select.add_item(skill)
		p_2_skill_select.add_item(skill)
	
	# ==========================================
	# 3. 綁定開戰按鈕 (告別等待，隨時開打！)
	# ==========================================
	fight_button.pressed.connect(_on_fight_pressed)
	fight_button.text = "開戰 (Fight!)"
	
	# 🌟 注意到了嗎？我們把「鎖定 P2 選單」和「網路監聽」的代碼全刪了！
	# 現在 P1 和 P2 都可以直接自由操作下拉選單！


# ==========================================
# ⚔️ 開戰按鈕！
# ==========================================
func _on_fight_pressed() -> void:
	# 🌟 不用再 call RPC 了！直接把畫面上的選項打包送進去！
	start_battle(p_1_char_select.selected, p_2_char_select.selected, p_1_skill_select.selected, p_2_skill_select.selected)


# ==========================================
# 🧠 寫入大腦並跳轉場景 (純單機極速版)
# ==========================================
func start_battle(p1_char_idx: int, p2_char_idx: int, p1_skill_idx: int, p2_skill_idx: int) -> void:
	
	# --- 1. 寫入角色路徑 ---
	match p1_char_idx:
		0: VsGameManager.p1_character = "res://VsMods/Clotty/clotty.tscn"
		1: VsGameManager.p1_character = "res://VsMods/Mechl/Mechl.tscn"
		
	match p2_char_idx:
		0: VsGameManager.p2_character = "res://VsMods/Clotty/clotty.tscn"
		1: VsGameManager.p2_character = "res://VsMods/Mechl/Mechl.tscn"
	
	# --- 2. 寫入技能路徑 ---
	match p1_skill_idx:
		0: VsGameManager.p1_custom_skill = "res://VsMods/skills/universal_skill_heal.tscn"

	match p2_skill_idx:
		0: VsGameManager.p2_custom_skill = "res://VsMods/skills/universal_skill_heal.tscn"
	
	print("🚀 本地雙打配置完畢！進入戰鬥舞台！")
	get_tree().change_scene_to_file("res://VsMods/vs_world.tscn")
