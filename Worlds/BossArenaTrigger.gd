extends Area2D

@export var boss: BossNaihe
@export var arena_door: StaticBody2D 

# ==========================================
# ⚙️ 初始化
# ==========================================
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	
	# 確保大門初始為開啟狀態 (隱藏視覺 + 關閉碰撞)
	if arena_door:
		arena_door.modulate.a = 0.0 
		var shape = arena_door.get_node_or_null("CollisionShape2D")
		if shape:
			shape.disabled = true

# ==========================================
# 🛑 玩家進入判定
# ==========================================
func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		# 🌟 1. 關閉觸發器本身的偵測，防止戰鬥中反覆觸發
		set_deferred("monitoring", false)
		
		# 2. 喚醒 BOSS，並掛上「死亡竊聽器」
		if is_instance_valid(boss):
			if boss.has_method("wake_up"):
				boss.wake_up()
				
			# 🌟 訂閱 BOSS 的死亡事件
			# 如果你的 BOSS 腳本裡有自訂的 signal "died"，就會優先用它
			if boss.has_signal("died"):
				boss.died.connect(_open_door_and_finish)
			else:
				# 萬一沒寫，退而求其次監聽「節點被從場景中移除(queue_free)」的瞬間
				boss.tree_exited.connect(_open_door_and_finish)
				
		# 3. 關閉競技場大門
		if is_instance_valid(arena_door):
			var shape = arena_door.get_node_or_null("CollisionShape2D")
			if shape:
				shape.set_deferred("disabled", false)
				
			var tween = create_tween()
			tween.tween_property(arena_door, "modulate:a", 1.0, 0.5)
			
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(10.0)

		# ⛔ 刪除原本在這裡的 queue_free()！我們還要等 BOSS 死掉！

# ==========================================
# 🔓 BOSS 擊殺後處理 (開門)
# ==========================================
func _open_door_and_finish() -> void:
	print("🎉 [Arena] BOSS 被擊敗！開啟大門！")
	
	if is_instance_valid(arena_door):
		var shape = arena_door.get_node_or_null("CollisionShape2D")
		if shape:
			shape.set_deferred("disabled", true) # 關閉碰撞，讓玩家通過
			
		var tween = create_tween()
		
		
	# 🌟 任務徹底圓滿完成，這時觸發器才可以安心銷毀
	queue_free()
