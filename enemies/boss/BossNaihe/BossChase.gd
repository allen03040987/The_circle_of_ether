class_name BossChaseState
extends BossState

@export var chase_speed: float = 120.0
@export var attack_range: float = 85.0 # 進入這個範圍直接出刀

# 拿掉耐心系統，因為動作遊戲的 Boss 不應該半途而廢

func enter() -> void:
	if boss.animation_player.has_animation("walk"):
		boss.play_safe_anim("walk")
	
func physics_update(delta: float) -> void:
	boss.velocity.y += boss.default_gravity * delta
	
	if not is_instance_valid(boss.player_target):
		boss.velocity.x = move_toward(boss.velocity.x, 0.0, boss.acceleration * delta)
		boss.custom_move_and_slide()
		return

	# 死死盯著玩家
	boss.face_player()
	var dist = boss.global_position.distance_to(boss.player_target.global_position)
	
	# 🌟 核心優化：範圍判定與無縫出刀
	if dist > attack_range:
		# 狂奔逼近玩家
		boss.velocity.x = move_toward(boss.velocity.x, boss.direction * chase_speed, boss.acceleration * delta)
	else:
		# 進入攻擊範圍！瞬間煞車並切換到近戰狀態！不需要經過 Decision！
		boss.velocity.x = 0.0
		state_machine.transition_to("MeleeAttack") 
		
	boss.custom_move_and_slide()
