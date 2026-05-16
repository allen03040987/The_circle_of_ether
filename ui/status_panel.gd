extends HBoxContainer # UI

@export var stats: Stats 

@onready var health_bar: TextureProgressBar = $V/HealthBar
@onready var eased_health_bar: TextureProgressBar = $V/HealthBar/EasedHealthBar
@onready var energy_bar: TextureProgressBar = $V/EnergyBar


# 節點準備好進入場景時執行
func _ready() -> void: 
	if not stats : # 將血量信息從自動載入引用
		stats = Game.player_stats
	
	stats.health_changed.connect(update_health)
	update_health(true)
	
	stats.energy_changed.connect(update_energy)
	update_energy()
	
	# 離開場景時，斷開與stats的聯繫
	tree_exited.connect(func():
		stats.health_changed.disconnect(update_health)
		stats.energy_changed.disconnect(update_energy)
		)
	
# 更新血量邏輯
func update_health(skip_anim := false) -> void :
	var percentage := stats.health / float(stats.max_health) # 計算血量
	health_bar.value = percentage
	
	if skip_anim :  # 判斷是否跳過
		eased_health_bar.value = percentage
	else :	
		# 捕間動畫用於紅色瘀血
		create_tween().tween_property(eased_health_bar,"value",percentage,0.3)
	
# 更新閃避能量邏輯
func update_energy() -> void :
	var percentage := stats.energy / stats.max_energy # 計算血量
	energy_bar.value = percentage
	
