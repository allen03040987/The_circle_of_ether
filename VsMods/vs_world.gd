extends Node2D

@onready var spawn_point_p1 = $SpawnPoint_P1 
@onready var spawn_point_p2 = $SpawnPoint_P2 

var p1: VsPlayer
var p2: VsPlayer
var is_game_over: bool = false # 防止重複觸發結算

func _ready():
	# 遊戲一開始，立刻呼叫生角色的函數！
	_spawn_fighters()

# ==========================================
# 🛑 裁判監視系統 (純單機版：直接判定生死)
# ==========================================
func _process(_delta: float) -> void:
	if is_game_over or p1 == null or p2 == null:
		return
		
	# 檢查雙方血量
	if p1.current_hp <= 0 and p2.current_hp <= 0:
		_trigger_game_over("Double K.O. ! 雙方平手！")
	elif p1.current_hp <= 0:
		_trigger_game_over("Player 2 Wins !")
	elif p2.current_hp <= 0:
		_trigger_game_over("Player 1 Wins !")

# ==========================================
# 🏆 遊戲結算與轉場 (純單機版：直接執行)
# ==========================================
func _trigger_game_over(winner_text: String) -> void:
	is_game_over = true 
	print("🏆 遊戲結束：", winner_text)
	
	# 1. 剝奪雙方控制權，變成沙包
	p1.is_dummy = true
	p2.is_dummy = true
	
	# 2. 🌟 神級 UI 魔法：程式動態生成「超級大字報」！
	var canvas = CanvasLayer.new()
	canvas.layer = 120 
	add_child(canvas)
	
	var label = Label.new()
	label.text = winner_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# 設定超狂的字體樣式 (黃字黑邊)
	label.add_theme_font_size_override("font_size", 100)
	label.add_theme_color_override("font_color", Color.YELLOW)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 20)
	
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(label)
	
	# 3. ⏳ 等待 3 秒鐘讓玩家截圖歡呼，然後回到選角畫面！
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://VsMods/select.tscn")

# ==========================================
# 🥋 選手生成器 (純單機版：拔除防斷線魔法)
# ==========================================
func _spawn_fighters() -> void:
	# ==========================================
	# 🔴 1. 生成 P1 
	# ==========================================
	var p1_scene = load(VsGameManager.p1_character)
	var p1_instance = p1_scene.instantiate() as VsPlayer
	
	p1_instance.name = "Player1"
	p1_instance.player_id = 1
	p1_instance.global_position = spawn_point_p1.global_position
	add_child(p1_instance)
	
	p1 = p1_instance
	
	# 裝填 P1 自選技能
	var p1_fsm = p1_instance.get_node("VsStateMachine")
	if VsGameManager.p1_custom_skill != "":
		var skill_scene = load(VsGameManager.p1_custom_skill)
		var skill_node = skill_scene.instantiate()
		skill_node.name = "CustomState" 
		p1_fsm.add_child(skill_node)    
		p1_fsm.custom_state = skill_node

	# ==========================================
	# 🔵 2. 生成 P2 
	# ==========================================
	var p2_scene = load(VsGameManager.p2_character)
	var p2_instance = p2_scene.instantiate() as VsPlayer
	
	p2_instance.name = "Player2"
	p2_instance.player_id = 2
	p2_instance.global_position = spawn_point_p2.global_position

	# 同角色互打 (Mirror Match) 異色版處理
	if VsGameManager.p1_character == VsGameManager.p2_character:
		p2_instance.get_node("Graphics").modulate = Color(1, 0.5, 0.5)
		
	# 讓 P2 一出生就強制面朝左邊
	p2_instance.get_node("Graphics").scale.x = -1.0 
	add_child(p2_instance)
	
	p2 = p2_instance
	
	# 裝填 P2 自選技能
	var p2_fsm = p2_instance.get_node("VsStateMachine")
	if VsGameManager.p2_custom_skill != "":
		var skill_scene = load(VsGameManager.p2_custom_skill)
		var skill_node = skill_scene.instantiate()
		skill_node.name = "CustomState" 
		p2_fsm.add_child(skill_node)   
		p2_fsm.custom_state = skill_node

	# ==========================================
	# 🤝 3. 互相綁定宿敵 
	# ==========================================
	p1_instance.opponent = p2_instance
	p2_instance.opponent = p1_instance

	# ==========================================
	# 🎥 4. 綁定 HUD、攝影機 與 插入專屬 UI 卡帶！
	# ==========================================
	
	# 🌟 找回失蹤的攝影機綁定！
	if has_node("Camera2D"):
		$Camera2D.target_p1 = p1_instance
		$Camera2D.target_p2 = p2_instance

	# 🌟 綁定 HUD 與插入卡帶
	if has_node("BattleHUD"):
		var hud = $BattleHUD
		hud.player_1 = p1_instance
		hud.player_2 = p2_instance
		
		# 插入 P1 的專屬 UI
		if p1_instance.custom_ui_scene != null:
			var p1_ui = p1_instance.custom_ui_scene.instantiate()
			hud.p1_custom_ui_anchor.add_child(p1_ui)
			if "player" in p1_ui: p1_ui.player = p1_instance
			
		# 插入 P2 的專屬 UI
		if p2_instance.custom_ui_scene != null:
			var p2_ui = p2_instance.custom_ui_scene.instantiate()
			hud.p2_custom_ui_anchor.add_child(p2_ui)
			if "player" in p2_ui: p2_ui.player = p2_instance
