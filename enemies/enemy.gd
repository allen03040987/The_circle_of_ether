class_name Enemy 
extends CharacterBody2D
## 敵方基底類別 (Enemy Base)
## 職責：處理共用移動、雙重霸體防禦判定、受擊閃爍特效與死亡邏輯。

enum Direction { LEFT = -1, RIGHT = +1 }

# ==========================================
# 🏷️ 階級制：目前只有 Slime(低)/BossNaihe(高) 兩隻，中階先留著給以後的新敵人用。
# 影響三個層面——這裡只提供「霸體」這一層的機制掛鉤，體質數值/AI複雜度是設計慣例，不是程式碼機制
# ==========================================
enum Tier { LOW, MID, HIGH }
@export var tier: Tier = Tier.LOW

## 攻擊狀態統一在 enter()/exit() 呼叫這兩個——依階級決定要不要自動開霸體。
## MID/HIGH 攻擊時自動開；LOW 永遠不會有霸體招
func enter_attack_state() -> void:
	if tier == Tier.MID or tier == Tier.HIGH: grant_hyper_armor()

func exit_attack_state() -> void:
	if tier == Tier.MID or tier == Tier.HIGH: clear_hyper_armor()

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

@export_group("防禦設定")
@export var can_be_launched: bool = true       # 體重設定：是否允許被挑飛

# ==========================================
# 🛡️ 霸體 / 無敵 —— 都是「現在這一刻」有沒有開啟的動態狀態，由施放中的招式自己 grant/clear
# （例如黃圈技窗口期間）。霸體只免疫擊退/硬直，不減傷（跟玩家的「強霸體」不同）；無敵則是完全無視這次攻擊。
# ==========================================
var is_hyper_armored: bool = false
var is_invincible: bool = false

func grant_hyper_armor() -> void:
	is_hyper_armored = true

func clear_hyper_armor() -> void:
	is_hyper_armored = false

func grant_invincibility() -> void:
	is_invincible = true

func clear_invincibility() -> void:
	is_invincible = false

# ==========================================
# 🎨 狀態輪廓描邊：霸體(藍，低不透明度)/無敵(紅)——跟 Player.gd 同一份 shader、同一套邏輯
# （漸進漸出 + 校正 spritesheet 格數避免雜點），優先權：無敵 > 霸體
# 🔧 黃圈技(start_guard_window())本身已經有專屬的黃色光環 VFX 了，這裡故意不疊加黃色輪廓，
# 不然同一個窗口會同時冒出光環+輪廓兩種黃色視覺，反而更雜亂
# ==========================================
const OUTLINE_SHADER = preload("res://classes/StatusOutline.gdshader")
const HYPER_ARMOR_OUTLINE_COLOR := Color(0.5, 0.8, 1.4, 0.7) ## 藍色，alpha 降到 0.5 降低存在感
const INVINCIBLE_OUTLINE_COLOR := Color(1.0, 0.15, 0.15, 1.0) ## 紅色
const OUTLINE_FADE_DURATION: float = 0.15

var _outline_mat: ShaderMaterial = null
var _outline_tween: Tween = null
var _outline_state: String = "" ## "" / "invincible" / "hyper_armor"——邏輯狀態，一改變就馬上是新值
var _outline_material_active: bool = false ## 材質層面「輪廓現在該不該蓋著本體」——淡出動畫真的跑完才會變 false，
## 跟 _outline_state 分開追蹤是因為兩者變 false 的時間點不一樣：_outline_state 一變就換，但材質還要撐到淡出跑完
var _base_sprite_material: Material = null ## 本體 Sprite2D 完全沒有特效時該有的材質，_ready() 只抓一次快照
var _is_flashing: bool = false ## 受擊白閃是否正在覆蓋本體材質

func _process(_delta: float) -> void:
	_update_status_outline()

func _update_status_outline() -> void:
	var desired_state := ""
	# 🔧 純視覺開關：關掉時一律不顯示輪廓，但底下的無敵/霸體判定完全不受影響
	if Game.config_enable_status_outline:
		if is_invincible: desired_state = "invincible"
		elif is_hyper_armored: desired_state = "hyper_armor"

	if desired_state != _outline_state:
		_outline_state = desired_state
		match desired_state:
			"invincible": _apply_outline(INVINCIBLE_OUTLINE_COLOR)
			"hyper_armor": _apply_outline(HYPER_ARMOR_OUTLINE_COLOR)
			_: _clear_outline()

	if is_instance_valid(_outline_mat) and _outline_material_active:
		_sync_outline_frame_bounds()

