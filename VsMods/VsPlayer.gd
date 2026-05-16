class_name VsPlayer
extends CharacterBody2D

## 玩家核心控制與狀態管理類別 (大亂鬥/現代輸入版)
## 作為所有戰鬥角色的底層基底，處理物理位移、受擊運算與技能冷卻 (純本地極速版)。

# ==========================================
# 📍 節點參考與外部綁定
# ==========================================
@onready var vs_state_machine: VsStateMachine = $VsStateMachine
@onready var animation: AnimationPlayer = $AnimationPlayer
@onready var sprite_2d: Sprite2D = $Graphics/Sprite2D
@onready var shoot_marker: Marker2D = $Graphics/ShootMarker 
# (已移除 PingLabel，純單機不需要測網速！)

@export var opponent: VsPlayer 

# ==========================================
# 🎮 玩家控制與網路變數
# ==========================================
@export_group("🎮 玩家控制設定")
@export var player_id: int = 1

# --- 本機輸入按鍵字串暫存 ---
var left_key: String
var right_key: String
var jump_key: String
var down_key: String  
var attack_key: String
var big_dash_key: String
var small_dash_key: String
var skill_key: String 
var special_key: String
var ultimate_key: String
var custom_key: String
## 專屬 UI 卡帶：讓每個角色自己決定要帶什麼 UI 進場！
@export var custom_ui_scene: PackedScene

@export_group("⚡ 角色外掛狀態")
var is_global_guard_break: bool = false 
var has_absolute_armor: bool = false

@export_group("⏳ 遊戲時間操控")
@export var custom_time_scale: float = 1.0 



# ==========================================
# 🏃‍♂️ 基礎物理數值
# ==========================================
@export_group("🏃‍♂️ 基礎物理數值")
@export var move_speed: float = 300.0  
@export var jump_force: float = -400.0 
@export var ground_friction: float = 5000.0
@export var air_friction: float = 5000.0 
@export var is_dummy: bool = false 

@export_group("🏃‍♂️ 衝刺與體力消耗")
@export var big_dash_cost: float = 1000.0 
@export var small_dash_cost: float = 600.0

# ==========================================
# ❤️ 戰鬥血條與資源
# ==========================================
@export_group("❤️ 戰鬥血條與能量")
@export var max_hp: float = 15000.0
@export var max_stamina: float = 3000.0
@export var stamina_regen: float = 200.0 
@export var max_mp: float = 3000.0
@export var mana_regen: float = 300.0

@export_group("🛡️ 防禦與生存屬性")
@export_range(0.0, 1.0) var base_defense: float = 0.2 
var current_defense: float = 0.0 

@export_group("⚔️ 遠程武器與特效")
@export var bleed_tick_effect: PackedScene
@export var damage_popup_scene: PackedScene 

# ==========================================
# ⏳ 技能冷卻系統 (次世代升級版：支援層數 Stock System)
# ==========================================
# 字典格式：
# {
#   "插槽名稱": {
#     "current": 剩餘時間 (當前這層), 
#     "max": 最大時間 (一層),
#     "charges": 當前層數,
#     "max_charges": 最大層數
#   }
# }
var skill_cooldowns: Dictionary = {} 

# 🌟 新增：萬用初始化函數 (在常規單機版下，這個函數其實不需要 RPC，直接呼叫即可)
func init_skill_slot(slot_name: String, duration: float, max_stock: int = 1) -> void:
	skill_cooldowns[slot_name] = {
		"current": 0.0, 
		"max": max(0.01, duration),
		"charges": max_stock, # 初始化時滿層
		"max_charges": max_stock
	}

# 🌟 修正：檢查技能是否可用 (層數 > 0)
func is_skill_ready(slot_name: String) -> bool:
	if not skill_cooldowns.has(slot_name): return true 
	return skill_cooldowns[slot_name]["charges"] > 0

