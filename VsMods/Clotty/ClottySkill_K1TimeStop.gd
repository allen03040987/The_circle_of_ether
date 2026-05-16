class_name VsHitboxTimeStop
extends VsHitbox

@export_group("🌟 時停大招專屬設定")
@export var final_spark: PackedScene       
@export var final_knockback: Vector2 = Vector2(300, -400) 
@export var final_damage: float = 700.0     
@export var final_shake_intensity: float = 150.0 
@export var final_shake_duration: float = 0.25   

var is_executing: bool = false 

func _ready() -> void:
	super._ready() 
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	# (已拔除剝奪副機判定權的代碼，現在兩邊都是本機實體計算！)
		
	if area is VsHurtbox and area.owner_player != self.owner_player:
		var victim = area.owner_player 
		if victim.invincibility_timer > 0.0 or is_executing: return
		
		is_executing = true 
		owner_player.velocity.x = 0.0
		
		# 第一刀判定 (打出硬直)
		area.take_hit(self, true)

		await get_tree().create_timer(0.01, false, false, true).timeout
		if victim.vs_state_machine.current_state.name == "Guard":
			is_executing = false 
			return 

		# ==========================================
		# 🎬 1. 啟動時停 (直接執行隱身與暫停)
		# ==========================================
		owner_player.set_global_pause(true) 
		var graphics = owner_player.get_node_or_null("Graphics")
		if graphics: graphics.visible = false

		# ==========================================
		# ⚔️ 2. 迴圈連斬與定格飄字 (純單機暴力生成)
		# ==========================================
		var hits = 6
		var interval = 0.5 / hits 
		var damage_per_hit = 200.0 
		
		for i in range(hits):
			var base_pos = area.global_position
			var p_spark_offset = Vector2(randf_range(-60, 60), randf_range(-80, 20))
			var popup_offset = Vector2(randf_range(-60, 60), randf_range(-120, -40))
			
			# 🌟 A. 生成火花 (取代原本的 rpc_spawn_hit_effects)
			for effect in [hit_effect_1, hit_effect_2]:
				if effect != null:
					var spark = effect.instantiate()
					spark.process_mode = Node.PROCESS_MODE_ALWAYS 
					spark.rotation = randf_range(0, PI * 2)
					spark.scale = Vector2.ONE * randf_range(0.8, 1.5)
					spark.global_position = base_pos + p_spark_offset
					get_tree().current_scene.add_child(spark)

			# 🌟 B. 生成定格飄字
			if owner_player.damage_popup_scene != null:
				var popup = owner_player.damage_popup_scene.instantiate()
				popup.amount = int(damage_per_hit)
				popup.global_position = base_pos + popup_offset
				get_tree().current_scene.add_child(popup)
				popup.process_mode = Node.PROCESS_MODE_PAUSABLE

			# 🌟 C. 真實扣血邏輯
			victim.take_damage(damage_per_hit)
				
			await get_tree().create_timer(interval, true, false, true).timeout

		# ==========================================
		# 💥 3. 解除時停、退回鏡頭、最後大地震
		# ==========================================
		var orig_eff1 = hit_effect_1
		var orig_eff2 = hit_effect_2
		damage = final_damage
		ground_knockback = final_knockback
		air_knockback = final_knockback
		if final_spark != null: 
			hit_effect_1 = final_spark 
			hit_effect_2 = null

		# 🌟 恢復時間流動！
		if graphics: graphics.visible = true
		owner_player.set_global_pause(false)

		# 🌟 本地直接呼叫攝影機退場與震動
		get_tree().call_group("camera", "cinematic_zoom", owner_player, 1.0, 0.2)
		get_tree().call_group("camera", "shake", final_shake_intensity, final_shake_duration)

		# 轟出最後一擊
		area.take_hit(self, true)
		
		hit_effect_1 = orig_eff1
		hit_effect_2 = orig_eff2
		
		await get_tree().create_timer(2.0, false, false, true).timeout
		is_executing = false
