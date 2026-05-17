class_name Enemy 
extends CharacterBody2D
## 敵方基底類別 (Enemy Base)
## 負責處理移動、雙重霸體防禦判定、受擊閃爍特效與死亡邏輯。
## 支援 Poise (韌性) 系統：韌性歸零時進入虛弱、緩速與減防。

enum Direction { LEFT = -1, RIGHT = +1 }

# ==========================================
# 🎛️ 基礎與防禦屬性
# ==========================================
@export_group("移動屬性")
@export var direction := Direction.LEFT as int:
	set(v):
		direction = v
		if not is_node_ready(): await ready
		if graphics: graphics.scale.x = direction

@export var max_speed: float = 100 
@export var acceleration: float = 2000

var default_gravity := ProjectSettings.get("physics/2d/default_gravity") as float

@export_group("防禦與霸體設定")
@export var can_be_launched: bool = true # 體重設定：是否允許被挑飛
@export var has_super_armor: bool = false # 普通霸體：無視「輕擊」硬直
@export var has_full_super_armor: bool = false # 完全霸體：無視所有硬直

@export_group("動畫特效庫 (VFX Library)")
@export var anim_vfx_library: Dictionary = {}
# ==========================================
# 📡 內部記憶體與節點參考
# ==========================================
var pending_damage = null # 暫存受擊數據，供狀態機讀取
var broken_ghost_timer: float = 0.0 # 虛弱特效計時器
var action_speed_mult: float = 1.0 # 全域動作與動畫速度乘數

@onready var graphics: Node2D = $Graphics
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var stats: Node = $Stats

# ==========================================
# 🎨 閃爍特效管理
# ==========================================
const FLASH_SHADER_CODE = """
shader_type canvas_item;
void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	COLOR = vec4(1.0, 1.0, 1.0, tex_color.a * COLOR.a);
}
"""
var _flash_mat: ShaderMaterial = null
var _original_materials: Dictionary = {}
var _flash_timer = null

# ==========================================
# ⚙️ 初始化與每幀更新
# ==========================================
func _ready() -> void:
	if stats and stats.has_signal("poise_broken"):
		stats.poise_broken.connect(_on_poise_broken)
			
# ==========================================
# 🏃 基礎移動與狀態信號
# ==========================================
func move(speed: float, delta: float) -> void:
	velocity.x = move_toward(velocity.x, speed * direction, acceleration * delta)
	velocity.y += default_gravity * delta
	custom_move_and_slide()

func _on_poise_broken(broken: bool) -> void:
	if broken:
		# 🌟 改為：觸發破防時，給予強烈視覺回饋，並強制交由狀態機處理癱瘓！
		if CombatManager.has_method("apply_hitstop"): CombatManager.apply_hitstop(0.3)
		if CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(15.0)
		
		# (可選) 破防瞬間閃個紅光之類的
		if graphics: graphics.modulate = Color(2.0, 0.5, 0.5, 1.0)
		var tween = create_tween()
		tween.tween_property(graphics, "modulate", Color.WHITE, 0.5)
		
# ==========================================
# ⚔️ 統一受擊入口 (Damage Handling)
# ==========================================
func take_damage(hitbox: Hitbox) -> void:
	if stats == null or stats.health <= 0: return
		
	# --- 1. 傷害與削韌計算 ---
	var dmg = hitbox.damage_amount if "damage_amount" in hitbox else 1
	
	if "is_broken" in stats and stats.is_broken:
		dmg = int(dmg * 1.5) # 虛弱狀態減防
		
	stats.health -= dmg
	
	if "poise_damage" in hitbox and "poise" in stats:
		if not ("is_broken" in stats and stats.is_broken):
			stats.poise -= hitbox.poise_damage
	
	# --- 2. 傷害飄字 ---
	var spawn_pos = global_position + Vector2(0, -30) 
	var is_heavy = (hitbox.attack_type == Damage.Type.HEAVY) if "attack_type" in hitbox else false
	
	if CombatManager.has_method("spawn_damage_number"):
		CombatManager.spawn_damage_number(dmg, spawn_pos, is_heavy)
	
	# --- 3. 提取擊退數據 ---
	var final_knockback = Vector2.ZERO
	if "absolute_knockback" in hitbox: final_knockback = hitbox.absolute_knockback
	elif "knockback_force" in hitbox: final_knockback = hitbox.knockback_force
		
	var final_attack_type = hitbox.attack_type if "attack_type" in hitbox else Damage.Type.LIGHT
	
	# --- 4. 霸體判定 ---
	if has_full_super_armor:
		final_attack_type = Damage.Type.NO_STUN
		final_knockback = Vector2.ZERO
	elif has_super_armor:
		if final_attack_type == Damage.Type.LIGHT:
			final_attack_type = Damage.Type.NO_STUN
			final_knockback = Vector2.ZERO
			
	# --- 5. 體重與浮空判定 ---
	if final_attack_type == Damage.Type.HEAVY and not can_be_launched:
		final_attack_type = Damage.Type.LIGHT
		final_knockback.y = 0 
		
	if final_attack_type == Damage.Type.LIGHT and is_on_floor():
		if final_knockback.y < 0: final_knockback.y = 0
			
	# --- 6. 動能保留系統 (Momentum Preservation) ---
	if not is_on_floor() and final_knockback.y == 0:
		final_knockback.y = velocity.y

	# --- 7. 打包數據與呼叫特效 ---
	pending_damage = {
		"source": hitbox,
		"type": final_attack_type,
		"knockback_force": final_knockback
	}
	
	_trigger_white_flash()

