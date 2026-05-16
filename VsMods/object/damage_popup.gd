extends Node2D

var amount: int = 0
var color: Color = Color.WHITE

@onready var label = $Label

func _ready() -> void:
	# 🌟 1. 免疫時停，保證大招 The World 暫停時數字依然能飄出來！
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 🌟 2. 顯示在最上層，絕對不被背景蓋住！
	z_index = 100
	
	# 設定數字與顏色
	label.text = str(amount)
	label.modulate = color
	
	# ==========================================
	# 🌟 3. 動態大小計算 (傷害越大，數字越大)
	# ==========================================
	# 步驟 A：計算比例 t (0.0 到 1.0)。
	# 如果傷害 <= 50，t 就是 0.0；如果傷害 >= 1000，t 就是 1.0。
	var t = clamp((float(amount) - 50.0) / (1000.0 - 50.0), 0.0, 1.0)
	
	# 步驟 B：根據比例 t，在最小縮放 (0.6倍) 與最大縮放 (1.8倍) 之間取值。
	# 你可以自由微調這兩個數字 (0.6 和 1.8) 來決定字體大小的極限！
	var final_scale = lerp(0.6, 1.8, t)
	
	# 步驟 C：初始瞬間稍微放大 1.5 倍，準備用 Tween 做彈出效果
	scale = Vector2(final_scale * 1.5, final_scale * 1.5)
	
	# ==========================================
	
	# 4. 加入淺淺左右隨機元素 (正負 15 像素隨機飄)
	var random_x_offset = randf_range(-15.0, 15.0)
	position.x += random_x_offset
	
	# 5. 建立 Tween 動畫 (並行播放)
	var tween = create_tween().set_parallel(true)
	
	# 💥 數字彈出效果：0.15 秒內，從初始的誇張大小，彈性縮回計算好的 final_scale！
	tween.tween_property(self, "scale", Vector2(final_scale, final_scale), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	# 往上飄 50 像素，花費 0.8 秒，使用減速效果(Ease Out)
	tween.tween_property(self, "position:y", position.y - 50.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# 透明度變成 0，花費 0.8 秒，使用加速效果(Ease In)
	tween.tween_property(self, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	
	# 動畫結束後，自動把自己刪除 (串接在並行任務之後)
	tween.chain().tween_callback(queue_free)
