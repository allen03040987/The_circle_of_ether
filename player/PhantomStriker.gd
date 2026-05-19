class_name PhantomStriker
extends CharacterBody2D

var outgoing_weapon: Node
var real_player: Node
var animation_player: AnimationPlayer

var vfx_common: Dictionary = {}
var vfx_weapon: Dictionary = {}
var vfx_system: Dictionary = {}

var direction: int = 1
var is_input_locked: bool = false
var default_gravity: float = 980.0
var FLOOR_ACCELERATION: float = 8000.0

# ==========================================
# 🧬 靈魂轉移與初始化 (由 Player 呼叫)
# ==========================================
func setup(player: CharacterBody2D, weapon: Weapon) -> void:
	self.name = "Phantom_" + weapon.name
	self.global_position = player.global_position
	
	# 1. 基礎屬性轉移
	real_player = player
	outgoing_weapon = weapon
	direction = player.direction
	vfx_common = player.vfx_common
	vfx_weapon = player.vfx_weapon
	vfx_system = player.vfx_system
	z_index = player.z_index
	default_gravity = player.default_gravity
	FLOOR_ACCELERATION = player.FLOOR_ACCELERATION
	velocity = player.velocity

	# 物理隔離：不碰撞怪物，只踩地板
	collision_layer = 0
	collision_mask = 1

	# 2. 複製碰撞體
	for child in player.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			var cloned_shape = child.duplicate()
			add_child(cloned_shape)

	# 3. 複製外觀與武器
	var cloned_graphics = player.graphics.duplicate()
	add_child(cloned_graphics)
	cloned_graphics.position = player.graphics.position
	cloned_graphics.scale = player.graphics.scale
	cloned_graphics.modulate = Color(1.0, 1.0, 1.0, 0.5)

	# 拔除殘影的碰撞受擊能力
	if cloned_graphics.has_node("Hurtbox"):
		var phantom_hurtbox = cloned_graphics.get_node("Hurtbox")
		phantom_hurtbox.collision_layer = 0
		phantom_hurtbox.collision_mask = 0
		for child in phantom_hurtbox.get_children():
			if child is CollisionShape2D or child is CollisionPolygon2D:
				child.queue_free()

	# 清理多餘武器，只保留正在揮動的那把
	var cloned_weapon_slot = cloned_graphics.get_node("WeaponSlot")
	var cloned_weapon = null
	for child in cloned_weapon_slot.get_children():
		if child.name != outgoing_weapon.name:
			child.queue_free()
		else:
			cloned_weapon = child
			child.show()
			child.set("player", self) # 🌟 武器的總機換成殘影！

			# 複製武器內部狀態
			var props_to_copy = [
				"combo_step", "is_attacking", "step_cooldown",
				"is_launch_triggered", "launch_timer",
				"current_charge_timer", "current_charge_tier", "light_hold_timer",
				"is_wave_fired", "air_attack_locked", "is_time_stop_triggered",
				"_tsubame_zoom_phase", "_is_hitbox_locked", "is_spear_thrown"
			]
			for prop in props_to_copy:
				if prop in outgoing_weapon:
					child.set(prop, outgoing_weapon.get(prop))

			# 綁定正確的判定框
			if "current_active_hitbox" in outgoing_weapon and outgoing_weapon.get("current_active_hitbox") != null:
				var orig_hb = outgoing_weapon.get("current_active_hitbox")
				var hb_path = outgoing_weapon.get_path_to(orig_hb)
				child.set("current_active_hitbox", child.get_node(hb_path))

	outgoing_weapon = cloned_weapon # 替換為複製品

	# 4. 靜音處理 (塞住 AnimationPlayer 的嘴)
	var original_sfx = player.get_node_or_null("SfxPlayer")
	if original_sfx:
		var dummy_sfx = original_sfx.duplicate()
		
		if "volume_db" in dummy_sfx: 
			dummy_sfx.volume_db = original_sfx.volume_db - 10.0
		add_child(dummy_sfx)

	# 5. 轉移動畫與修正所有權
	animation_player = player.animation_player.duplicate()
	add_child(animation_player)
	
	var nodes_to_process = [self]
	while nodes_to_process.size() > 0:
		var current = nodes_to_process.pop_back()
		if current != self: current.owner = self
		nodes_to_process.append_array(current.get_children())

	# 6. 接力播放殘影演出
	var current_anim = player.animation_player.current_animation
	var current_pos = player.animation_player.current_animation_position

	if current_anim != "":
		animation_player.play(current_anim)
		animation_player.seek(current_pos, true)
		
		# 使用 unbind(1) 自動忽略 animation_finished 傳來的參數
		animation_player.animation_finished.connect(die_gracefully.unbind(1))
		
		var max_lifespan: float = 2.0
		if animation_player.has_animation(current_anim):
			var anim_data = animation_player.get_animation(current_anim)
			if anim_data.loop_mode == Animation.LOOP_NONE:
				max_lifespan = max(0.5, anim_data.length - current_pos + 0.2)
				
		get_tree().create_timer(max_lifespan, false).timeout.connect(die_gracefully)
	else:
		die_gracefully()

