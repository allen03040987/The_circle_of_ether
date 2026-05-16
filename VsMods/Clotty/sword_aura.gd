extends Area2D
class_name SwordAura

# ==========================================
# 🌟 軌跡模式選單 (會在 Inspector 變成下拉選單)
# ==========================================
enum TrajectoryType { STRAIGHT, SINE_WAVE, SQUARE }
@export var trajectory: TrajectoryType = TrajectoryType.STRAIGHT

@export var speed: float = 800.0
@export var max_lifetime: float = 3.0

# --- 〰️ 上下曲線 (Sine Wave) 專用參數 ---
@export_group("〰️ 曲線參數")
@export var wave_amplitude: float = 100.0 # 上下起伏的高度 (振幅)
@export var wave_frequency: float = 15.0  # 扭動的速度 (頻率)

# --- 🔲 正方形 (Square) 專用參數 ---
@export_group("🔲 正方形參數")
@export var square_side_time: float = 0.2 # 正方形每條邊飛多久才轉彎 (秒)


# 🌟 新增：讓劍氣認識發射它的老爸
var owner_player: Node2D = null 

var direction: float = 1.0
var time_passed: float = 0.0
var start_y: float = 0.0
var current_phase: int = 0

func _ready() -> void:
	$Sprite2D.scale.x = direction 
	# start_y 交給老爸去設定了，這裡不用管！
	
	var hitbox = get_node_or_null("VsHitbox")
	if hitbox:
		print("✅ [", self.name, "] 成功降落！傷害：", hitbox.damage)
		
	# 🌟 防秒殺機制：如果編輯器不小心設成 0，強制給它 3 秒壽命！
	if max_lifetime <= 0.0:
		max_lifetime = 3.0
		
	
	

func _physics_process(delta: float) -> void:
	# 🌟 核心：偷取老爸的時空倍率！
	var time_scale = 1.0
	if owner_player != null and "custom_time_scale" in owner_player:
		time_scale = owner_player.custom_time_scale
		
	var real_delta = delta * time_scale 
	time_passed += real_delta
	
	# ==========================================
	# 💀 壽命終結判定 (完美配合時停與緩速！)
	# ==========================================
	# 因為 time_passed 只在時間有流動時才會增加，
	# 所以如果在時停期間，劍氣的壽命絕對不會減少！
	if time_passed >= max_lifetime:
		queue_free()
		return # 壽命到了就直接退出，不用再算下面的位移了
	
	match trajectory:
		TrajectoryType.STRAIGHT:
			position.x += speed * direction * real_delta # 🌟 改用 real_delta
			
		TrajectoryType.SINE_WAVE:
			position.x += speed * direction * real_delta # 🌟 改用 real_delta
			position.y = start_y + sin(time_passed * wave_frequency) * wave_amplitude
			
		TrajectoryType.SQUARE:
			current_phase = int(time_passed / square_side_time) % 4
			
			if current_phase == 0:
				position.x += speed * direction * real_delta 
			elif current_phase == 1:
				position.y += speed * real_delta 
			elif current_phase == 2:
				position.x -= speed * direction * real_delta 
			elif current_phase == 3:
				position.y -= speed * real_delta
