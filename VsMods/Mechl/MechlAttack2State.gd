class_name MechlAttack2State
extends VsPlayerState

# ==========================================
# 🏃‍♂️ 絞肉機突進 (機鎧普攻第二段)
# ==========================================
@export_group("⚙️ 技能參數")
@export var dash_speed: float = 85.0      # 突進速度
@export var dash_duration: float = 1      # 狂奔持續時間
@export var multi_hit_interval: float = 0.1 # 每 0.1 秒打擊一次

@export_group("🎯 判定框綁定")
@export var multi_hitbox_path: NodePath    # 連打用的判定框
@export var final_hitbox_path: NodePath    # 最後一擊把人打飛的判定框

var is_dashing: bool = false

func can_cast() -> bool:
	return true

func enter() -> void:
	is_dashing = true
	
	# 🌟 核心 1：關閉肉體碰撞，變成無情穿透機器！
	player.set_pass_through(true)
	player.animation.play("running")
	
	var facing_dir = player.get_node("Graphics").scale.x
	player.velocity.x = facing_dir * dash_speed
	
	# ==========================================
	# 🔥 納刀強化系統連動 (大腦注入)
	# ==========================================
	var mh = get_node_or_null(multi_hitbox_path) as VsHitbox
	var fh = get_node_or_null(final_hitbox_path) as VsHitbox
	
	# 🚨 神級防呆：如果找不到，直接在終端機瘋狂洗畫面警告你！
	if mh == null: print("❌ 慘了！找不到連打框！你是不是又綁定到 CollisionShape2D 了？")
	if fh == null: print("❌ 慘了！找不到最後一擊框！請去 Inspector 重新綁定！")
	
	if player.has_method("buff_hitbox"):
		# 🌟 已經幫你把基礎傷害全部改成 12.0！
		if mh: player.buff_hitbox(mh, 12.0)
		if fh: player.buff_hitbox(fh, 12.0)
		
		
	_execute_meat_grinder(mh, fh)

# ==========================================
# 🎬 絞肉機導演排程 (純代碼控制連擊)
# ==========================================
func _execute_meat_grinder(mh: VsHitbox, fh: VsHitbox) -> void:
	_set_hitbox_active(mh, true)
	
	var loops = int(dash_duration / multi_hit_interval)
	
	for i in range(loops):
		await get_tree().create_timer(multi_hit_interval, false, false, true).timeout
		if state_machine.current_state != self: return 
		if mh: mh.hit_targets.clear()

	_set_hitbox_active(mh, false) 
	
	is_dashing = false
	player.velocity.x = 0.0 
	player.animation.play("running") 
	
	if fh:
		fh.causes_down = true
		fh.air_knockback = Vector2(200, -200) 
		fh.ground_knockback = Vector2(200, -200)
		_set_hitbox_active(fh, true) 
		
	await get_tree().create_timer(0.3, false, false, true).timeout
	if state_machine.current_state != self: return
	
	_set_hitbox_active(fh, false)
	state_machine.change_state(state_machine.idle_state)

# ==========================================
# 🛠️ 神級輔助：強制切換 Hitbox 與實體碰撞形狀
# ==========================================
func _set_hitbox_active(hitbox: VsHitbox, active: bool) -> void:
	if hitbox == null: return
	
	hitbox.set_deferred("monitoring", active)
	
	for child in hitbox.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", not active)

func exit() -> void:
	player.set_pass_through(false)
	
	var mh = get_node_or_null(multi_hitbox_path) as VsHitbox
	var fh = get_node_or_null(final_hitbox_path) as VsHitbox
	_set_hitbox_active(mh, false)
	_set_hitbox_active(fh, false)
	
	if player.has_method("deactivate_all_hitboxes"):
		player.deactivate_all_hitboxes()
