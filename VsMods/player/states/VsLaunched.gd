class_name VsLaunched
extends VsPlayerState
## 擊飛狀態（落地屬性攻擊 + 向上擊退 y<0）
## 規則：直接飛上天所以忽略硬直時間；空中無法操作；
## 落地（y 回到地面）那一刻直接進入倒地（VsKnockdown）。

var elapsed: float = 0.0

func enter(_prev: StringName) -> void:
	elapsed = 0.0
	(player as VsPlayer).anim_player.play("launched")

func physics_update(delta: float, _input: InputState) -> StringName:
	elapsed += delta
	_apply_gravity(delta)
	# 落地判定：擊飛瞬間 velocity.y < 0（還沒離地），必須等下落階段才算落地。
	# 水平動量保留交給 VsKnockdown（彈起+漸增摩擦），不在這裡歸零
	if _grounded() and player.velocity.y >= 0.0:
		return &"vsknockdown"
	return &""

func save_state() -> Dictionary:
	return {"elapsed": elapsed}

func restore_state(d: Dictionary) -> void:
	elapsed = d.get("elapsed", 0.0)

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("launched")
	vs.anim_player.seek(elapsed, true)
