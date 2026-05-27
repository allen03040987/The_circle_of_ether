extends Node
## 全域戰鬥管理器 (Combat Manager)
## Autoload (Singleton) 單例。
## 處理全域卡肉 (Hitstop)、螢幕震動 (Camera Shake) 及各類戰鬥特效與 UI 飄字的統一生成。

# ==========================================
# ⏱️ 頓幀與時停 (Hitstop)
# ==========================================
var _hitstop_end_time: float = 0.0
var _is_hitstopping: bool = false

# ==========================================
# ⚙️ 初始化與設定同步
# ==========================================
func _ready() -> void:
	# 初始化時先對齊一次存檔設定
	_sync_settings()
	
	# 綁定 Game 的全域廣播，只要玩家一改設定，就立刻刷新！
	if not Game.settings_changed.is_connected(_sync_settings):
		Game.settings_changed.connect(_sync_settings)

func _sync_settings() -> void:
	# 將 CombatManager 內部的開關，對齊玩家設定檔
	enable_screen_shake = Game.config_enable_screen_shake
	
func apply_hitstop(duration: float, time_scale: float = 0.05) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	var requested_end_time = current_time + duration
	
	# 處理多重卡肉請求：取最晚的結束時間
	if _is_hitstopping:
		if requested_end_time > _hitstop_end_time:
			_hitstop_end_time = requested_end_time
		return
	
	_is_hitstopping = true
	_hitstop_end_time = requested_end_time
	Engine.time_scale = time_scale
	
	_process_hitstop()

func _process_hitstop() -> void:
	while _is_hitstopping:
		await get_tree().process_frame 
		var current_time = Time.get_ticks_msec() / 1000.0
		
		if current_time >= _hitstop_end_time:
			_is_hitstopping = false
			
			var is_player_domain_active = false
			var p = null
			
			var players = get_tree().get_nodes_in_group("Player")
			if players.size() > 0:
				p = players[0]
			else:
				p = get_tree().current_scene.find_child("Player*", true, false)
				
			# 霸權談判：若玩家正在開啟大招 (時停領域)，則交還時間控制權
			if p and p.get("time_stop_left") != null and p.time_stop_left > 0:
				is_player_domain_active = true
				Engine.time_scale = p.current_time_scale 
					
			if not is_player_domain_active:
				Engine.time_scale = 1.0

# ==========================================
# 📳 螢幕震動 (Camera Shake - 優先級保護版)
# ==========================================
var _shake_tween: Tween
var enable_screen_shake: bool = true 
var _shake_end_time: float = 0.0 # 記錄當前震動何時結束

func apply_camera_shake(intensity: float, duration: float = 0.06) -> void:
	if not enable_screen_shake: return
	
	var camera = get_viewport().get_camera_2d()
	if not camera: return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# 🌟 核心修復：優先級保護！
	# 如果目前正在進行「長時間的大震動」，且新來的震動只是「普攻小震動(<=0.1秒)」，則直接拒絕覆蓋！
	if _shake_tween and _shake_tween.is_valid():
		if current_time < _shake_end_time and duration <= 0.1:
			return # 保護大震動，忽略小震動
		_shake_tween.kill()
		
	_shake_end_time = current_time + duration
	camera.offset = Vector2.ZERO 
	_shake_tween = create_tween()
	
	# 震動抗時停補償
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	_shake_tween.set_speed_scale(speed_mult)
	
	var step_time: float = 0.02
	var shake_count: int = max(1, roundi(duration / step_time))
	
	for i in range(shake_count):
		# 🌟 升級：上下左右雙軸隨機狂震，打擊感更脆！
		var random_offset = Vector2(
			randf_range(-intensity, intensity), 
			randf_range(-intensity, intensity)
		)
		_shake_tween.tween_property(camera, "offset", random_offset, step_time)
		
	_shake_tween.tween_property(camera, "offset", Vector2.ZERO, step_time)

# ==========================================
# 🎨 特效預載 (Preload Scenes)
# ==========================================
const SLASH_SPARK_SCENE = preload("res://Explod/tscn/hit_spark.tscn") 
const BLUNT_SPARK_SCENE = preload("res://Explod/tscn/blunt_spark.tscn")
const DODGE_SPARK_SCENE = preload("res://Explod/tscn/DodgeSpark.tscn")
const DAMAGE_NUMBER_SCENE = preload("res://Explod/tscn/DamageNumber.tscn")
const ENERGY_ORB_SCENE = preload("res://player/energy_orb.tscn")

# ==========================================
# ✨ 特效生成系統 (VFX Spawn)
# ==========================================
# 把 raw_intensity: float = 1.0 移到最後面！
func spawn_spark(type: int, spawn_position: Vector2, attacker_dir: int = 1, target_node: Node = null, angle_offset: float = 0.0, custom_scale: float = 1.0, custom_color: Color = Color.WHITE, custom_scene: PackedScene = null, aura_color: Color = Color.WHITE, raw_intensity: float = 1.0) -> void: 
				
	var spark_scene: PackedScene = null
	match type:
		0: spark_scene = SLASH_SPARK_SCENE
		1: spark_scene = BLUNT_SPARK_SCENE 
		2: 
			if custom_scene: spark_scene = custom_scene
			else:
				printerr("❌ [CombatManager] 嘗試生成 OTHER 特效，但沒有配置 custom_spark_scene！")
				return 

	if spark_scene:
		var spark = spark_scene.instantiate()
		
		if is_instance_valid(target_node): target_node.add_child(spark)
		else: get_tree().current_scene.add_child(spark)
		
		spark.global_position = spawn_position
		spark.scale = Vector2(attacker_dir * custom_scale, custom_scale)
		spark.rotation_degrees += angle_offset
		
		var hdr_color = Color(
			custom_color.r * raw_intensity, 
			custom_color.g * raw_intensity, 
			custom_color.b * raw_intensity, 
			custom_color.a
		)
		
		_apply_vfx_colors(spark, hdr_color, aura_color)
		

