class_name VsCamera
extends Camera2D

var target_p1: Node2D
var target_p2: Node2D

## 附身血影時（Asatsubaki）額外要一起入鏡的點——target_p1/p2 這時已經換成
## 血影本身，角色本體停在原地不再被 target_p1/p2 代表，若不額外補上就會被
## 鏡頭排除在外。沒有附身時維持 null，取景數學退化成跟原本完全一樣（見
## _physics_process() 的邊界框計算，2 點時 bounding box 中點/跨距等價於
## 原本的兩點連線中點/差值，不影響既有調好的鏡頭手感）。純視覺、不進快照，
## 由 vs_world._process() 每幀設定。
var target_p1_extra: Node2D = null
var target_p2_extra: Node2D = null

var shake_intensity: float = 0.0
var shake_timer: float = 0.0

# 特寫記憶體
var cinematic_timer: float = 0.0
var cinematic_target: Node2D = null
var cinematic_target_zoom: float = 1.0

@export_group("🎥 運鏡縮放設定")
@export var min_zoom: float = 0.6
@export var max_zoom: float = 1.2
@export var margin: Vector2 = Vector2(300.0, 300.0)

# 🌟 【折中修改區】
@export var follow_speed_x: float = 6.0  # 水平稍微降速，增加電影滑順感
@export var follow_speed_y: float = 10.0  # 🌟 垂直速度暴降！解決頭暈的關鍵！讓它用「飄」的上去
@export var zoom_speed: float = 4.0      # 🌟 稍微加快縮放速度，靠拉遠鏡頭來防止人物出框！

@export var cinematic_offset: Vector2 = Vector2(0.0, -50.0)
var is_in_cinematic: bool = false

func _ready() -> void:
	add_to_group("camera")
	position_smoothing_enabled = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func _physics_process(delta: float) -> void:
	if target_p1 != null and target_p2 != null:

		# ==========================================
		# 1. 🎬 電影特寫模式
		# ==========================================
		if is_in_cinematic:
			# cinematic_timer 倒數：歸零就自動退出特寫，交還給下面的一般立回模式
			# 接管（這個計時器原本只宣告沒用到，特寫永遠不會自動結束，是死碼）
			cinematic_timer -= delta
			if cinematic_timer <= 0.0:
				is_in_cinematic = false
			else:
				var target_pos = cinematic_target.global_position + cinematic_offset
				global_position = global_position.lerp(target_pos, 15.0 * delta)

				var final_zoom = lerp(zoom.x, cinematic_target_zoom, 10.0 * delta)
				final_zoom = max(0.1, final_zoom)
				zoom = Vector2(final_zoom, final_zoom)

		# ==========================================
		# 2. ⚔️ 一般立回模式 (海陸空全域智慧縮放)
		# ==========================================
		else:
			# --- A. 雙軸分離追蹤 (極致平滑化) ---
			# 收集這一幀所有「必須入鏡」的點，用邊界框取中點/跨距，取代原本
			# 寫死兩點的版本——正常情況只有 target_p1/target_p2 兩點，數學上
			# min+max == 兩點相加，跟原本的兩點平均/差值完全等價；血影附身
			# 時 extra 補上本體位置，鏡頭才會把本體也包進取景範圍，不會因為
			# target_p1/p2 換成血影就把本體排除在外。
			var points: Array[Vector2] = [target_p1.global_position, target_p2.global_position]
			if target_p1_extra != null: points.append(target_p1_extra.global_position)
			if target_p2_extra != null: points.append(target_p2_extra.global_position)

			var min_pt := points[0]
			var max_pt := points[0]
			for pt in points:
				min_pt.x = minf(min_pt.x, pt.x)
				min_pt.y = minf(min_pt.y, pt.y)
				max_pt.x = maxf(max_pt.x, pt.x)
				max_pt.y = maxf(max_pt.y, pt.y)

			var midpoint = (min_pt + max_pt) / 2.0
			var target_pos = Vector2(midpoint.x, midpoint.y - 50.0)

			# 🌟 使用較為柔和的 lerp 速度
			global_position.x = lerp(global_position.x, target_pos.x, follow_speed_x * delta)
			global_position.y = lerp(global_position.y, target_pos.y, follow_speed_y * delta)

			# --- B. 2D 邊界智慧縮放 ---
			var dist_x = max_pt.x - min_pt.x
			var dist_y = max_pt.y - min_pt.y

			var screen_size = get_viewport_rect().size

			var zoom_x = screen_size.x / (dist_x + margin.x)
			var zoom_y = screen_size.y / (dist_y + margin.y)

			var target_zoom_value = min(zoom_x, zoom_y)
			target_zoom_value = clamp(target_zoom_value, min_zoom, max_zoom)

			# 🌟 讓縮放承擔「把人物包在畫面裡」的責任，而不是靠鏡頭上下狂追
			var final_zoom = lerp(zoom.x, target_zoom_value, zoom_speed * delta)
			zoom = Vector2(final_zoom, final_zoom)

	# ==========================================
	# 3. 💥 螢幕震動邏輯
	# ==========================================
	if shake_timer > 0:
		shake_timer -= delta
		offset = Vector2(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity)
		)
		shake_intensity = lerp(shake_intensity, 0.0, 5.0 * delta)
	else:
		offset = Vector2.ZERO

func shake(intensity: float, duration: float) -> void:
	shake_intensity = intensity
	shake_timer = duration

# ==========================================
# 🎬 特寫控制器
# ==========================================
## 觸發電影特寫：鏡頭拉近盯著 target，維持 duration 秒後（cinematic_timer 倒數
## 到 0）自動交還給一般立回模式，不用另外呼叫任何「結束特寫」的函式。
func cinematic_zoom(target: Node2D, target_zoom: float, duration: float) -> void:
	if target_zoom <= 1.0:
		is_in_cinematic = false
		return

	cinematic_target = target
	cinematic_target_zoom = target_zoom
	cinematic_timer = duration
	is_in_cinematic = true
