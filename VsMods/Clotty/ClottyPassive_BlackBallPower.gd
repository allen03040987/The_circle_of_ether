class_name ClottyPassive_BlackBallPower
extends VsPlayerState

# ==========================================
# 🔮 被動：黑球之力 (The World 時停特寫版)
# ==========================================
var is_buffing: bool = false

func enter() -> void:
	is_buffing = true
	
	player.velocity = Vector2.ZERO
	player.auto_face_opponent()
	
	player.play_safe_anim("passive")
	player.play_ultimate_cinematic(1.0)
	player.trigger_cinematic_zoom(true, 1.5, 0.2)
	
	_sequence_buff_effects()

func _sequence_buff_effects() -> void:
	await get_tree().create_timer(0.8, true, false, true).timeout
	
	if state_machine.current_state != self:
		return
		
	# 🎲 單機極速抽獎
	var buff_type = randi() % 3 
	_apply_buff(buff_type)

	await get_tree().create_timer(0.2, true, false, true).timeout
	
	if state_machine.current_state == self:
		player.trigger_cinematic_zoom(true, 1.0, 0.15)
		is_buffing = false

# ==========================================
# 🎁 單機 BUFF 執行與發光特效
# ==========================================
func _apply_buff(buff_type: int) -> void:
	var graphics = player.get_node_or_null("Graphics")
	var tween = create_tween()
	
	match buff_type:
		0: # 🩸 0號 (綠色)：回血 400
			player.current_hp = min(player.current_hp + 400.0, player.max_hp)
			player.spawn_damage_text(400, Color.GREEN) 
			if graphics:
				graphics.modulate = Color(0.3, 1.5, 0.3, 1.0) 
				tween.tween_property(graphics, "modulate", Color.WHITE, 0.5)
				
		1: # ⚡ 1號 (黃色)：回滿體力
			player.current_stamina = player.max_stamina
			player.spawn_damage_text(999, Color.YELLOW) 
			if graphics:
				graphics.modulate = Color(1.5, 1.5, 0.3, 1.0) 
				tween.tween_property(graphics, "modulate", Color.WHITE, 0.5)
				
		2: # 🔵 2號 (藍色)：回滿魔力
			player.current_mp = player.max_mp
			player.spawn_damage_text(999, Color.CYAN) 
			if graphics:
				graphics.modulate = Color(0.3, 1.0, 1.5, 1.0) 
				tween.tween_property(graphics, "modulate", Color.WHITE, 0.5)

	player.play_camera_shake(15.0, 0.2)

func process_physics(delta: float) -> VsState:
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.ground_friction * delta)
	player.custom_move_and_slide()
	
	if not player.animation.is_playing() and not is_buffing:
		return state_machine.idle_state
		
	return null

func exit() -> void:
	if is_buffing:
		player.trigger_cinematic_zoom(true, 1.0, 0.2)
		
	is_buffing = false
	
	var graphics = player.get_node_or_null("Graphics")
	if graphics: graphics.modulate = Color.WHITE
