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
			# 🌟 修復循環：如果是測試階段，直接重開場景最乾淨
			# 這樣會重新跑一次 Player 的 _ready，狀態會全部重置
			get_tree().reload_current_scene()
			
			# 如果你想用你的存檔系統，請確保 load_game() 裡面有 reload_current_scene()
			if Game.has_save():
				Game.load_game()
			else:
				Game.back_to_title()
			
func show_game_over() -> void: # 啟用介面
	show() 
	set_process_input(true)
	animation_player.play("enter")
