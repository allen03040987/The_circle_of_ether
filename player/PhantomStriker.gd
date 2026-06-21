class_name PhantomStriker
extends CharacterBody2D

var outgoing_weapon: Node
var real_player: Node
var animation_player: AnimationPlayer

var vfx_common: Dictionary = {}
var vfx_weapon: Dictionary = {}
var vfx_system: Dictionary = {}

var direction: int = 1
var default_gravity: float = 980.0
var FLOOR_ACCELERATION: float = 8000.0


var can_play_sfx: bool = false

var _death_retries: int = 0

var _target_anim: String = ""
var _target_pos: float = 0.0

var _is_initializing: bool = false # 🌟 新增：快進定位保護鎖
# ==========================================
# 🧬 靈魂轉移與初始化 (由 Player 呼叫)
# ==========================================
func setup(player: CharacterBody2D, weapon: Weapon) -> void:
	
	# 🌟 完美解耦：主動詢問武器，當下狀態是否「拒絕」生成殘影？
	if weapon.has_method("can_spawn_phantom") and not weapon.can_spawn_phantom():
		queue_free()
		return
	
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
	
	# 🌟 絕對抗時停：讓這個節點及所有子節點無視 Engine.time_scale！
	self.process_mode = Node.PROCESS_MODE_ALWAYS

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
		
		# 🌟 絕對不要改名！保留原名讓 AnimationPlayer 找得到它，就不會報錯
		phantom_hurtbox.name = "Hurtbox"
		
		# 🌟 只要把物理圖層歸零，就算動畫強行把 monitorable 設為 true，它也是個瞎子，絕對不會受傷！
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
				"_tsubame_zoom_phase", "_is_hitbox_locked", "is_spear_thrown",
				
				# 🌟 補上 is_tower_spawned，殘影才不會無限重複放塔！
				"is_vfx_fired", "is_proj_fired", "is_tower_spawned",
				"current_talisman_charge", 
				"skill_2_current_step", "skill_3_current_step", 
				"skill_2_combo_timer", "skill_3_combo_timer",   
				
				"_current_energy_reward", "_current_switch_reward", 
				"_current_pozhen_reward", "_current_iai_reward", "_current_charge_reward",
				"_multi_hit_energy", "_has_granted_resources_this_step",
				"has_used_air_hook" 
			]
			for prop in props_to_copy:
				if prop in outgoing_weapon:
					child.set(prop, outgoing_weapon.get(prop))

			# ==========================================
			# 🌟 終極解耦：用 get_index() 繞過 Godot 匿名名稱陷阱，完美接管卡帶
			# ==========================================
			var orig_art = outgoing_weapon.get("active_martial_art")
			var orig_slots = outgoing_weapon.get("martial_slots")
			var new_cloned_slots: Array[Node] = [null, null, null]

			# 1. 利用絕對子節點位置，重新校正殘影武器內部的 slots 陣列 reference
			if orig_slots is Array:
				for i in range(min(orig_slots.size(), 3)):
					if is_instance_valid(orig_slots[i]):
						# 🎯 取得本尊卡帶在武器底下的絕對子節點順序 (例如第 4 個)
						var child_idx = orig_slots[i].get_index()
						if child_idx >= 0 and child_idx < child.get_child_count():
							var found_clone = child.get_child(child_idx)
							if is_instance_valid(found_clone):
								new_cloned_slots[i] = found_clone
			child.set("martial_slots", new_cloned_slots)

			# 2. 設置並激活當前正在執行的武藝狀態
			if is_instance_valid(orig_art):
				var art_idx = orig_art.get_index()
				if art_idx >= 0 and art_idx < child.get_child_count():
					var cloned_art = child.get_child(art_idx)
					if is_instance_valid(cloned_art):
						child.set("active_martial_art", cloned_art)
						cloned_art.set("is_active", orig_art.get("is_active"))
						
						# 重新把殘影與複製的武器接上武藝卡帶，完成神經對接
						if cloned_art.has_method("setup"):
							cloned_art.setup(self, child)
						else:
							cloned_art.set("player", self)
							cloned_art.set("weapon", child)

			# 綁定正確的判定框
			if "current_active_hitbox" in outgoing_weapon and outgoing_weapon.get("current_active_hitbox") != null:
				var orig_hb = outgoing_weapon.get("current_active_hitbox")
				var hb_path = outgoing_weapon.get_path_to(orig_hb)
				var cloned_hb = child.get_node(hb_path)
				child.set("current_active_hitbox", cloned_hb)
				
				if cloned_hb.has_signal("hit") and child.has_method("_on_hitbox_hit"):
					cloned_hb.hit.connect(child._on_hitbox_hit)
				
				if "hit_targets" in orig_hb and "hit_targets" in cloned_hb:
					cloned_hb.hit_targets = orig_hb.hit_targets.duplicate()
					
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
	
	animation_player.speed_scale = 1.0
	
	var nodes_to_process = [self]
	while nodes_to_process.size() > 0:
		var current = nodes_to_process.pop_back()
		if current != self: current.owner = self
		nodes_to_process.append_array(current.get_children())

	# 6. 紀錄接力播放數據 (延遲到進入場景樹後才安全播放)
	var current_anim = player.animation_player.current_animation
	var current_pos = player.animation_player.current_animation_position

	if current_anim != "":
		_target_anim = current_anim
		_target_pos = current_pos
	else:
		die_gracefully()

