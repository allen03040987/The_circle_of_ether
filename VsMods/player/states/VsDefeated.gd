class_name VsDefeated
extends VsPlayerState
## 敗北終局姿勢（硬直死亡專用）
## 進入路徑：VsRoundManager._tick_fighting() 偵測到 hp<=0 時，若當下
## current_state 是 VsHurt（硬直，不是擊飛/已經在倒地流程），直接轉進這裡，
## 完全跳過 VsKnockdown 那整套落地/彈起/起身流程——播死亡動畫 "did" 定格。
## 擊飛死亡走的是另一條路（VsKnockdown 二次落地時偵測 is_defeated，播
## launched_3 停在原地，不會進到這個狀態，見 VsKnockdown.gd）。
##
## defeat_settled："did" 播完（elapsed >= 動畫長度）才設 true，
## VsRoundManager._tick_round_end() 靠這個決定 ROUND_END_DELAY 何時開始倒數
## ——死亡動畫要能完整播完才繼續，不是從偵測死亡那一刻就固定等 2 秒。
##
## ⚠ 使用者要記得在角色的動畫庫（ClottyAnimLib.tres/NaiheAnimLib.tres）
## 加一支叫 "did" 的動畫，沒有這支動畫的話 get_animation() 會回傳 null 導致報錯
## （跟 launched_3 當初的情況一樣）。
##
## 沒有任何轉場出口——停在這裡直到回合重置，VsRoundManager._reset_round()
## 會強制 transition_to(&"vsidle")，不是這個狀態自己處理。

var elapsed:      float = 0.0
var _anim_length: float = 0.0

func enter(_prev: StringName) -> void:
	elapsed = 0.0
	var vs  := player as VsPlayer
	player.velocity = Vector2.ZERO
	vs.defeat_settled = false
	vs.anim_player.play(&"did")
	_anim_length = vs.anim_player.get_animation(&"did").length

func physics_update(delta: float, _input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer
	if elapsed >= _anim_length:
		vs.defeat_settled = true
	# 死亡瞬間可能還在半空中（例如硬直中被擊退到懸空邊緣）——照樣落地貼平，
	# 不要飄在空中，但落地後不再有摩擦漸增之類的講究，直接煞停即可
	if _grounded():
		player.velocity.x = move_toward(player.velocity.x, 0.0, vs.friction * delta)
	else:
		_apply_gravity(delta)
	return &""

func save_state() -> Dictionary:
	return {"elapsed": elapsed}

func restore_state(d: Dictionary) -> void:
	elapsed = d.get("elapsed", 0.0)
	var vs := player as VsPlayer
	if is_instance_valid(vs):
		_anim_length = vs.anim_player.get_animation(&"did").length

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play(&"did")
	vs.anim_player.seek(elapsed, true)
