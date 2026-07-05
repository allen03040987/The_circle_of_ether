class_name CombatManagerSingleton
extends Node
## 全域戰鬥管理器 (Autoload)
## 負責集中調度遊戲中的時間流速、相機震動/縮放，以及全域戰鬥特效生成。

# ==========================================
# ⏱️ 時間流速仲裁系統
# ==========================================
var _is_domain_active: bool = false
var _domain_scale: float = 1.0
var _is_ui_paused: bool = false

# ==========================================
# 📳 螢幕震動控制變數
# ==========================================
var _shake_tween: Tween
var enable_screen_shake: bool = true 
var _shake_end_time: float = 0.0

# ==========================================
# ⚙️ 初始化與設定同步
# ==========================================
## 系統初始化，綁定全域設定變更訊號
func _ready() -> void:
	_sync_settings()
	if not Game.settings_changed.is_connected(_sync_settings):
		Game.settings_changed.connect(_sync_settings)

## 同步玩家的遊戲設定（如：是否開啟螢幕震動）
func _sync_settings() -> void:
	enable_screen_shake = Game.config_enable_screen_shake

## 觸發領域展開或大招的專屬時間流速 (時停/緩速)
func set_domain_time(scale: float) -> void:
	_is_domain_active = true
	_domain_scale = scale
	_update_time_scale()

## 解除領域/大招時間流速，恢復正常
func clear_domain_time() -> void:
	_is_domain_active = false
	_domain_scale = 1.0
	_update_time_scale()

## 暫停或恢復 UI 時間 (開啟選單時使用)
func set_ui_paused(is_paused: bool) -> void:
	_is_ui_paused = is_paused
	_update_time_scale()

## 內部核心：仲裁並更新目前的 Engine.time_scale，並同步更新抗時停特效
func _update_time_scale() -> void:
	if _is_ui_paused:
		Engine.time_scale = 1.0            
	elif _is_domain_active:
		Engine.time_scale = _domain_scale  
	else:
		Engine.time_scale = 1.0            
	
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	for vfx_node in get_tree().get_nodes_in_group("anti_timestop_vfx"):
		if is_instance_valid(vfx_node):
			_apply_speed_scale_recursive(vfx_node, speed_mult)

# ==========================================
# 🎥 螢幕震動 (Camera Shake)
# ==========================================
## 全域呼叫螢幕震動，支援強度與持續時間設定
func apply_camera_shake(intensity: float, duration: float = 0.06) -> void:
	if not enable_screen_shake: return
	
	var camera = get_viewport().get_camera_2d()
	if not camera: return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# 避免較弱的短震動覆蓋掉正在進行的強烈大震動
	if _shake_tween and _shake_tween.is_valid():
		if current_time < _shake_end_time and duration <= 0.1:
			return 
		_shake_tween.kill()
		
	_shake_end_time = current_time + duration
	camera.offset = Vector2.ZERO 
	_shake_tween = create_tween()
	
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	_shake_tween.set_speed_scale(speed_mult)
	
	var step_time: float = 0.02
	var shake_count: int = max(1, roundi(duration / step_time))
	
	for i in range(shake_count):
		var random_offset = Vector2(
			randf_range(-intensity, intensity), 
			randf_range(-intensity, intensity)
		)
		_shake_tween.tween_property(camera, "offset", random_offset, step_time)
		
	_shake_tween.tween_property(camera, "offset", Vector2.ZERO, step_time)

# ==========================================
# 🎨 特效預載與生成 (VFX Spawn)
# ==========================================
const SLASH_SPARK_SCENE = preload("res://Explod/tscn/hit_spark.tscn") 
const BLUNT_SPARK_SCENE = preload("res://Explod/tscn/blunt_spark.tscn")
const DODGE_SPARK_SCENE = preload("res://Explod/tscn/DodgeSpark.tscn")
const DAMAGE_NUMBER_SCENE = preload("res://Explod/tscn/DamageNumber.tscn")
const ENERGY_ORB_SCENE = preload("res://player/energy_orb.tscn")

## 在指定位置生成打擊火花或自訂特效
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
		_apply_anti_timestop(spark)
		
		if is_instance_valid(target_node): target_node.add_child(spark)
		else: get_tree().current_scene.add_child(spark)
		
		spark.global_position = spawn_position
		spark.scale = Vector2(attacker_dir * custom_scale, custom_scale)
		spark.rotation_degrees += angle_offset
		
		var hdr_color = Color(custom_color.r * raw_intensity, custom_color.g * raw_intensity, custom_color.b * raw_intensity, custom_color.a)
		_apply_vfx_colors(spark, hdr_color, aura_color)