# ==========================================
# 🏃 物理與代理功能 (Proxy Functions)
# ==========================================
func _physics_process(delta: float) -> void:
	if is_instance_valid(outgoing_weapon):
		if outgoing_weapon.has_method("get_current_velocity"):
			velocity = outgoing_weapon.get_current_velocity(delta)
			
		if outgoing_weapon.has_method("is_handling_gravity") and not outgoing_weapon.is_handling_gravity():
			if not is_on_floor():
				velocity.y += default_gravity * delta
			else:
				if velocity.y > 0: velocity.y = 0 
					
		move_and_slide()

func strike_impulse(strength: float) -> void:
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	velocity.x = direction * (strength * speed_mult)

func enable_weapon_hitbox(shape_name: String = "") -> void:
	if outgoing_weapon and outgoing_weapon.has_method("enable_hitbox"):
		outgoing_weapon.enable_hitbox(shape_name)

func disable_weapon_hitbox(shape_name: String = "") -> void:
	if outgoing_weapon and outgoing_weapon.has_method("disable_hitbox"):
		outgoing_weapon.disable_hitbox(shape_name)

func add_ghost() -> void: pass 

func play_safe_anim(anim_name: String) -> void:
	if animation_player and animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			animation_player.play(anim_name)

func add_weapon_resource(w_id: String, e: float, s: float) -> void:
	if real_player and real_player.has_method("add_weapon_resource"):
		real_player.add_weapon_resource(w_id, e, s)

func die_gracefully() -> void:
	var hb = outgoing_weapon.get("current_active_hitbox") if is_instance_valid(outgoing_weapon) else null
	if is_instance_valid(hb) and hb.get("sticky_multi_hit") and hb.get("hit_targets") and not hb.hit_targets.is_empty():
		get_tree().create_timer(0.1, false).timeout.connect(die_gracefully)
	else:
		queue_free()

# ==========================================
# 🌟 殘影專屬 VFX 系統
# ==========================================
func spawn_anim_vfx(vfx_name: String, offset_x: float = 0.0, offset_y: float = 0.0, custom_scale: Vector2 = Vector2(1.0, 1.0), rotation_deg: float = 0.0, custom_color: Color = Color.WHITE, aura_color: Color = Color.WHITE, detach: bool = true, custom_z_index: int = 1, raw_intensity: float = 1.0) -> void:
	var vfx_scene = null
	if vfx_common.has(vfx_name): vfx_scene = vfx_common[vfx_name]
	elif vfx_weapon.has(vfx_name): vfx_scene = vfx_weapon[vfx_name]
	elif vfx_system.has(vfx_name): vfx_scene = vfx_system[vfx_name]

	if vfx_scene == null: return

	var vfx = vfx_scene.instantiate()
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	if vfx.has_node("AnimationPlayer"): vfx.get_node("AnimationPlayer").speed_scale = speed_mult
	if vfx is GPUParticles2D: vfx.speed_scale = speed_mult
	elif vfx.has_node("GPUParticles2D"): vfx.get_node("GPUParticles2D").speed_scale = speed_mult

	if detach:
		get_parent().add_child(vfx)
		var spawn_pos = global_position
		spawn_pos.x += offset_x * direction
		spawn_pos.y += offset_y
		vfx.global_position = spawn_pos
		vfx.z_index = self.z_index + custom_z_index
	else:
		self.add_child(vfx)
		vfx.position = Vector2(offset_x * direction, offset_y)
		vfx.z_index = custom_z_index

	vfx.scale = Vector2(direction * custom_scale.x, custom_scale.y)
	vfx.rotation_degrees = rotation_deg * direction

	var hdr_color = Color(custom_color.r * raw_intensity, custom_color.g * raw_intensity, custom_color.b * raw_intensity, custom_color.a)
	_apply_vfx_colors(vfx, hdr_color, aura_color)

func _apply_vfx_colors(node: Node, main_color: Color, aura_color: Color) -> void:
	if node is CanvasItem and node.name != "AnimationPlayer":
		if node.name == "Aura": node.self_modulate = aura_color
		else: node.self_modulate = main_color
	for child in node.get_children():
		_apply_vfx_colors(child, main_color, aura_color)


func trigger_swing_sfx(sfx_type: String) -> void:
	
	if AudioManager.has_method("play_action_sfx"):
		AudioManager.play_action_sfx(sfx_type, -12.0)
