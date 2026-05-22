class_name Teleporter # 門
extends Area2D # 🌟 改為直接繼承 Area2D，拋棄按鍵互動與提示圖示

@export_file("*.tscn") var path: String # 設置新地圖
@export var entry_point: String         # 設置入口位置

func _ready() -> void:
	# 🌟 初始化：連接碰撞訊號
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	# 🌟 安全牆防護：只有「玩家」肉身踩到才傳送，怪物或武器判定框踩到直接無視
	if body is Player:
		# 防呆確認：必須配置了新地圖路徑，且全域目前沒有在轉場中，才放行傳送
		if path != "" and not Game.is_transitioning:
			print("🚪 [傳送門] 玩家進入範圍，啟動自動傳送！目標點: ", entry_point)
			Game.change_scene(path, {"entry_point": entry_point})
