class_name VsGuard
extends VsPlayerState
## 防禦狀態（長按防禦鍵持續）
## 一般受擊只承受碎片傷害；guard_break 攻擊直接破防轉 VsHurt

const CHIP_RATIO: float = 0.15  # 防禦成功時承受的傷害比例

func enter(_prev: StringName) -> void:
	# TODO: 換成防禦動畫（目前無對應素材，暫用 idle）
	(player as VsPlayer).anim_player.play("idle")

func physics_update(delta: float, input: InputState) -> StringName:
	player.velocity.x = move_toward(player.velocity.x, 0.0, FRICTION * delta)
	if not player.is_on_floor():
		_apply_gravity(delta)
	# 閃避優先級高於防禦
	if input.dodge:
		var vs := player as VsPlayer
		if vs.use_energy(15.0):
			return &"vsdodge"
	if not input.guard:
		return &"vsidle" if player.is_on_floor() else &"vsfall"
	return &""

## 由 VsPlayer._on_hurtbox_hurt() 在防禦狀態下呼叫
func on_guard_hit(hitbox: VsHitbox) -> void:
	var vs := player as VsPlayer
	var src_pos := hitbox.global_position
	if is_instance_valid(hitbox.owner):
		src_pos = hitbox.owner.global_position
	var dir_x := int(sign(src_pos.x - vs.global_position.x))
	if dir_x == 0: dir_x = -vs.facing_dir

	if hitbox.guard_break:
		# 破防：排隊一次完整受傷（下幀由 VsPlayer._apply_pending_hit 處理）
		vs.pending_hit = {
			"damage": hitbox.damage,
			"hitstun_time": hitbox.hitstun_time,
			"knockback": Vector2(hitbox.knockback.x * dir_x, hitbox.knockback.y),
			"causes_knockdown": hitbox.causes_knockdown,
		}
		return
	# 碎片傷害
	vs.hp = maxf(vs.hp - hitbox.damage * CHIP_RATIO, 0.0)
	# 輕微後退
	vs.velocity.x = -dir_x * 120.0
