extends Node2D

# ==========================================
# 🔗 節點參考 (Node References)
# ==========================================
@onready var player: Player = owner
@onready var sprite: Sprite2D = $ScabbardSprite 

# ==========================================
# 🎛️ 核心參數 (Properties)
# ==========================================
@export_group("跟隨與起伏設定")
## 理想的跟隨偏移量 (預設是在玩家背後)
@export var follow_offset := Vector2(-50, -35) 
## 追趕速度 (越小越有橡皮筋的拉扯感)
@export var follow_speed := 4.0                
## 上下呼吸的起伏幅度
@export var float_amplitude := 4.0 
## 上下呼吸的頻率
@export var float_frequency := 2.0 
## 轉身時劍鞘甩動過渡的速度
@export var swing_speed := 8.0 

@export_group("殘影特效設定")
## 產生黑煙殘影的時間間隔
@export var ghost_trail_interval := 0.05 

# --- 內部計時與記憶體 ---
var ghost_timer := 0.0
var time_passed := 0.0
var current_tween: Tween
var current_offset := Vector2.ZERO 

# ==========================================
# 📐 圖層常數 (Z-Index)
# ==========================================
const PLAYER_Z_INDEX := 0   # 玩家本體
const SCABBARD_Z_INDEX := 5 # 劍鞘本體 (最前)
const SMOKE_Z_INDEX := 1    # 黑煙殘影 (夾在中間)

# ==========================================
# ⚙️ 初始化與物理更新 (Lifecycle & Physics)
# ==========================================
func _ready() -> void:
	sprite.modulate.a = 0.8
	
	# 獨立飛行與圖層設定
	top_level = true 
	global_position = player.global_position
	current_offset = follow_offset 
	z_index = SCABBARD_Z_INDEX

func _physics_process(delta: float) -> void:
	# 1. 計算目標點與平滑過渡 (獨立 Z 軸)
	var target_offset = follow_offset
	if player.direction == player.Direction.LEFT:
		target_offset.x = -follow_offset.x
	
	# 🧱 爬牆防穿模：提至頭頂
	if player.is_on_wall() and not player.is_on_floor():
		target_offset.x *= 0.3  
		target_offset.y = follow_offset.y - 30.0 
	else:
		target_offset.y = follow_offset.y 
		
	# 向量平滑轉向
	current_offset = current_offset.lerp(target_offset, swing_speed * delta)
	
	# 執行跟隨
	var target_pos = player.global_position + current_offset
	global_position = global_position.lerp(target_pos, follow_speed * delta)
	
	# 2. 上下呼吸起伏
	time_passed += delta
	var y_offset = sin(time_passed * float_frequency) * float_amplitude
	sprite.position.y = y_offset 

	# 3. 處理黑色煙霧殘影 (僅可見時產生)
	if trails_active():
		ghost_timer += delta
		if ghost_timer >= ghost_trail_interval:
			add_ghost_outline()
			ghost_timer = 0.0

# ==========================================
# 🎨 視覺特效與殘影 (VFX & Ghost Trails)
# ==========================================
func trails_active() -> bool:
	return sprite.modulate.a > 0.1 and sprite.texture != null

func add_ghost_outline() -> void:
	if not sprite.texture: return
	
	var ghost := Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.scale = sprite.scale
	
	# 黑煙設定
	ghost.modulate = Color(0, 0, 0, 0.6) 
	ghost.top_level = true
	ghost.global_position = sprite.global_position
	ghost.z_index = SMOKE_Z_INDEX
	
	get_tree().current_scene.add_child(ghost)
	
	# 向上飄散與淡出動畫
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ghost, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(ghost, "global_position:y", ghost.global_position.y - 40.0, 0.5).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_callback(ghost.queue_free)

# ==========================================
# 🎬 顯隱邏輯與動態切換 (Fade In/Out & Switch)
# ==========================================
func fade_out() -> void:
	if current_tween: current_tween.kill() 
	current_tween = create_tween()
	current_tween.tween_property(sprite, "modulate:a", 0.0, 0.1).set_trans(Tween.TRANS_SINE)

func fade_in() -> void:
	if current_tween: current_tween.kill()
	current_tween = create_tween()
	current_tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 0.8), 0.5).set_trans(Tween.TRANS_SINE)

# 🌟 升級版：切換貼圖並觸發閃白特效
func set_scabbard_texture(tex: Texture2D) -> void:
	if sprite.texture == tex: 
		return # 如果貼圖一樣（切換同一把武器），就不重複閃爍
		
	sprite.texture = tex
	
	if current_tween: 
		current_tween.kill()
		
	if tex == null:
		# 如果這把武器沒有劍鞘 (例如空手)，直接隱藏
		sprite.modulate.a = 0.0
		return
		
	# 🌟 閃白特效：瞬間將顏色拉到超亮全白 (利用 RGB > 1 產生發光感)
	sprite.modulate = Color(2.5, 2.5, 2.5, 1.0)
	
	# 利用 Tween 在 0.2 秒內平滑過渡回預設的半透明白
	current_tween = create_tween()
	current_tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 0.8), 0.2).set_trans(Tween.TRANS_SINE)