func _apply_outline(color: Color) -> void:
	if _outline_mat == null:
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = OUTLINE_SHADER
	_outline_mat.set_shader_parameter("line_color", color)
	_outline_mat.set_shader_parameter("outline_alpha", 0.0)
	_outline_material_active = true
	_refresh_main_sprite_material()

	if is_instance_valid(_outline_tween) and _outline_tween.is_valid(): _outline_tween.kill()
	_outline_tween = create_tween()
	_outline_tween.tween_property(_outline_mat, "shader_parameter/outline_alpha", 1.0, OUTLINE_FADE_DURATION)

func _clear_outline() -> void:
	if not is_instance_valid(_outline_mat): return
	if is_instance_valid(_outline_tween) and _outline_tween.is_valid(): _outline_tween.kill()
	_outline_tween = create_tween()
	_outline_tween.tween_property(_outline_mat, "shader_parameter/outline_alpha", 0.0, OUTLINE_FADE_DURATION)
	_outline_tween.tween_callback(func():
		# 🔧 淡出動畫真的跑完才關掉，不能提早在 _outline_state 一變 "" 就關——
		# 不然淡出途中如果被打中觸發白閃，閃光結束時 resolve 到這裡會直接判定「不用顯示輪廓了」，
		# 材質瞬間被換掉，視覺上就變成「沒有漸變、直接消失」
		_outline_material_active = false
		_refresh_main_sprite_material()
	)

func _sync_outline_frame_bounds() -> void:
	var sprite = graphics.get_node_or_null("Sprite2D")
	if not is_instance_valid(sprite) or not (sprite is Sprite2D): return

	var h = maxi(sprite.hframes, 1)
	var v = maxi(sprite.vframes, 1)
	if h <= 1 and v <= 1:
		_outline_mat.set_shader_parameter("frame_uv_min", Vector2.ZERO)
		_outline_mat.set_shader_parameter("frame_uv_max", Vector2.ONE)
		return

	var col = sprite.frame % h
	var row = int(sprite.frame / h)
	var uv_min = Vector2(float(col) / h, float(row) / v)
	var uv_max = uv_min + Vector2(1.0 / h, 1.0 / v)
	_outline_mat.set_shader_parameter("frame_uv_min", uv_min)
	_outline_mat.set_shader_parameter("frame_uv_max", uv_max)

## 🛡️ 本體 Sprite2D 的 material 由「即時狀態解析」決定，不用快照/還原——
## 這是本體唯一的寫入入口，跟受擊白閃系統共用同一份解析結果，兩邊都呼叫這個函式而不是各自快照，
## 從根本避免「白閃/輪廓互相搶著還原成舊快照，結果卡在錯的材質上」這類race（就是這次boss卡全白的根因）
func _resolve_main_sprite_material() -> Material:
	if _is_flashing: return _flash_mat
	if _outline_material_active: return _outline_mat
	return _base_sprite_material

func _refresh_main_sprite_material() -> void:
	var sprite = graphics.get_node_or_null("Sprite2D")
	if is_instance_valid(sprite): sprite.material = _resolve_main_sprite_material()

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

	# 🔧 只在這裡抓一次「完全沒特效」時的材質快照，之後白閃/輪廓都靠 _resolve_main_sprite_material() 即時算，
	# 不再各自快照互相蓋來蓋去
	var sprite = graphics.get_node_or_null("Sprite2D") if graphics else null
	if is_instance_valid(sprite): _base_sprite_material = sprite.material

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
# ⚠️ 通用出招預警圖示工具
# ==========================================
var _warning_tweens: Dictionary = {} ## icon -> 正在淡入的 Tween，hide 時要記得殺掉，不然淡入還在跑會把 icon 又淡回來
var _warning_tokens: Dictionary = {} ## icon -> 目前有效的預警請求編號，delay 計時器到期時要核對還算不算數
var _warning_token_counter: int = 0
var _warning_icon_base_scales: Dictionary = {} ## icon -> 場景裡原本設定的 scale，第一次看到時記一次，之後都以此為基準乘上設定檔的倍率

const WARNING_ICON_SCALE_MULTIPLIERS := [0.5, 0.75, 1.0] ## 對應設定檔 0=小/1=中/2=大
const WARNING_ICON_SIZE_NONE := 3 ## 設定檔第 4 檔「無」：直接不顯示，不是縮到 0

