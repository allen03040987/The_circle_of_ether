class_name Art_Naihe_4
extends VsMartialArt
## 移植自奈何橋 Boss 的 dash_back——單純後撤，使用者明確表示甚至不用判定框。
## 後撤動能完全靠 `art_4` 動畫軌道上的 3 個 strike_impulse Call Method key
## 驅動（數值照抄 Boss 原始動畫：-500/-100/0.0 @ t=0.1/0.3/0.55），這支腳本
## 本身跟其他三招同一套模板，沒有任何後撤專屬的程式碼。

const IMPULSE_FRICTION: float = 8750.0

func _init() -> void:
	art_name       = "武藝四"
	energy_cost    = 20.0
	can_use_in_air = false

var _anim_length: float = 0.0

func enter(_prev: StringName) -> void:
	super.enter(_prev)
	var vs := player as VsPlayer
	player.velocity.x = 0.0
	vs.anim_player.play("art_4")
	_anim_length = vs.anim_player.get_animation("art_4").length
	vs.mark_in_combat()

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"
	player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * delta)

	if elapsed >= _anim_length:
		return _recovery_transition(input)
	return &""

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("art_4")
	vs.anim_player.seek(elapsed, true)