func _apply_vfx_colors(node: Node, main_color: Color, aura_color: Color) -> void:
	if node is CanvasItem and node.name != "AnimationPlayer":
		if node.name == "Aura":
			node.self_modulate = aura_color
		else:
			node.self_modulate = main_color
			
	for child in node.get_children():
		_apply_vfx_colors(child, main_color, aura_color)

func spawn_damage_number(amount: int, spawn_pos: Vector2, is_heavy: bool = false) -> void:
	if not DAMAGE_NUMBER_SCENE: return
	
	var dmg_num = DAMAGE_NUMBER_SCENE.instantiate()
	get_tree().current_scene.add_child(dmg_num)
	
	dmg_num.global_position = spawn_pos
	if dmg_num.has_method("setup"): dmg_num.setup(amount, is_heavy)
		
	_apply_anti_timestop(dmg_num)

func spawn_energy_orbs(amount: int, spawn_pos: Vector2) -> void:
	if not ENERGY_ORB_SCENE: return
	
	for i in range(amount):
		var orb = ENERGY_ORB_SCENE.instantiate() as Node2D
		orb.global_position = spawn_pos 
		get_tree().current_scene.call_deferred("add_child", orb)

func spawn_dodge_spark(pos: Vector2) -> void:
	if DODGE_SPARK_SCENE:
		var spark = DODGE_SPARK_SCENE.instantiate()
		get_tree().current_scene.add_child(spark)
		spark.global_position = pos + Vector2(0, -20)
		spark.scale = Vector2(.2, .2)
		_apply_anti_timestop(spark)
		
# ==========================================
# 🛡️ 輔助：抗時停特效加速器 
# ==========================================
func _apply_anti_timestop(node: Node) -> void:
	# 🌟 核心修復：不要再算數學了！
	# 直接把節點的 Process Mode 設為 ALWAYS (永遠執行)。
	# 這樣即使 Engine.time_scale 變成了 0.05，這個節點和它底下的動畫依然會以真實世界的時間 (1.0) 播放！
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	
# ==========================================
# ⏱️ 動作遊戲專用計時器 (System Timers)
# ==========================================
func get_skill_timer(duration: float) -> SceneTreeTimer:
	# Ignore Time Scale = true，保證無敵與冷卻等核心計時不受時停干擾
	return get_tree().create_timer(duration, false, false, true)

# ==========================================
# 🎥 全域相機與特寫管理 (Camera & Close-up Management)
# ==========================================
var base_zoom := Vector2(1.0, 1.0) # 紀錄地圖當前的基準視野（普通常景 或 BOSS 戰視野）
var is_close_up_active := false    # 標記目前是否正在執行大招特寫
var _zoom_tween: Tween

## 🌟 路由介面：由 World.gd 呼叫，變更並紀錄當前的場景基準視野
func update_base_zoom(target_zoom: Vector2, duration: float = 1.5) -> void:
	base_zoom = target_zoom
	# 如果現在沒有人在放招做特寫，就立刻平滑套用新的基準視野
	if not is_close_up_active:
		_tween_camera_zoom(target_zoom, duration)

## 🌟 大招特寫介面：由角色技能呼叫！發動特寫拉近鏡頭，並在結束後「精準還原」到當前的 base_zoom
func apply_camera_closeup(closeup_zoom: Vector2, hold_duration: float, trans_in: float = 0.15, trans_out: float = 0.4) -> void:
	is_close_up_active = true
	
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
		
	var camera = get_viewport().get_camera_2d()
	if not camera: return
	
	_zoom_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	
	# 抗時停補償：確保在全域時停或卡肉時，特寫鏡頭移動依然流暢流利
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	_zoom_tween.set_speed_scale(speed_mult)
	
	# 1. 鏡頭拉近到特寫比例
	_zoom_tween.tween_property(camera, "zoom", closeup_zoom, trans_in)
	# 2. 保持特寫時間 (例如定格特寫 0.3 秒)
	_zoom_tween.tween_interval(hold_duration)
	# 3. 完美還原到【當前的基準視野】(不論是平時還是 BOSS 戰視野，通通不會迷路！)
	_zoom_tween.tween_property(camera, "zoom", base_zoom, trans_out)
	# 4. 結束後解除特寫鎖定
	_zoom_tween.tween_callback(func(): is_close_up_active = false)

# 內部平滑縮放邏輯
func _tween_camera_zoom(target_zoom: Vector2, duration: float) -> void:
	var camera = get_viewport().get_camera_2d()
	if not camera: return
	
	if _zoom_tween and _zoom_tween.is_valid() and not is_close_up_active:
		_zoom_tween.kill()
		
	_zoom_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_zoom_tween.tween_property(camera, "zoom", target_zoom, duration)

