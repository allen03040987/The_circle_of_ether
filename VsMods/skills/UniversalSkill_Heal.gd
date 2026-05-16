class_name UniversalSkill_Heal
extends VsPlayerState

# 預載一個通用的補血特效 (你可以自己做一個綠色光柱的 .tscn)
# 如果還沒做，可以先留空，我們用文字和發光代替！
# var heal_effect = preload("res://Effects/UniversalHealAura.tscn")

var is_healing: bool = false

func enter() -> void:
	is_healing = true
	player.velocity = Vector2.ZERO
	player.auto_face_opponent()
	
	# 🌟 黃金法則 3：播放通用動畫！
	# (請確保刻羅帝跟雙文的動畫編輯器裡，都有一個叫 "skill_universal" 的動畫)
	# (如果現在還沒做，可以先暫時改成 "idle" 或 "crouch" 防崩潰)
	player.play_safe_anim("skill_universal") 
	
	# 暫停角色動作，準備補血
	_sequence_heal()

func _sequence_heal() -> void:
	# ⏳ 詠唱 0.5 秒
	await get_tree().create_timer(0.5, true, false, true).timeout
	if state_machine.current_state != self: return
		
	# 🌟 黃金法則 1：只透過 RPC 操作老爸的變數
	if not multiplayer.has_multiplayer_peer():
		rpc_apply_heal()
	elif multiplayer.is_server():
		rpc("rpc_apply_heal")

	# ⏳ 補血完畢的後搖 0.3 秒
	await get_tree().create_timer(0.3, true, false, true).timeout
	if state_machine.current_state == self:
		is_healing = false

# ==========================================
# 📡 RPC 廣播：所有人一起看綠色爆發特效！
# ==========================================
@rpc("call_local", "authority", "reliable")
func rpc_apply_heal() -> void:
	# 🌟 黃金法則 1：操作通用血量
	player.current_hp = min(player.current_hp + 300.0, player.max_hp)
	player.spawn_damage_text(300, Color.GREEN) 
	
	# 🌟 黃金法則 2：獨立特效 (這裡我們用老爸通用的 Graphics 變色代替)
	# 因為每個角色都有 Graphics 節點裝圖片，所以這樣寫很安全！
	var graphics = player.get_node_or_null("Graphics")
	if graphics:
		var tween = create_tween()
		graphics.modulate = Color(0.3, 2.0, 0.3, 1.0) # 爆發出強烈綠光
		tween.tween_property(graphics, "modulate", Color.WHITE, 0.5)

func process_physics(delta: float) -> VsState:
	# 施法期間會有摩擦力慢慢停下來
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.ground_friction * delta)
	player.custom_move_and_slide()
	
	if not player.animation.is_playing() and not is_healing:
		return state_machine.idle_state
	return null

func exit() -> void:
	is_healing = false
	var graphics = player.get_node_or_null("Graphics")
	if graphics: graphics.modulate = Color.WHITE