## 遞迴套用特效的主色與光暈色 (Aura)
func _apply_vfx_colors(node: Node, main_color: Color, aura_color: Color) -> void:
	if node is CanvasItem and node.name != "AnimationPlayer":
		node.self_modulate = aura_color if node.name == "Aura" else main_color
	for child in node.get_children():
		_apply_vfx_colors(child, main_color, aura_color)

## 生成傷害數字浮動文字
func spawn_damage_number(amount: int, spawn_pos: Vector2, is_heavy: bool = false) -> void:
	if not DAMAGE_NUMBER_SCENE: return
	var dmg_num = DAMAGE_NUMBER_SCENE.instantiate()
	get_tree().current_scene.add_child(dmg_num)
	dmg_num.global_position = spawn_pos
	if dmg_num.has_method("setup"): dmg_num.setup(amount, is_heavy)
	_apply_anti_timestop(dmg_num)

## 生成能量球 (通常用於打擊回復或擊殺掉落)
func spawn_energy_orbs(amount: int, spawn_pos: Vector2) -> void:
	if not ENERGY_ORB_SCENE: return
	for i in range(amount):
		var orb = ENERGY_ORB_SCENE.instantiate() as Node2D
		orb.global_position = spawn_pos 
		get_tree().current_scene.call_deferred("add_child", orb)

## 生成極限閃避專屬火花
func spawn_dodge_spark(pos: Vector2) -> void:
	if DODGE_SPARK_SCENE:
		var spark = DODGE_SPARK_SCENE.instantiate()
		get_tree().current_scene.add_child(spark)
		spark.global_position = pos + Vector2(0, -20)
		spark.scale = Vector2(.2, .2)
		_apply_anti_timestop(spark)
		
# ==========================================
# 🛡️ 抗時停特效加速器 (Anti-Timestop)
# ==========================================
## 註冊並應用抗時停邏輯，確保特效在時停期間依然能正常播放
func _apply_anti_timestop(node: Node) -> void:
	node.add_to_group("anti_timestop_vfx")
	
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	if speed_mult > 1.0:
		_apply_speed_scale_recursive(node, speed_mult)

## 遞迴設定節點內所有動畫與粒子的播放速度
func _apply_speed_scale_recursive(node: Node, mult: float) -> void:
	if node is AnimationPlayer or node is GPUParticles2D or node is CPUParticles2D:
		node.speed_scale = mult
	for child in node.get_children():
		_apply_speed_scale_recursive(child, mult)
		
# ==========================================
# ⏱️ 計時器與全域相機
# ==========================================
## 建立不受時停影響的安全計時器
func get_skill_timer(duration: float) -> SceneTreeTimer:
	return get_tree().create_timer(duration, false, false, true)

var base_zoom := Vector2(1.0, 1.0) 
var is_close_up_active := false    
var _zoom_tween: Tween

## 更新相機的基準縮放值 (用於關卡切換或進入大空間)
func update_base_zoom(target_zoom: Vector2, duration: float = 1.5) -> void:
	base_zoom = target_zoom
	if not is_close_up_active:
		_tween_camera_zoom(target_zoom, duration)

## 施放大招時觸發的相機特寫/拉近運鏡
func apply_camera_closeup(closeup_zoom: Vector2, hold_duration: float, trans_in: float = 0.15, trans_out: float = 0.4) -> void:
	is_close_up_active = true
	
	if _zoom_tween and _zoom_tween.is_valid(): _zoom_tween.kill()
	var camera = get_viewport().get_camera_2d()
	if not camera: return
	
	_zoom_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	_zoom_tween.set_speed_scale(speed_mult)
	
	_zoom_tween.tween_property(camera, "zoom", closeup_zoom, trans_in)
	_zoom_tween.tween_interval(hold_duration)
	_zoom_tween.tween_property(camera, "zoom", base_zoom, trans_out)
	_zoom_tween.tween_callback(func(): is_close_up_active = false)

## 內部調用：負責執行縮放的 Tween 動畫
func _tween_camera_zoom(target_zoom: Vector2, duration: float) -> void:
	var camera = get_viewport().get_camera_2d()
	if not camera: return
	if _zoom_tween and _zoom_tween.is_valid() and not is_close_up_active: _zoom_tween.kill()
		
	if duration <= 0.0:
		camera.zoom = target_zoom
		return
		
	_zoom_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_zoom_tween.tween_property(camera, "zoom", target_zoom, duration)

## 強制重置所有時間、相機縮放與震動狀態 (通常用於玩家死亡或場景重置)
func force_reset_time() -> void:
	_is_domain_active = false
	_is_ui_paused = false
	_domain_scale = 1.0
	Engine.time_scale = 1.0
	is_close_up_active = false
	if _zoom_tween and _zoom_tween.is_valid(): _zoom_tween.kill()
	if _shake_tween and _shake_tween.is_valid(): _shake_tween.kill()
