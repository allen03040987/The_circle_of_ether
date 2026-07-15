## VsState — VsMods 狀態基底
## 所有 VS 玩家狀態繼承此類別。
## physics_update 回傳下一個狀態名（空字串 = 維持當前狀態）。
class_name VsState
extends Node

var player: CharacterBody2D   # 實際型別為 VsPlayer，用 CharacterBody2D 避免循環依賴
var state_machine: VsStateMachine

func enter(_prev: StringName) -> void: pass
func exit() -> void: pass
func physics_update(_delta: float, _input: InputState) -> StringName:
	return &""

# ── Rollback 介面（子類依需要覆寫）──────────────────────────────────────────
func save_state() -> Dictionary: return {}
func restore_state(_d: Dictionary) -> void: pass
func sync_anim() -> void: pass
