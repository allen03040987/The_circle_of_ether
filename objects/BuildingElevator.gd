class_name BuildingElevator
extends Interactable
## 封閉式大樓電梯 (Cinematic Elevator)
## 負責處理交互、瞬間隱藏玩家、運鏡平移與同場景傳送。

@export_group("電梯設定")
## 連接的目標電梯
@export var destination_path: NodePath
## 鏡頭平移所需時間 (秒)
@export var travel_time: float = 2.0 

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var spawn_point: Marker2D = $SpawnPoint

var _is_operating: bool = false 

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
		
	anim.play("close")

func interact() -> void:
	super()
	
	if _is_operating: return
	
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() == 0: return
	var player = players[0]
	
	# ==========================================
	# 🌟 修正 1：防懸空陷阱！必須雙腳落地才能搭電梯
	# ==========================================
	if not player.is_on_floor():
		return 
		
	var dest_elevator = get_node_or_null(destination_path) as BuildingElevator
	if not dest_elevator:
		print("❌ [電梯] 未設定目標電梯！")
		return
		
	_is_operating = true
	dest_elevator._is_operating = true 
	
	# ==========================================
	# 🎬 階段 1：進電梯 (精準凍結大腦與物理)
	# ==========================================
	player.velocity = Vector2.ZERO
	AudioManager.play_action_sfx("elevator") 
	if player.has_node("AnimationPlayer"):
		player.get_node("AnimationPlayer").play("idle")
	
	player.is_input_locked = true
	
	player.set_physics_process(false)
	if player.get("state_machine"):
		player.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	
	anim.play("open")
	await anim.animation_finished
	
	
	player.hide() 
	
	anim.play("close")
	await anim.animation_finished
	
	# ==========================================
	# 🎥 階段 2：切換臨時相機與平移運鏡
	# ==========================================
	var temp_cam = Camera2D.new()
	get_tree().current_scene.add_child(temp_cam)
	temp_cam.global_position = player.global_position
	temp_cam.make_current() 
	
	player.global_position = dest_elevator.spawn_point.global_position
	
	var travel_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	travel_tween.tween_property(temp_cam, "global_position", dest_elevator.global_position, travel_time)
	await travel_tween.finished
	
	# ==========================================
	# 🎬 階段 3：出電梯 (瞬間出現與喚醒玩家)
	# ==========================================
	AudioManager.play_action_sfx("ding") # 🌟 加在這裡！電梯抵達，叮一聲！
	AudioManager.play_action_sfx("elevator") 
	dest_elevator.anim.play("open")
	await dest_elevator.anim.animation_finished
	
	player.show()
	
	player.is_input_locked = false
	
	# 喚醒物理引擎與狀態機
	player.set_physics_process(true)
	if player.get("state_machine"):
		player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
		
		# ==========================================
		# 🌟 修正 2：治好狀態機的「滑步失憶症」
		# 重新觸發當前狀態的進入邏輯，強迫它檢查玩家是否按著方向鍵，並立刻切換成跑步動畫！
		# ==========================================
		var sm = player.state_machine
		if sm.get("current_state") and sm.current_state.has_method("enter"):
			sm.current_state.enter()
	
	if player.has_node("Camera2D"):
		var p_cam = player.get_node("Camera2D")
		p_cam.make_current()
		p_cam.reset_smoothing()
		p_cam.force_update_scroll()
	
	temp_cam.queue_free()
	
	dest_elevator.anim.play("close")
	
	await dest_elevator.anim.animation_finished
	
	
	
	_is_operating = false
	dest_elevator._is_operating = false
	