# 🌟 修正：啟動冷卻 (消耗一層)
func start_cooldown(slot_name: String, duration: float) -> void:
	# (💡 如果你已經在用 init_skill_slot，這裡的 duration 其實用不到了)
	if not skill_cooldowns.has(slot_name): return
	
	var cd_data = skill_cooldowns[slot_name]
	
	if cd_data["charges"] > 0:
		cd_data["charges"] -= 1 # 消耗一層
		
		# 只有在消耗掉最後一層時，才需要讓 CD 條開始轉動 (如果本來就在轉，就不用動它)
		if cd_data["charges"] == (cd_data["max_charges"] - 1):
			# 🌟 注意：如果 current 本來就是 0，代表是第一次轉。
			# 如果 current > 0，代表本來就在轉，不用理它。
			if cd_data["current"] <= 0.0:
				cd_data["current"] = cd_data["max"]

# 🌟 修正：獲取冷卻百分比 (只取當前正在轉的那一層)
func get_cooldown_percent(slot_name: String) -> float:
	if not skill_cooldowns.has(slot_name): return 0.0
	var cd_data = skill_cooldowns[slot_name]
	if cd_data["charges"] >= cd_data["max_charges"]: return 0.0 # 滿層不用轉
	if cd_data["max"] <= 0.0: return 0.0
	return clamp(cd_data["current"] / cd_data["max"], 0.0, 1.0)

# 🌟 新增：獲取當前層數 (供 UI 顯示數字用)
func get_skill_charges(slot_name: String) -> int:
	if not skill_cooldowns.has(slot_name): return 0
	return skill_cooldowns[slot_name]["charges"]

# --- 舊函數保持兼容性，但內部邏輯已改變 ---
func reduce_cooldown(slot_name: String, amount: float) -> void:
	if skill_cooldowns.has(slot_name):
		var cd_data = skill_cooldowns[slot_name]
		if cd_data["charges"] < cd_data["max_charges"]:
			cd_data["current"] = max(0.0, cd_data["current"] - amount)

func reset_cooldown(slot_name: String) -> void:
	if skill_cooldowns.has(slot_name):
		var cd_data = skill_cooldowns[slot_name]
		cd_data["charges"] = cd_data["max_charges"]
		cd_data["current"] = 0.0
	
var current_hp: float = max_hp
var current_mp: float = max_mp
var current_stamina: float = max_stamina

# ==========================================
# 🧠 戰鬥核心記憶體 (內部狀態)
# ==========================================
var jump_count := 0
var max_jumps := 2
var can_combo := false             
var invincibility_timer: float = 0.0 
var has_super_armor: bool = false    

var hitstun_time_left: float = 0.0
var received_knockback: Vector2 = Vector2.ZERO
var received_friction: float = 5000.0 
var received_causes_down: bool = false 
var received_hit_type: int = 0 

var double_tap_window: float = 0.26
var tap_timer: float = 0.0
var last_tap_key: String = ""
var double_tapped_dir: float = 0.0 

var current_bleed_ticks: int = 0
var is_currently_bleeding: bool = false

# ==============================================================================
# 🔄 1. 生命週期與主迴圈
# ==============================================================================

func _ready() -> void:
	left_key = "p%d_left" % player_id
	right_key = "p%d_right" % player_id
	jump_key = "p%d_jump" % player_id
	attack_key = "p%d_attack" % player_id
	big_dash_key = "p%d_big_dash" % player_id
	small_dash_key = "p%d_small_dash" % player_id
	down_key = "p%d_down" % player_id 
	skill_key = "p%d_skill" % player_id 
	ultimate_key = "p%d_ultimate" % player_id 
	special_key = "p%d_special" % player_id 
	custom_key = "p%d_custom" % player_id
	
	vs_state_machine.init()
	current_defense = base_defense
	
func _process(delta: float) -> void:
	# --- ⏳ 技能冷卻倒數 (次世代升級版回復邏輯) ---
	for skill in skill_cooldowns.keys():
		var cd_data = skill_cooldowns[skill]
		
		# 只有在沒滿層的時候才需要回復
		if cd_data["charges"] < cd_data["max_charges"]:
			# 🌟 當前層數倒數
			if cd_data["current"] > 0.0:
				cd_data["current"] -= delta
				
			# 🌟 回復一層！
			if cd_data["current"] <= 0.0:
				cd_data["charges"] += 1
				
				# 如果還沒滿層，自動開啟下一層的回復
				if cd_data["charges"] < cd_data["max_charges"]:
					cd_data["current"] = cd_data["max"]
				else:
					cd_data["current"] = 0.0 # 滿層，CD 歸零

	# 推進狀態機
	vs_state_machine.process_frame(delta)

