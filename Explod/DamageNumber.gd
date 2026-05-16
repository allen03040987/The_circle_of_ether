class_name DamageNumber
extends Marker2D

@onready var label: Label = $Label

# 🌟 新增一個變數來儲存 Tween，方便外部修改它的速度
var _my_tween: Tween

func setup(amount: int, is_heavy: bool = false) -> void:
	label.text = str(amount)
	
	# 隨機偏移一點點初始位置，避免多段攻擊的字全疊在一起
	position += Vector2(randf_range(-15.0, 15.0), randf_range(-15.0, 15.0))
	
	# 🌟 重擊特效：字體變大、變色
	if is_heavy:
		scale = Vector2(1.5, 1.5)
		z_index = 10 # 重擊數字顯示在最上層
	else:
		label.modulate = Color.WHITE
		scale = Vector2(1.0, 1.0)
		z_index = 5
		
	# ==========================================
	# 🎬 飄字動畫 (使用 Tween 動態生成)
	# ==========================================
	# 將建立好的 Tween 存入類別變數
	_my_tween = create_tween().set_parallel(true)
	
	# 1. 往上飄 (Y軸減少)
	var target_y = position.y - 40.0
	_my_tween.tween_property(self, "position:y", target_y, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# 2. 漸隱 (Alpha 變 0) - 延遲 0.2 秒才開始變透明
	_my_tween.tween_property(self, "modulate:a", 0.0, 0.4).set_delay(0.2)
	
	# 3. 動畫結束後自我銷毀 (關閉平行模式，讓銷毀在最後發生)
	_my_tween.chain().tween_callback(queue_free)

# ==========================================
# 🛡️ 接收 CombatManager 傳來的抗時停倍率
# ==========================================
func set_anti_timestop_speed(mult: float) -> void:
	if _my_tween and _my_tween.is_valid():
		# 🌟 強制設定 Tween 的播放速度，完美抵銷 Engine.time_scale！
		_my_tween.set_speed_scale(mult)
