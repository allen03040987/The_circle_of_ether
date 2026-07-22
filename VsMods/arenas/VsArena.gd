class_name VsArena
extends Node2D
## 場地根節點共用基底。vs_world.gd 在 _spawn_arena() 依
## VsGameManager.selected_arena_id 動態 instantiate 一份掛進 $ArenaRoot，
## 讀這裡的 camera_limit_* 設回 Camera2D。P1/P2 重生點固定用子節點
## SpawnPoint_P1/SpawnPoint_P2（Marker2D）——位置本來就該在編輯器裡可視化調，
## 不用另外包成 @export 數值。

@export var camera_limit_left:   float = -240
@export var camera_limit_right:  float = 730
@export var camera_limit_bottom: float = 300