func _physics_process(delta: float) -> void:
	if is_dummy:
		vs_state_machine.process_physics(delta)
		return
			
	# --- ⏱️ 雙擊方向鍵偵測 ---
	if tap_timer > 0:
		tap_timer -= delta
		if tap_timer <= 0:
			last_tap_key = "" 
			
	double_tapped_dir = 0.0 
	if Input.is_action_just_pressed(right_key):
		if last_tap_key == right_key and tap_timer > 0:
			double_tapped_dir = 1.0 
			last_tap_key = ""        
		else:
			last_tap_key = right_key
			tap_timer = double_tap_window
	elif Input.is_action_just_pressed(left_key):
		if last_tap_key == left_key and tap_timer > 0:
			double_tapped_dir = -1.0 
			last_tap_key = ""
		else:
			last_tap_key = left_key
			tap_timer = double_tap_window
		
	# --- 🔀 空中轉向鎖死系統 ---
	if not is_on_floor():
		var current_s = vs_state_machine.current_state
		if current_s is VsPlayerJumpState or current_s is VsPlayerFallState:
			var move_dir = get_move_dir() 
			if move_dir != 0:
				$Graphics.scale.x = move_dir
				
	# --- ⚙️ 執行狀態機物理運算 ---
	vs_state_machine.process_physics(delta * custom_time_scale) 
	
	# --- 🔋 資源被動回復與無敵閃爍 ---
	var is_holding_down = Input.is_action_pressed(down_key)
	var is_guarding = (vs_state_machine.current_state != null and vs_state_machine.current_state.name == "Guard")
	
	if not is_holding_down and not is_guarding:
		if current_stamina < max_stamina:
			current_stamina = min(current_stamina + stamina_regen * delta, max_stamina)
		if current_mp < max_mp:
			current_mp = min(current_mp + mana_regen * delta, max_mp)
			
	if invincibility_timer > 0.0:
		invincibility_timer -= delta
		var target_alpha = 0.3 if (Engine.get_physics_frames() % 30 < 15) else 1.0 
		set_graphics_opacity(target_alpha)
		
		if invincibility_timer <= 0.0:
			set_graphics_opacity(1.0) 

# ==============================================================================
# ⌨️ 2. 輸入與基礎位移控制
# ==============================================================================

func _input(event: InputEvent) -> void:
	# 🌟 直接丟給狀態機！再也沒有主副機的權限問題！
	vs_state_machine.process_input(event)
	
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()

func strike_impulse(strength: float) -> void:
	var facing_dir = $Graphics.scale.x
	velocity.x = strength * facing_dir
	
# ==============================================================================
# 🛡️ 3. 戰鬥狀態與異常狀態系統
# ==============================================================================

func set_can_combo(value: bool) -> void: can_combo = value
func trigger_invincibility(duration: float) -> void: invincibility_timer = duration
func set_super_armor(is_active: bool) -> void: has_super_armor = is_active

func auto_face_opponent() -> void:
	if opponent == null: return
	var dir_to_opponent = sign(opponent.global_position.x - self.global_position.x)
	if dir_to_opponent != 0:
		$Graphics.scale.x = dir_to_opponent

func take_damage(raw_damage: float) -> float:
	var final_defense = clamp(current_defense, 0.0, 0.99)
	var actual_damage = raw_damage * (1.0 - final_defense)
	current_hp -= actual_damage
	return actual_damage
	
func get_move_dir() -> float:
	if is_dummy: return 0.0
	var left = Input.is_action_pressed(left_key)
	var right = Input.is_action_pressed(right_key)
	
	if left and not right: return -1.0
	elif right and not left: return 1.0
	elif left and right:
		if Input.is_action_just_pressed(left_key): return -1.0
		if Input.is_action_just_pressed(right_key): return 1.0
	return 0.0
	
