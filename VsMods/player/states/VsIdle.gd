class_name VsIdle
extends VsPlayerState

func enter(_prev: StringName) -> void:
	# 進場刻意不轉向：enter() 跟上一個狀態的收尾轉場同一幀觸發，這時 AnimationPlayer
	# 是 MANUAL 模式、play("idle") 要等下一幀 advance() 才會真的把畫面換成 idle 姿勢，
	# 但 graphics.scale.x 是每幀無條件套用——若這裡先轉，上一個狀態最後一幀顯示的
	# 畫面會被新朝向鏡像，看起來像「攻擊最後一幀也跟著轉」。轉向只交給 physics_update
	# 每幀判斷，等真正進到 idle（下一幀）才會生效
	(player as VsPlayer).anim_player.play("idle")

func sync_anim() -> void:
	(player as VsPlayer).anim_player.play("idle")

func physics_update(delta: float, input: InputState) -> StringName:
	_apply_gravity(delta)
	_apply_ground_move(delta, input)

	var vs := player as VsPlayer
	# 靜止時持續鎖定面向對手（輔助鎖敵）；一旦有移動輸入，_apply_ground_move
	# 已經照移動方向轉了，不能再被這裡蓋回去
	if input.move_dir == 0.0:
		vs.face_opponent()

	if not _grounded():
		return &"vsfall"

	if input.attack:
		return &"vsattack"
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"
	if input.guard:
		return &"vsguard"
	if input.jump:
		return &"vsjump"
	if input.move_dir != 0.0:
		return &"vsrun"
	return &""
