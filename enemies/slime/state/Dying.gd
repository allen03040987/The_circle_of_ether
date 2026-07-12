extends SlimeState

func enter() -> void:
	slime.animation_player.play("die")

	# 🌟 核心防護：死亡瞬間立刻關閉所有碰撞與判定！防止幽靈攻擊或被鞭屍位移
	slime.hitbox_shape.set_deferred("disabled", true)
	var hurtbox = slime.graphics.get_node_or_null("Hurtbox/CollisionShape2D")
	if hurtbox: hurtbox.set_deferred("disabled", true)

	# 取消物理層
	slime.set_collision_layer_value(1, false)
	slime.set_collision_mask_value(1, false)

func physics_update(delta: float) -> void:
	slime.move(0.0, delta)
