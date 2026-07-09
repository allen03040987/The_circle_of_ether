class_name Enemy 
extends CharacterBody2D
## 敵方基底類別 (Enemy Base)
## 職責：處理共用移動、雙重霸體防禦判定、受擊閃爍特效與死亡邏輯。

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
@export var can_be_launched: bool = true       # 體重設定：是否允許被挑飛
@export var has_super_armor: bool = false      # 普通霸體：無視「輕擊」硬直
@export var has_full_super_armor: bool = false # 完全霸體：無視所有硬直

@export_group("動畫特效庫 (VFX Library)")
@export var anim_vfx_library: Dictionary = {}

# ==========================================
# 📡 內部記憶體與節點參考
# ==========================================
var pending_damage = null
var action_speed_mult: float = 1.0

@onready var graphics: Node2D = $Graphics
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var stats: Node = get_node_or_null("Stats") # 加個防呆

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
# ⚙️ 初始化與共用移動
# ==========================================
func _ready() -> void:
	if stats and stats.has_signal("poise_broken"):
		stats.poise_broken.connect(_on_poise_broken)

func move(speed: float, delta: float) -> void:
	velocity.x = move_toward(velocity.x, speed * direction, acceleration * delta)
	velocity.y += default_gravity * delta
	custom_move_and_slide()

func custom_move_and_slide() -> void:
	# 🌟 核心修復：徹底拔除敵人的抗時停特權！
	# 敵人的位移、重力與摩擦力，就應該完美服從 Engine.time_scale 被凍結！
	move_and_slide()

## 動畫安全播放：同名動畫已在播就不重播（避免每幀呼叫時卡頓重置），並套用緩速乘數（支援韌性破防系統）
func play_safe_anim(anim_name: String) -> void:
	if animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			animation_player.play(anim_name, -1, action_speed_mult)
	else:
		printerr("❌ ", name, " 找不到動畫: ", anim_name)

func die() -> void:
	queue_free()

# ==========================================
# ⚔️ 統一受擊與癱瘓入口 
# ==========================================
func _on_poise_broken(broken: bool) -> void:
	if broken:
		if CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(15.0)
		
		if graphics: graphics.modulate = Color(2.0, 0.5, 0.5, 1.0)
		var tween = create_tween()
		tween.tween_property(graphics, "modulate", Color.WHITE, 0.5)

# ==========================================
# ⚡ 黃圈彈刀 (格擋判定窗)
# ==========================================
const GUARD_CIRCLE_SCENE = preload("res://Explod/tscn/EnemyGuardCircle.tscn")
const GUARD_BREAK_BURST_SCENE = preload("res://Explod/tscn/GuardBreakBurst.tscn")

var is_guard_window_open: bool = false
var _guard_window_active: bool = false
var _guard_circle_vfx: Node2D = null

## 開啟一段「黃圈彈刀」判定窗：duration 秒內都能被 breaks_guard 攻擊命中破解，沒有前搖，一開就能破
func start_guard_window(duration: float = 1.0) -> void:
	if _guard_window_active: return
	_guard_window_active = true
	is_guard_window_open = true

	if GUARD_CIRCLE_SCENE and graphics:
		_guard_circle_vfx = GUARD_CIRCLE_SCENE.instantiate()
		graphics.add_child(_guard_circle_vfx)
		_guard_circle_vfx.position = Vector2(0, -50) # 🔧 Graphics 是以腳底為原點，往上抬到身體中段附近

	# 🔧 這裡故意用一般計時器（會被 Engine.time_scale 影響），不是 CombatManager.get_skill_timer()：
	# 破黃光招式觸發的世界時緩本來就是要讓這個判定窗「真的變長」，如果窗口關閉是不受時緩影響的真實時間，
	# 時緩再怎麼慢，窗口還是準時關閉，等於時緩完全沒延長玩家能出手的機會
	get_tree().create_timer(duration).timeout.connect(func():
		if not is_instance_valid(self): return
		_close_guard_window()
	)

