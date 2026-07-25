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

## 每張場地各自的鏡頭縮放範圍——原本這三個數字寫死在 VsCamera.gd（Camera2D
## 節點本身，vs_world.tscn 唯一一份，不分地圖），跟 camera_limit_* 不對稱
## （camera_limit_* 從一開始就是每張場地各自設定）。現在比照 camera_limit_*
## 的做法搬到這裡：vs_world._spawn_arena() 掛完場地後把這三個值寫回
## VsCamera 對應的 @export 欄位，覆蓋掉 VsCamera.gd 上的預設值——想讓某張
## 地圖鏡頭拉更開/更近，直接改這裡，不用去動 vs_world.tscn 裡的 Camera2D 節點。
## 預設值跟 VsCamera.gd 原本寫死的數字一致，所以沒調過的地圖（Sunnyland/
## ExperimentSpace）行為完全不變。
@export_group("鏡頭縮放範圍")
@export var zoom_min:    float  = 0.6    ## 兩人距離很遠時，鏡頭最多拉多開
@export var zoom_max:    float  = 1.2    ## 兩人距離很近時，鏡頭最多拉多近
@export var zoom_margin: Vector2 = Vector2(300.0, 300.0)   ## 距離之外多留的空間，越大鏡頭越早開始往外拉

## 每張場地固定配一首 BGM——沿用主遊戲既有的 AudioManager.play_bgm()/stop_bgm()
## 機制（Worlds/world.gd::level_bgm 同款做法），不是 VsMods 另開一套。留空
## （null）代表這張地圖暫時沒有配樂，vs_world._spawn_arena() 會跳過不播放。
@export_group("音效設定")
@export var arena_bgm:   AudioStream
@export var bgm_volume:  float = -10.0