func set_pass_through(is_passing: bool) -> void:
	set_collision_mask_value(12, not is_passing)
	set_collision_layer_value(12, not is_passing)

func deactivate_all_hitboxes() -> void:
	var hitbox_container = get_node_or_null("Hitboxes")
	if hitbox_container:
		for child in hitbox_container.get_children():
			if child is Area2D:
				child.set_deferred("monitoring", false)
				child.set_deferred("monitorable", false)
				if "hit_targets" in child:
					child.hit_targets.clear()

func start_bleed(duration: float, damage_per_tick: float, tick_interval: float, custom_sparks: Array = []) -> void:
	var interval = max(0.05, tick_interval)
	var new_ticks: int = ceil(duration / interval)
	current_bleed_ticks = new_ticks 
	
	if is_currently_bleeding: return 
	is_currently_bleeding = true

	while current_bleed_ticks > 0:
		await get_tree().create_timer(interval).timeout
		if current_hp <= 0 or not is_inside_tree(): break
			
		current_hp -= damage_per_tick
		current_bleed_ticks -= 1
		spawn_damage_text(int(damage_per_tick), Color.RED)
		
		if custom_sparks.size() > 0:
			broadcast_hit_sparks(custom_sparks, 1, Vector2(20, 30), true, Vector2(0, -25), 0.0)
		elif bleed_tick_effect != null:
			broadcast_hit_sparks([bleed_tick_effect.resource_path], 1, Vector2(20, 30), true, Vector2(0, -25), 0.0)
		
	is_currently_bleeding = false

# ==========================================
# 🔫 4. 萬用發射器與視覺特效 (告別 RPC 廣播)
# ==========================================
func shoot_custom_projectile(proj_scene: PackedScene, custom_marker: Marker2D = null) -> void:
	if proj_scene == null: return
	var target_pos = self.global_position
	if custom_marker != null: target_pos = custom_marker.global_position
	elif shoot_marker != null: target_pos = shoot_marker.global_position
		
	var proj = proj_scene.instantiate()
	proj.direction = $Graphics.scale.x
	proj.owner_player = self
	
	var proj_hitbox = proj.get_node_or_null("VsHitbox")
	if proj_hitbox: proj_hitbox.owner_player = self
		
	get_parent().add_child(proj)
	proj.global_position = target_pos
	if "start_y" in proj: proj.start_y = proj.position.y

func play_camera_shake(intensity: float, duration: float) -> void:
	get_tree().call_group("camera", "shake", intensity, duration)

func trigger_cinematic_zoom(target_self: bool, target_zoom: float, duration: float) -> void:
	var target_node = self if target_self else opponent 
	if target_node:
		get_tree().call_group("camera", "cinematic_zoom", target_node, target_zoom, duration)

func spawn_afterimage(color: Color = Color(1, 0.2, 0.2, 0.6), fade_time: float = 0.4, custom_offset: Vector2 = Vector2(0, -29)) -> void:
	var my_sprite = get_node_or_null("Graphics/Sprite2D") 
	if my_sprite == null: return
	
	var ghost = Sprite2D.new()
	ghost.texture = my_sprite.texture
	ghost.hframes = my_sprite.hframes
	ghost.vframes = my_sprite.vframes
	ghost.frame = my_sprite.frame
	ghost.region_enabled = my_sprite.region_enabled
	ghost.region_rect = my_sprite.region_rect
	
	ghost.global_position = self.global_position + custom_offset
	ghost.scale = get_node_or_null("Graphics").scale 
	ghost.modulate = color 
	
	get_tree().current_scene.add_child(ghost)
	var tween = create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(ghost.queue_free)

func spawn_standalone_effect(effect_scene: PackedScene, offset_x: float, offset_y: float) -> void:
	if effect_scene == null: return
	var effect = effect_scene.instantiate()
	var dir = $Graphics.scale.x 
	effect.global_position = global_position + Vector2(offset_x * dir, offset_y)
	effect.scale.x = dir 
	get_tree().current_scene.add_child(effect)

