class_name BossChaseState
extends BossState

@export var chase_speed: float = 120.0
@export var attack_range: float = 85.0 # 進入這個範圍直接出刀

# 拿掉耐心系統，因為動作遊戲的 Boss 不應該半途而廢

func enter() -> void:
	if boss.animation_player.has_animation("walk"):
		boss.play_safe_anim("walk")
	
func physics_update(delta: float) -> void:
	if not is_instance_valid(boss.player_target):
		boss.velocity.y += boss.default_gravity * delta
		boss.velocity.x = move_toward(boss.velocity.x, 0.0, boss.acceleration * delta)
		boss.custom_move_and_slide()
		return

	# 死死盯著玩家
	boss.face_player()
	# 🔧 只看水平距離：如果跟玩家有高低差，直線距離會被 Y 軸拉大，導致永遠貼近不到 attack_range
	var dist = absf(boss.player_target.global_position.x - boss.global_position.x)

	# 🌟 核心優化：範圍判定與無縫出刀
	if dist > attack_range:
		# 狂奔逼近玩家：跟 Slime 共用 Enemy.gd 的 move()，不再手刷一份一模一樣的邏輯
		boss.move(chase_speed, delta)
	else:
		# 進入攻擊範圍！瞬間煞車並切換到近戰狀態！不需要經過 Decision！
		boss.velocity.y += boss.default_gravity * delta
		boss.velocity.x = 0.0
		# 🔧 明確指定招式：避免 next_melee 殘留 RetreatAttack 專屬的 "A4"，導致 MeleeAttack 啞火站定原地
		boss.set_meta("next_melee", "A1")
		state_machine.transition_to("MeleeAttack")
		boss.custom_move_and_slide()
