class_name VsGuard
extends VsPlayerState
## 防禦狀態（長按防禦鍵持續）
## 持續期間獲得強霸體（50% 減傷 + 免疫非強破霸的擊退/硬直）。
## 強破霸攻擊直接破防 → 完整傷害 + 擊退 + 硬直。

func enter(_prev: StringName) -> void:
	# TODO: 換成防禦動畫（目前無對應素材，暫用 idle）
	(player as VsPlayer).anim_player.play("idle")

func sync_anim() -> void:
	(player as VsPlayer).anim_player.play("idle")

func physics_update(delta: float, input: InputState) -> StringName:
	# 防禦期間原地不動（規則：原地無法移動——直接歸零，不滑行）
	player.velocity.x = 0.0
	if not _grounded():
		_apply_gravity(delta)
	# 衝刺可打斷防禦（優先級高）
	if input.dodge:
		var vs := player as VsPlayer
		if vs.use_dash_energy(30.0):
			return &"vsdodge"
	if not input.guard:
		return _recovery_transition(input)   # 支援跑步預輸入
	return &""

## 由 VsPlayer._on_hurtbox_hurt() 在防禦狀態下呼叫
## 體質效果（強霸體）邏輯統一在此處理，不走一般 pending_hit 流程
func on_guard_hit(hitbox: VsHitbox) -> void:
	var vs := player as VsPlayer
	# 擊退方向用攻擊者面向，理由同 VsPlayer._on_hurtbox_hurt
	var dir_x: int = hitbox.owner_player.facing_dir if hitbox.owner_player else -vs.facing_dir

	vs.mark_in_combat()

	if hitbox.break_level == VsHitbox.BreakLevel.STRONG_ARMOR_BREAK:
		# 強破霸 = 破防：完整傷害 + 擊退 + 硬直
		vs.pending_hit = {
			"damage":           hitbox.damage,
			"hitstun_time":     hitbox.hitstun_time,
			"knockback":        Vector2(hitbox.knockback.x * dir_x, hitbox.knockback.y),
			"causes_knockdown": hitbox.causes_knockdown,
		}
		return

	# 強霸體：50% 減傷，免疫擊退/硬直——格擋成功，比照主遊戲 Guard.gd::try_block()
	# 音效組合（hit_2 疊 hit_8）
	vs.hp = maxf(vs.hp - hitbox.damage * 0.5, 0.0)
	vs.vfx_action_sfx("hit_2", 0.0)
	vs.vfx_action_sfx("hit_8", -10.0)