# ==========================================
# 🎬 動畫軌道專用：瞬間衝力 (Animation Impulse)
# ==========================================
func strike_impulse(strength: float) -> void:
	# 1. 取得狀態機目前的狀態 (確保有掛載 StateMachine)
	var current_state = ""
	if has_node("StateMachine"):
		current_state = $StateMachine.current_state.name.to_lower()
		
	# 2. 🛡️ 防護網攔截：如果被打癱瘓、受擊硬直或已經死了，絕對不准衝刺！
	if current_state in ["paralyzed", "hurt", "death"]:
		print("🛡️ [防護網觸發] BOSS 處於癱瘓或死亡，成功攔截動畫衝刺偷渡！")
		return
		
	# 3. 🌟 BOSS 純淨版推力：不需要抗時停！直接給予動能！
	# (正數往前衝，負數往後退)
	velocity.x = direction * strength
	
# ==========================================
# ✨ 視覺特效輔助 
# ==========================================
func _trigger_white_flash() -> void:
	if _flash_mat == null:
		_flash_mat = ShaderMaterial.new()
		var shader = Shader.new()
		shader.code = FLASH_SHADER_CODE
		_flash_mat.shader = shader
		
	_apply_flash_material(graphics)
	
	var timer = CombatManager.get_skill_timer(0.08)
	_flash_timer = timer
	timer.timeout.connect(func():
		if is_instance_valid(self) and _flash_timer == timer:
			_restore_original_materials(graphics)
	)

func _apply_flash_material(node: Node) -> void:
	if node is Sprite2D or node is AnimatedSprite2D or node is Polygon2D:
		if not _original_materials.has(node): _original_materials[node] = node.material
		node.material = _flash_mat
	for child in node.get_children(): _apply_flash_material(child)

func _restore_original_materials(node: Node) -> void:
	if node is Sprite2D or node is AnimatedSprite2D or node is Polygon2D:
		if _original_materials.has(node): node.material = _original_materials[node]
	for child in node.get_children(): _restore_original_materials(child) 

# 復用 Player 的 spawn_anim_vfx 函數
func spawn_anim_vfx(vfx_name: String, offset_x: float = 0.0, offset_y: float = 0.0, custom_scale: Vector2 = Vector2(1.0, 1.0), rotation_deg: float = 0.0, custom_color: Color = Color.WHITE, aura_color: Color = Color.WHITE, detach: bool = true, custom_z_index: int = 1, raw_intensity: float = 1.0) -> void:
	if not anim_vfx_library.has(vfx_name) or anim_vfx_library[vfx_name] == null:
		return

	var vfx = anim_vfx_library[vfx_name].instantiate()
	
	# 🗑️ 刪除：把所有 speed_mult 或 process_mode 的抗時停邏輯全部刪掉！
	# 讓特效乖乖繼承引擎當前的 time_scale。
		
	if detach:
		get_parent().add_child(vfx)
		vfx.global_position = global_position + Vector2(offset_x * direction, offset_y)
		vfx.z_index = self.z_index + custom_z_index 
	else:
		self.add_child(vfx)
		vfx.position = Vector2(offset_x * direction, offset_y)
		vfx.z_index = custom_z_index

	vfx.scale = Vector2(direction * custom_scale.x, custom_scale.y)
	vfx.rotation_degrees = rotation_deg * direction
	
	_apply_vfx_colors(vfx, Color(custom_color.r * raw_intensity, custom_color.g * raw_intensity, custom_color.b * raw_intensity, custom_color.a), aura_color)
	
# 記得也要把這個私有函數搬過去
func _apply_vfx_colors(node: Node, main_color: Color, aura_color: Color) -> void:
	if node is CanvasItem and node.name != "AnimationPlayer":
		if node.name == "Aura": node.self_modulate = aura_color
		else: node.self_modulate = main_color
	for child in node.get_children(): _apply_vfx_colors(child, main_color, aura_color)
	
# ==========================================
# 🏃 物理出口與死亡邏輯
# ==========================================
func custom_move_and_slide() -> void:
	# ✅ 回歸純淨的位移，不再受緩速乘數干擾
	move_and_slide()

func die() -> void:
	queue_free()
