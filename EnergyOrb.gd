class_name EnergyOrb
extends Area2D

# ==========================================
# 🎛️ 追蹤動力學參數
# ==========================================
var velocity := Vector2.ZERO
var is_homing := false
var homing_speed := 0.0
var max_homing_speed := 1200.0
var homing_acceleration := 2500.0

var target_player: Node2D = null

func _ready() -> void:
	# 1. 抓取玩家 (加入了防呆提示)
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		target_player = players[0]
	else:
		printerr("❌ 錯誤：EnergyOrb 找不到玩家！請確認玩家節點已經加入 'Player' 群組！")
		
	# 2. 噴發時的隨機爆炸初速度 (偏向斜上方炸開)
	var angle = randf_range(PI * 1.0, PI * 2.0)
	var speed = randf_range(200.0, 400.0)
	velocity = Vector2(cos(angle), sin(angle)) * speed
	
	# 3. 綁定碰撞事件
	body_entered.connect(_on_body_entered)
	
	# 4. 🎬 動態時間軸 (縮小到 0.4 倍，避免太大！)
	scale = Vector2.ZERO
	var tween = create_tween()
	# 🌟 如果你的圖還是太大，就把這裡的 Vector2(0.4, 0.4) 繼續調小！
	tween.tween_property(self, "scale", Vector2(0.06, 0.06), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.1) # 滯空等待
	tween.tween_callback(func(): is_homing = true)

func _physics_process(delta: float) -> void:
	if not is_homing:
		# 剛噴出來的階段：帶有空氣阻力的慣性滑行
		velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
	else:
		# 追蹤階段：加速飛向玩家！
		if is_instance_valid(target_player):
			var target_pos = target_player.global_position + Vector2(0, -20)
			var direction = (target_pos - global_position).normalized()
			
			homing_speed = move_toward(homing_speed, max_homing_speed, homing_acceleration * delta)
			velocity = direction * homing_speed
			
	global_position += velocity * delta

func _on_body_entered(body: Node2D) -> void:
	# 🌟 改用 is_in_group 判斷，這是最穩定的作法
	if body.is_in_group("Player"):
		if body.has_method("add_energy"):
			body.add_energy(1)
			
		if CombatManager.has_method("apply_camera_shake"):
			CombatManager.apply_camera_shake(1.0)
			
		queue_free()