## 純特效函式：delay 秒後淡入顯示 icon，純粹讓敵人在頭上比出驚嘆號，不帶任何流程/計時邏輯——
## 攻擊本身該什麼時候真的打出去，完全是呼叫端自己的行為樹決定，這裡不插手、不阻塞。
## duration > 0 時會在淡入後自動倒數、淡出、隱藏，呼叫端不用自己記得收尾；
## duration < 0（預設）則維持舊行為：一直亮著，呼叫端要自己在對的時機呼叫 hide_attack_warning() 收掉。
## 回傳建立的 SceneTreeTimer，如果狀態中途被打斷、呼叫端想取消，可以直接呼叫 hide_attack_warning()。
func show_attack_warning(icon: CanvasItem, delay: float = 0.0, duration: float = -1.0, fade_duration: float = 0.3) -> SceneTreeTimer:
	if not is_instance_valid(icon): return null
	if Game.config_warning_icon_size == WARNING_ICON_SIZE_NONE: return null # 🔧「無」：整個功能直接不啟動，icon 維持原本的隱藏狀態

	# 🔧 用 .get()/.set() 動態存取 scale：icon 型別是 CanvasItem，但 scale 其實是 Node2D/Control 才有的成員，
	# 靜態型別檢查不會通過 icon.scale 這種直接寫法
	if not _warning_icon_base_scales.has(icon):
		_warning_icon_base_scales[icon] = icon.get("scale")
	var base_scale = _warning_icon_base_scales.get(icon)
	if base_scale != null:
		var idx = clampi(Game.config_warning_icon_size, 0, WARNING_ICON_SCALE_MULTIPLIERS.size() - 1)
		icon.set("scale", base_scale * WARNING_ICON_SCALE_MULTIPLIERS[idx])

	icon.visible = false
	icon.modulate.a = 0.0
	if _warning_tweens.has(icon) and is_instance_valid(_warning_tweens[icon]):
		_warning_tweens[icon].kill()
		_warning_tweens.erase(icon)

	# 🔧 delay 這段期間如果被 hide_attack_warning() 取消，這個 timer 本身沒辦法被殺掉（SceneTreeTimer 沒有 cancel），
	# 只能靠 token 核對：等它真的 timeout 時，如果這次請求早就作廢了就直接不做事，不然圖示會在毫無預警的狀態下突然彈出來卡住
	_warning_token_counter += 1
	var my_token = _warning_token_counter
	_warning_tokens[icon] = my_token

	var timer = get_tree().create_timer(delay)
	timer.timeout.connect(func():
		if not is_instance_valid(self) or not is_instance_valid(icon): return
		if _warning_tokens.get(icon, -1) != my_token: return
		icon.visible = true
		var tween = create_tween()
		_warning_tweens[icon] = tween
		tween.tween_property(icon, "modulate:a", 1.0, fade_duration).set_trans(Tween.TRANS_SINE)
		if duration > 0.0:
			tween.tween_interval(maxf(duration - fade_duration, 0.0))
			tween.tween_property(icon, "modulate:a", 0.0, fade_duration).set_trans(Tween.TRANS_SINE)
			tween.tween_callback(func():
				if is_instance_valid(icon): icon.visible = false
				_warning_tokens.erase(icon)
			)
	)
	return timer

## 立刻隱藏預警圖示——通常在狀態被打斷/提早結束的 exit() 呼叫
func hide_attack_warning(icon: CanvasItem) -> void:
	if is_instance_valid(icon):
		_warning_tokens.erase(icon)
		if _warning_tweens.has(icon) and is_instance_valid(_warning_tweens[icon]):
			_warning_tweens[icon].kill()
			_warning_tweens.erase(icon)
		icon.visible = false
		icon.modulate.a = 0.0

# ==========================================
# ⚔️ 統一受擊與癱瘓入口
# ==========================================
func _on_poise_broken(broken: bool) -> void:
	if broken:
		if CombatManager.has_method("apply_camera_shake"): CombatManager.apply_camera_shake(15.0)

		if graphics: graphics.modulate = Color(2.0, 0.5, 0.5, 1.0)
		var tween = create_tween()
		tween.tween_property(graphics, "modulate", Color.WHITE, 0.5)

		_handle_poise_break_by_tier()