func _close_guard_window() -> void:
	is_guard_window_open = false
	_guard_window_active = false
	if is_instance_valid(_guard_circle_vfx) and _guard_circle_vfx.has_method("stop"):
		_guard_circle_vfx.stop()
	_guard_circle_vfx = null

## 供各敵人 _on_hurtbox_hurt() 開頭呼叫：命中的攻擊若能破解目前開啟的黃圈判定窗，就統一處理高額傷害。
## 回傳 true 代表已經處理完畢（呼叫端可疊加自己專屬的額外反應，例如 Boss 的削韌+強制硬直）；false 代表沒破防，照正常流程走
func try_guard_break(hitbox: Hitbox) -> bool:
	if not is_guard_window_open: return false
	if not ("breaks_guard" in hitbox) or not hitbox.breaks_guard: return false
	if stats == null: return false

	_close_guard_window()

	var dmg = int(float(hitbox.damage_amount if "damage_amount" in hitbox else 1) * 3.0)
	stats.health -= dmg

	if CombatManager.has_method("spawn_damage_number"):
		CombatManager.spawn_damage_number(dmg, global_position + Vector2(0, -30), true)
	if CombatManager.has_method("apply_camera_shake"):
		CombatManager.apply_camera_shake(20.0, 0.15)

	if GUARD_BREAK_BURST_SCENE:
		var burst = GUARD_BREAK_BURST_SCENE.instantiate()
		get_tree().current_scene.add_child(burst)
		burst.global_position = global_position + Vector2(0, -30)

	AudioManager.play_action_sfx("Counterattack_successful", -2.0)

	_trigger_white_flash()
	return true

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
	elif has_super_armor and final_attack_type == Damage.Type.LIGHT:
		final_attack_type = Damage.Type.NO_STUN
		final_knockback = Vector2.ZERO
			
	# --- 5. 體重與浮空判定 ---
	if final_attack_type == Damage.Type.HEAVY and not can_be_launched:
		final_attack_type = Damage.Type.LIGHT
		final_knockback.y = 0 
		
	if final_attack_type == Damage.Type.LIGHT and is_on_floor():
		if final_knockback.y < 0: final_knockback.y = 0
			
	# --- 6. 動能保留系統 ---
	if not is_on_floor() and final_knockback.y == 0:
		final_knockback.y = velocity.y

	# --- 7. 打包數據與呼叫特效 ---
	pending_damage = {
		"source": hitbox,
		"type": final_attack_type,
		"knockback_force": final_knockback
	}
	
	_trigger_white_flash()

func strike_impulse(strength: float) -> void:
	var current_state = ""
	if has_node("StateMachine"):
		current_state = $StateMachine.current_state.name.to_lower()
		
	if current_state in ["paralyzed", "hurt", "death"]: return
	velocity.x = direction * strength

# ==========================================
# ✨ 視覺特效輔助 
# ==========================================
func _trigger_white_flash() -> void:
	# 🌟 新增：如果設定檔說不閃白光，就直接結束這個函數！
	if not Game.config_enable_hit_flash:
		return 

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

func spawn_anim_vfx(vfx_name: String, offset_x: float = 0.0, offset_y: float = 0.0, custom_scale: Vector2 = Vector2(1.0, 1.0), rotation_deg: float = 0.0, custom_color: Color = Color.WHITE, aura_color: Color = Color.WHITE, detach: bool = true, custom_z_index: int = 1, raw_intensity: float = 1.0) -> void:
	if not anim_vfx_library.has(vfx_name) or anim_vfx_library[vfx_name] == null: return

	var vfx = anim_vfx_library[vfx_name].instantiate()
	if CombatManager.has_method("_apply_anti_timestop"): CombatManager._apply_anti_timestop(vfx)

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

	CombatManager._apply_vfx_colors(vfx, Color(custom_color.r * raw_intensity, custom_color.g * raw_intensity, custom_color.b * raw_intensity, custom_color.a), aura_color)
