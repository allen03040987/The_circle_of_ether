extends Control # 遊戲結束UI

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void: # 隱藏介面
	hide() 
	set_process_input(false)


func _input(event: InputEvent) -> void:
	if animation_player.is_playing():
		return

	if event.is_pressed() and not event.is_echo():
		if (
			event is InputEventKey or 
			event is InputEventMouseButton or
			event is InputEventJoypadButton
		):
			# 🔧 移除了重複觸發的 reload_current_scene()，只留下正規的存讀檔路徑，
			# 避免跟 Game.load_game()/back_to_title() 的場景切換互搶。
			if Game.has_save():
				Game.load_game()
			else:
				Game.back_to_title()
			
func show_game_over() -> void: # 啟用介面
	show() 
	set_process_input(true)
	animation_player.play("enter")
