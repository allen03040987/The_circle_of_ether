extends Interactable # 存檔點

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func interact() -> void:
	super()
	
	animation_player.play("activated")
	
	Game.player_stats.health = Game.player_stats.max_health # 恢復
	Game.player_stats.energy = Game.player_stats.max_energy

	if is_instance_valid(interacting_player) and is_instance_valid(interacting_player.health_item):
		interacting_player.health_item.refill() # 血包跟血量/能量一樣，摸到存檔點就補滿

	Game.save_game() # 存檔
