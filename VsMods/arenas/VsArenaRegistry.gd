class_name VsArenaRegistry
## 場地 id → 資料的對照表，跟 VsCharacterRegistry/VsArtRegistry 同一套 pattern
## （純靜態字典，class_name 不掛 autoload）。MapSelectScreen 用 all_ids() 生成
## 選單，vs_world.gd 用 get_scene() 依 VsGameManager.selected_arena_id 動態
## 掛載場地。之後新增場地只需要在這裡加一筆資料 + 一個 Arena_XXX.tscn，不用
## 動 MapSelectScreen/vs_world 的程式碼。

const ARENAS: Dictionary = {
	"Sunnyland": {
		"display_name": "陽光島",   # 暫定名稱，不滿意可直接改這個字串
		"scene_path": "res://VsMods/arenas/Arena_Sunnyland.tscn",
	},
}

const DEFAULT_ARENA := "Sunnyland"

static func get_scene(arena_id: String) -> PackedScene:
	var path: String = ARENAS.get(arena_id, {}).get("scene_path", "")
	return load(path) if path != "" else null

static func get_display_name(arena_id: String) -> String:
	return ARENAS.get(arena_id, {}).get("display_name", arena_id)

static func all_ids() -> Array:
	return ARENAS.keys()
