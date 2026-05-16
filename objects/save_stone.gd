extends Interactable # 存檔點

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func interact() -> void:
	super()
	
	animation_player.play("activated")
	
	Game.player_stats.health = Game.player_stats.max_health # 恢復
	Game.player_stats.energy = Game.player_stats.max_energy
	Game.save_game() # 存檔
