extends CanvasLayer

@onready var boss: BossNaihe = get_parent()
@onready var health_bar: TextureProgressBar = $V/HealthBar
@onready var poise_bar: TextureProgressBar = $V/PoiseBar

# ==========================================
# ⚙️ 初始化與訊號綁定
# ==========================================
func _ready() -> void:
	hide()
	await boss.ready
	
	if boss.stats:
		# 初始化血量
		health_bar.max_value = boss.stats.max_health
		health_bar.value = boss.stats.health
		boss.stats.health_changed.connect(_update_health)
		
		# 初始化韌性
		poise_bar.max_value = boss.stats.max_poise
		poise_bar.value = boss.stats.poise
		boss.stats.poise_changed.connect(_update_poise)
		boss.stats.poise_broken.connect(_on_poise_broken)
		
# ==========================================
# 🔄 數值更新邏輯
# ==========================================
func _update_health() -> void:
	if boss.stats:
		var tween = create_tween()
		tween.tween_property(health_bar, "value", boss.stats.health, 0.2).set_trans(Tween.TRANS_SINE)
		
		# 🌟 核心修復：如果血量歸零，立刻觸發血條淡出消失！
		if boss.stats.health <= 0:
			hide_boss_bar()
			
func _update_poise() -> void:
	poise_bar.value = boss.stats.poise

func _on_poise_broken(broken: bool) -> void:
	if broken:
		poise_bar.tint_progress = Color.GRAY
	else:
		poise_bar.tint_progress = Color.YELLOW 
		
# ==========================================
# 🎬 視覺演出接口
# ==========================================
func show_boss_bar() -> void:
	show() 
	
	var ui_container = $V 
	ui_container.modulate.a = 0.0
	
	var tween = create_tween()
	tween.tween_property(ui_container, "modulate:a", 1.0, 1.0)

# 🌟 新增：BOSS 死亡時的優雅退場
func hide_boss_bar() -> void:
	var ui_container = $V 
	var tween = create_tween()
	# 花 1 秒鐘慢慢變透明
	tween.tween_property(ui_container, "modulate:a", 0.0, 1.0)
	# 變透明後徹底隱藏，不佔用資源
	tween.tween_callback(hide)
	