# ==========================================
# 🌟 當殘影被 add_child 正式加入世界時自動觸發
# ==========================================
func _ready() -> void:
	if _target_anim != "" and is_instance_valid(animation_player):
		# 🛡️ 啟動快進定位保護鎖
		_is_initializing = true 
		
		# 此時節點已在場景樹中，打包版也能完美、立刻解析動畫路徑！
		animation_player.play(_target_anim)
		animation_player.seek(_target_pos, true)
		animation_player.advance(0)
		
		# 🌟 核心修復：不再無腦自殺，改交給專屬的過濾器判斷！
		animation_player.animation_finished.connect(_on_animation_finished)
		
		var max_lifespan: float = 2.0
		if animation_player.has_animation(_target_anim):
			var anim_data = animation_player.get_animation(_target_anim)
			if anim_data.loop_mode == Animation.LOOP_NONE:
				max_lifespan = max(0.5, anim_data.length - _target_pos + 0.2)
		
		# ==========================================
		# 🌟 完美解耦：詢問武器是否需要為這招「延長殘影的壽命保險」！
		# ==========================================
		if is_instance_valid(outgoing_weapon) and outgoing_weapon.has_method("get_phantom_lifespan"):
			var custom_lifespan = outgoing_weapon.get_phantom_lifespan()
			if custom_lifespan > 0.0:
				max_lifespan = custom_lifespan
				print("👻 [殘影系統] 武器要求延長壽命至：", max_lifespan, " 秒")
		
		get_tree().create_timer(max_lifespan, true, false, true).timeout.connect(die_gracefully)
		
		# ==========================================
		# 🌟 延遲解鎖與音效解放
		# ==========================================
		await get_tree().process_frame 
		_is_initializing = false 
		can_play_sfx = true # 🌟 垃圾清空完畢，殘影正式解除靜音！
		
	else:
		die_gracefully()
		
func _process(_delta: float) -> void:
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	
	# 動態維持動畫的真實速度 (絕對不慢動作)
	if is_instance_valid(animation_player):
		animation_player.speed_scale = speed_mult
		
func _physics_process(delta: float) -> void:
	if is_instance_valid(outgoing_weapon):
		if outgoing_weapon.has_method("get_current_velocity"):
			velocity = outgoing_weapon.get_current_velocity(delta)
			
		if outgoing_weapon.has_method("is_handling_gravity") and not outgoing_weapon.is_handling_gravity():
			if not is_on_floor():
				velocity.y += default_gravity * delta
			else:
				if velocity.y > 0: velocity.y = 0 
		
	# ==========================================
	# 🌟 貫徹標準：主邏輯嚴禁呼叫原生方法，全部交給自定義底層！
	# ==========================================
	custom_move_and_slide()

func strike_impulse(strength: float) -> void:
	if _is_initializing: 
		return 
		
	velocity.x = direction * strength

func enable_weapon_hitbox(shape_name: String = "") -> void:
	if outgoing_weapon and outgoing_weapon.has_method("enable_hitbox"):
		outgoing_weapon.enable_hitbox(shape_name)

func disable_weapon_hitbox(shape_name: String = "") -> void:
	if outgoing_weapon and outgoing_weapon.has_method("disable_hitbox"):
		outgoing_weapon.disable_hitbox(shape_name)

