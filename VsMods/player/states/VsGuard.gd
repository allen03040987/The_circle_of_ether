class_name VsGuard
extends VsPlayerState
## 防禦狀態（長按防禦鍵持續）
## 持續期間獲得強霸體（50% 減傷 + 免疫非強破霸的擊退/硬直）。
## 強破霸攻擊直接破防 → 完整傷害 + 擊退 + 硬直。
##
## 動畫兩階段：按住期間循環播 "defense"；放開後播一次性後搖 "defense_2"，
## 播完才真正離開狀態（elapsed/_anim_length 收尾寫法跟 VsSkill 同一套）。
## 後搖期間無霸體：`is_blocking()` 只在按住階段回傳 true，`VsPlayer.get_armor_tier()`
## 跟 `_on_hurtbox_hurt()` 都靠這個判斷——後搖被打會直接照一般 ArmorTier.NONE
## 流程走（正常受傷+硬直/擊飛，可能因此被打斷離開這個狀態），不再享有格擋保護。

var _releasing:  bool  = false
var elapsed:      float = 0.0
var _anim_length: float = 0.0

func enter(_prev: StringName) -> void:
	_releasing = false
	elapsed    = 0.0
	(player as VsPlayer).anim_player.play("defense")

func sync_anim() -> void:
	var vs := player as VsPlayer
	if _releasing:
		vs.anim_player.play("defense_2")
		vs.anim_player.seek(elapsed, true)
	else:
		vs.anim_player.play("defense")

func physics_update(delta: float, input: InputState) -> StringName:
	# 防禦期間原地不動（規則：原地無法移動——直接歸零，不滑行）
	player.velocity.x = 0.0
	if not _grounded():
		_apply_gravity(delta)
	# 衝刺可打斷防禦（優先級高，按住/後搖兩階段都適用）
	if input.dodge:
		var vs := player as VsPlayer
		if vs.use_dash_energy(30.0):
			return &"vsdodge"

	if _releasing:
		elapsed += delta
		if elapsed >= _anim_length:
			return _recovery_transition(input)   # 支援跑步預輸入
		return &""

	if not input.guard:
		_releasing = true
		elapsed    = 0.0
		var vs := player as VsPlayer
		vs.anim_player.play("defense_2")
		_anim_length = vs.anim_player.get_animation("defense_2").length
	return &""

func save_state() -> Dictionary:
	return {
		"rel": _releasing,
		"el":  elapsed,
	}

func restore_state(d: Dictionary) -> void:
	_releasing = d.get("rel", false)
	elapsed    = d.get("el",  0.0)
	var vs := player as VsPlayer
	if is_instance_valid(vs) and _releasing:
		_anim_length = vs.anim_player.get_animation("defense_2").length

## 是否仍在「按住防禦」階段（有霸體）。後搖（defense_2）期間回傳 false——
## VsPlayer.get_armor_tier()／_on_hurtbox_hurt() 都靠這個決定要不要給格擋保護。
func is_blocking() -> bool:
	return not _releasing

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