## 破韌後果依階級而定：低階直接死、中階對自己爆大量傷害、高階交給各自既有的癱瘓轉換（這裡不用做事）
func _handle_poise_break_by_tier() -> void:
	match tier:
		Tier.LOW:
			stats.health = 0 ## 直接死，交給各自狀態機下一輪 physics_update 的死亡判定接手
		Tier.MID:
			stats.health -= roundi(stats.max_health * 0.3) ## 佔位比例，之後有實際中階敵人再調
		Tier.HIGH:
			pass ## 交給各敵人自己既有的癱瘓轉換邏輯（例如 BossNaihe 的 Paralyzed），這裡不用做事

# ==========================================
# ⚡ 黃圈彈刀 (格擋判定窗)
# ==========================================
const GUARD_CIRCLE_SCENE = preload("res://Explod/tscn/EnemyGuardCircle.tscn")
const GUARD_BREAK_BURST_SCENE = preload("res://Explod/tscn/GuardBreakBurst.tscn")

var is_guard_window_open: bool = false
var _guard_window_active: bool = false
var _guard_circle_vfx: Node2D = null

## 開啟一段「黃圈彈刀」判定窗：duration 秒內都能被 breaks_guard 攻擊命中破解，沒有前搖，一開就能破。
## 🔧 這裡不再自己 grant/clear_hyper_armor()：霸體交給呼叫端整段攻擊狀態的 enter_attack_state()/exit_attack_state()
## 管，不然這裡的計時器一到就 clear，會比攻擊狀態本身還早結束霸體，變成攻擊後段突然掉霸體的破綻
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
	if is_invincible: return # 敵人無敵：完全無視這次攻擊，沒有傷害、沒有硬直、沒有削韌

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
	
	# --- 4. 霸體判定：只免硬直/擊退，不分攻擊種類，也不減傷 ---
	if is_hyper_armored:
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

## 通用流血 DOT：間隔固定時間造成 N 次傷害，不觸發受擊硬直/擊退/白光，純粹掉血。
## 放在 Enemy.gd 讓任何敵人都能直接被任何武器/技能呼叫，不用各自刻一份。
## 用 CombatManager.get_skill_timer()（真實時間、不受 Engine.time_scale 影響）而不是 get_tree().create_timer()，
## 跟專案裡其他戰鬥計時器同一套慣例
func apply_bleed(damage_per_tick: int, ticks: int, interval: float) -> void:
	for i in range(ticks):
		CombatManager.get_skill_timer(interval * (i + 1)).timeout.connect(_on_bleed_tick.bind(damage_per_tick))

func _on_bleed_tick(damage_per_tick: int) -> void:
	if stats == null or stats.health <= 0: return
	stats.health -= damage_per_tick
	if CombatManager.has_method("spawn_damage_number"):
		CombatManager.spawn_damage_number(damage_per_tick, global_position + Vector2(0, -30), false)

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

	# 🔧 本體 Sprite2D 交給即時解析（見 _resolve_main_sprite_material()），不再自己快照，
	# 避免跟霸體輪廓系統搶著把「舊材質」寫回去、結果卡在錯的材質上
	_is_flashing = true
	_refresh_main_sprite_material()
	# 其餘子節點（武器特效等）維持原本快照式做法——輪廓系統不會碰它們，沒有搶寫問題
	_apply_flash_material(graphics)

	var timer = CombatManager.get_skill_timer(0.08)
	_flash_timer = timer
	timer.timeout.connect(func():
		if is_instance_valid(self) and _flash_timer == timer:
			_is_flashing = false
			_refresh_main_sprite_material()
			_restore_original_materials(graphics)
	)

## 本體 Sprite2D 由 _refresh_main_sprite_material() 統一處理；WarningIcon 這類輔助 VFX（不是角色本體，
## 有自己的淡入淡出 tween）也要排除，不然被打中時它會被硬套上白閃材質，把驚嘆號的顯示/淡出攪亂
func _is_flash_excluded(node: Node) -> bool:
	return node == graphics.get_node_or_null("Sprite2D") or node.name == "WarningIcon"

func _apply_flash_material(node: Node) -> void:
	if _is_flash_excluded(node):
		pass
	elif node is Sprite2D or node is AnimatedSprite2D or node is Polygon2D:
		if not _original_materials.has(node): _original_materials[node] = node.material
		node.material = _flash_mat
	for child in node.get_children(): _apply_flash_material(child)

func _restore_original_materials(node: Node) -> void:
	if _is_flash_excluded(node):
		pass
	elif node is Sprite2D or node is AnimatedSprite2D or node is Polygon2D:
		if _original_materials.has(node):
			node.material = _original_materials[node]
			_original_materials.erase(node)
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