func play_safe_anim(anim_name: String) -> void:
	if animation_player and animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			animation_player.play(anim_name)

# 🌟 核心修復：把 _base_switch 設為 = 0.0，完美相容 2 個或 3 個參數的呼叫！
func add_weapon_resource(weapon_id: String, base_energy: float, _base_switch: float = 0.0) -> void:
	# 殘影只是個無情的打工仔，收到能量後直接呼叫老爸的快遞專線轉交！
	if is_instance_valid(real_player) and real_player.has_method("add_weapon_resource"):
		real_player.add_weapon_resource(weapon_id, base_energy)

func die_gracefully() -> void:
	var hb = outgoing_weapon.get("current_active_hitbox") if is_instance_valid(outgoing_weapon) else null
	
	# 🌟 只保留通用的防卡死邏輯，絕不干涉特定武器內部運作
	if is_instance_valid(hb) and hb.get("sticky_multi_hit") and hb.get("hit_targets") and not hb.hit_targets.is_empty() and _death_retries < 5:
		_death_retries += 1
		get_tree().create_timer(0.1, true, false, true).timeout.connect(die_gracefully)
	else:
		queue_free()

# ==========================================
# 🌟 殘影專屬 VFX 系統
# ==========================================
func spawn_anim_vfx(vfx_name: String, offset_x: float = 0.0, offset_y: float = 0.0, custom_scale: Vector2 = Vector2(1.0, 1.0), rotation_deg: float = 0.0, custom_color: Color = Color.WHITE, aura_color: Color = Color.WHITE, detach: bool = true, custom_z_index: int = 1, raw_intensity: float = 1.0) -> void:
	
	if _is_initializing: 
		return 
		
	var vfx_scene = null
	if vfx_common.has(vfx_name): vfx_scene = vfx_common[vfx_name]
	elif vfx_weapon.has(vfx_name): vfx_scene = vfx_weapon[vfx_name]
	elif vfx_system.has(vfx_name): vfx_scene = vfx_system[vfx_name]
	
	if vfx_scene == null: return

	var vfx = vfx_scene.instantiate()
	
	# ==========================================
	# 🌟 核心修復：殘影的特效也交給仲裁者統一發放特權！
	# ==========================================
	if CombatManager.has_method("_apply_anti_timestop"):
		CombatManager._apply_anti_timestop(vfx)

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

# ==========================================
# 🏃 殘影專屬物理底層 (抗時停補償)
# ==========================================
func custom_move_and_slide() -> void:
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var original_velocity = velocity
	
	# ✅ 只放大 X 軸，確保殘影能平滑往前削過去
	velocity.x *= speed_mult 
	# ❌ 絕對不要寫 velocity *= speed_mult！放過 Y 軸，不讓挑飛變火箭！
	
	# 這裡作為底層封裝，是唯一合法呼叫原生 move_and_slide 的地方
	move_and_slide()
	
	# 算完後立刻還原真實速度
	velocity = original_velocity
	
# ==========================================
# 👻 殘影生命週期過濾器
# ==========================================
func _on_animation_finished(anim_name: String) -> void:
	# 詢問武器：這個動畫播完時，殘影可以死嗎？(防禦多段狀態機招式)
	if is_instance_valid(outgoing_weapon) and outgoing_weapon.has_method("should_phantom_keep_alive"):
		if outgoing_weapon.should_phantom_keep_alive(anim_name):
			print("👻 [殘影系統] 武器要求續命，忽略動畫結束信號：", anim_name)
			return
			
	die_gracefully()
	
func _apply_vfx_colors(node: Node, main_color: Color, aura_color: Color) -> void:
	if node is CanvasItem and node.name != "AnimationPlayer":
		if node.name == "Aura": node.self_modulate = aura_color
		else: node.self_modulate = main_color
	for child in node.get_children():
		_apply_vfx_colors(child, main_color, aura_color)


func trigger_swing_sfx(sfx_type: String) -> void:
	# 🚨 核心修復：快進追趕期間被重刷出來的舊音效，一律攔截，防止炸耳朵！
	if _is_initializing: return 
	
	# 🌟 嚴格遵守 can_play_sfx 的設定
	if not can_play_sfx: return 
	AudioManager.play_action_sfx(sfx_type, -8.0)
