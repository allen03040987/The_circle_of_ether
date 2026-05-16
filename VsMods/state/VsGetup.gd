class_name VsPlayerGetupState
extends VsPlayerState

## 起身狀態 (Getup State)
## 從倒地狀態 (DownState) 恢復的過渡狀態，包含起身動畫與起身無敵判定。

func enter() -> void:
	# 播放起身動畫
	player.animation.play("get_up") 
	
func process_physics(delta: float) -> VsState:
	super(delta) # 維持重力與基本物理
	
	# 起身動畫播完，才真正回到待機狀態 (恢復操作權限)
	if not player.animation.is_playing():
		player.invincibility_timer = 1.0 # 賦予 1 秒的「起身無敵」，防止被對手無縫壓制 (Oki)
		return state_machine.idle_state
		
	return null
