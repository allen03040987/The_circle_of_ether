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
		# 1. 關閉觸發器本身的偵測
		set_deferred("monitoring", false)
		
		# 2. 喚醒 BOSS，並掛上「死亡竊聽器」
		if is_instance_valid(boss):
			if boss.has_method("wake_up"):
				boss.wake_up()
				
			if boss.has_signal("died"):
				boss.died.connect(_open_door_and_finish)
			else:
				boss.tree_exited.connect(_open_door_and_finish)
				
		# 🎵 🌟 新增：踏入戰場，激昂的 Boss 戰 BGM 奏響！
		var boss_music = preload("res://sound/BGM/BossNaihe/SACRED NIGHT ᐸ五丈原の戦いᐳ.wav") 
		AudioManager.play_bgm(boss_music)
		AudioManager.play_bgm(boss_music, -12.0)
		# 3. 關閉競技場大門
		if is_instance_valid(arena_door):
			var shape = arena_door.get_node_or_null("CollisionShape2D")
			if shape:
				shape.set_deferred("disabled", false)
				
			var tween = create_tween()
			tween.tween_property(arena_door, "modulate:a", 1.0, 0.5)
			
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(10.0)

		

# ==========================================
# 🔓 BOSS 擊殺後處理 (開門)
# ==========================================
func _open_door_and_finish() -> void:
	# 🛡️ 終極防護網：如果節點已經不在樹上 (代表玩家正在關閉遊戲)，直接終止，絕對不准報錯！
	if not is_inside_tree(): return 
	
	print("🎉 [Arena] BOSS 被擊敗！開啟大門！")
	
	# 🎵 🌟 戰鬥結束，讓 BGM 在 2.5 秒內優雅地漸出消失！
	AudioManager.stop_bgm(2.5)
	
	if is_instance_valid(arena_door):
		var shape = arena_door.get_node_or_null("CollisionShape2D")
		if shape:
			shape.set_deferred("disabled", true) 
			
		var tween = create_tween()
		tween.tween_property(arena_door, "modulate:a", 0.0, 0.5)
		
	await get_tree().create_timer(0.5).timeout
	queue_free()