func broadcast_hit_sparks(effect_paths: Array, count: int, spread: Vector2, random_angle: bool, offset: Vector2, interval: float) -> void:
	var facing_dir = $Graphics.scale.x
	for i in range(count):
		for path in effect_paths:
			if path == null or path == "": continue
			var effect_scene = load(path)
			if effect_scene == null: continue
			
			var effect_instance = effect_scene.instantiate()
			var final_offset = Vector2(offset.x * facing_dir, offset.y)
			var spark_rand_x = randf_range(-spread.x, spread.x)
			var spark_rand_y = randf_range(-spread.y, spread.y)
			
			effect_instance.global_position = self.global_position + final_offset + Vector2(spark_rand_x, spark_rand_y)
			
			if random_angle: effect_instance.rotation_degrees = randf_range(0.0, 360.0)
			else: effect_instance.scale.x = facing_dir
				
			get_tree().current_scene.add_child(effect_instance)
			
		if interval > 0.0 and i < (count - 1):
			await get_tree().create_timer(interval).timeout

func set_graphics_opacity(alpha: float) -> void:
	var graphics = get_node_or_null("Graphics")
	if graphics: graphics.modulate.a = alpha

func set_graphics_visible(target_visible: bool) -> void:
	var graphics = get_node_or_null("Graphics")
	if graphics: graphics.visible = target_visible

func set_global_pause(is_paused: bool) -> void:
	get_tree().paused = is_paused

func play_ultimate_cinematic(duration: float, is_freeze: bool = false) -> void:
	var perfect_frame: int = -1 
	var graphics_sprite = get_node_or_null("Graphics/Sprite2D")
	if is_freeze and graphics_sprite:
		perfect_frame = graphics_sprite.frame
			
	get_tree().paused = true
	
	var graphics = get_node_or_null("Graphics")
	var anim = get_node_or_null("AnimationPlayer")
	
	if graphics: graphics.process_mode = Node.PROCESS_MODE_ALWAYS
	
	if anim: 
		anim.process_mode = Node.PROCESS_MODE_ALWAYS
		if perfect_frame >= 0 and graphics_sprite:
			anim.active = false 
			graphics_sprite.frame = perfect_frame
		else:
			anim.active = true  
	
	var original_z = self.z_index
	self.z_index = 100
	
	var dark_bg = ColorRect.new()
	dark_bg.color = Color(0, 0, 0, 0) 
	dark_bg.position = Vector2(-20000, -20000)
	dark_bg.size = Vector2(40000, 40000)
	dark_bg.z_index = 90
	dark_bg.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(dark_bg)
		
	var tween = dark_bg.create_tween()
	tween.tween_property(dark_bg, "color:a", 0.6, 0.15)
	tween.tween_interval(duration)
	tween.tween_property(dark_bg, "color:a", 0.0, 0.2) 
	
	tween.tween_callback(func():
		dark_bg.queue_free()
		self.z_index = original_z 
		if graphics: graphics.process_mode = Node.PROCESS_MODE_INHERIT
		if anim: 
			anim.process_mode = Node.PROCESS_MODE_INHERIT
			anim.active = true 
		get_tree().paused = false 
	)
	
func custom_move_and_slide() -> bool:
	if custom_time_scale == 1.0: return move_and_slide()
	velocity *= custom_time_scale 
	var result = move_and_slide() 
	if custom_time_scale > 0.0: velocity /= custom_time_scale 
	return result

func spawn_damage_text(amount: int, text_color: Color = Color.WHITE) -> void:
	if amount <= 0 or damage_popup_scene == null: return
	var popup = damage_popup_scene.instantiate()
	popup.amount = amount
	popup.color = text_color
	popup.global_position = self.global_position + Vector2(0, -80)
	get_tree().current_scene.add_child(popup)	

func play_safe_anim(anim_name: String) -> void:
	if animation.is_playing(): animation.stop() 
	if sprite_2d != null:
		sprite_2d.vframes = 100
		sprite_2d.hframes = 100
		sprite_2d.frame = 0
	animation.play(anim_name)
