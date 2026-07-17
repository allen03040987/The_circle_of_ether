# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Communication

The developer communicates in Traditional Chinese (繁體中文) and expects replies in Traditional Chinese by default. Don't switch to English mid-conversation unless explicitly asked to.

## Project Overview

"以太之圓" (The Circle of Ether) — a Godot 4.2 (GL Compatibility renderer) 2D game written in GDScript. The project bundles **two largely independent gameplay systems** in one repo:

- **Main game** — a single-player action game (top-down movement, jump, weapon combat, interact, save stones, bosses).
- **VsMods** — a separate 1v1 versus fighting-game mode (P1/P2 controls, character select, ultimates/skills, stocks/cooldowns).

These two systems do not share a state machine or combat framework — see Architecture below.

## Development

There is no build step, package manager, linter, or test suite in this repo — it's a Godot project edited and run through the Godot 4.2 editor (or `godot` executable/CLI for headless runs). Scenes (`.tscn`) and scripts (`.gd`) are edited together; most gameplay logic lives in `.gd` scripts attached to nodes, so understanding a feature usually requires opening the paired `.tscn` in the editor to see the node tree, not just reading the script.

`project.godot` defines the autoloads, input map, and physics layers — check it when a script references a global (`Game.`, `CombatManager.`, `AudioManager.`, `VsGameManager.`) or an input action (`p1_attack`, `art_1`, `martial_modifier`, etc.) that isn't obviously defined nearby.

## Architecture

### Main game state machine (`classes/`, `player/state/`)

`classes/State.gd` is a minimal contract (`enter()`, `exit()`, `update(delta)`, `physics_update(delta)`, all no-ops by default). `classes/StateMachine.gd` auto-discovers its child `State` nodes into a dict keyed by lowercase node name, injects `player`/`state_machine` back-references, and drives the current state's `update`/`physics_update` each frame. `transition_to(name)` guards against re-entrant transitions. States are wired as child nodes in the Player scene (`player/state/Idle.gd`, `Run.gd`, `Jump.gd`, `Fall.gd`, `Hurt.gd`, `Dying.gd`, `SwapWeapon.gd`, ...).

### Weapon system (`player/`)

`player/Weapon.gd` is the base contract for equippable weapons (`start_light_attack`, `start_heavy_attack`, `get_current_velocity`, `is_attack_finished`, `cancel_attack`, `requires_sheath`, plus a 3-slot "武藝卡帶" special-move system via `martial_slots` / `execute_martial_art(slot)`). Concrete weapons (`Katana.gd`, `Spear.gd`, `Sickle.gd`, `Talisman.gd`) extend `Weapon`.

Combos are **data-table driven, not one-State-per-move**: each weapon defines dictionaries (e.g. `DICT_LIGHT_GROUND`, `DICT_LIGHT_AIR`, `DICT_HEAVY_ULT`) mapping numeric combo-step codes to animation name, hitbox name, damage, knockback, sfx, and action type; an integer `combo_step` drives branching logic in the weapon script itself. Individual `State` subclasses only exist for the broad player states (Idle/Run/Jump/SwapWeapon/...), not for each attack — don't look for a `KatanaAttack1.gd` file, look inside `Katana.gd`'s combo dictionaries.

`MartialArt.gd` is a separate, smaller contract for the special "art" moves (`Art_Katana_1.gd`, etc.) — its own setup/enter/cancel lifecycle, unrelated to `classes/StateMachine.gd`. `ScabbardContainer.gd` handles cosmetic sheath/ghost-trail VFX on weapon swap.

### Input lock (`Player.gd::is_input_locked`)

A single blanket flag meaning "ignore all player input right now," reused for two unrelated purposes with no way to tell them apart from the flag alone: (1) weapon scripts (every weapon's `start_ultimate()`, `Spear.gd`'s `_begin_catch_recovery()` 轉身收槍 前搖) set it during a long committed animation so movement/re-triggering attacks can't interrupt it; (2) `objects/BuildingElevator.gd` sets it for the entire cutscene-like elevator ride as a full freeze — that second case is safe because it also sets `state_machine.process_mode = PROCESS_MODE_DISABLED`, so nothing is left running to consume buffered input anyway.

**Dodge (`slide` action) must always bypass this flag — it's the highest-priority interrupt in the game and is never supposed to be blocked by it.** That exception isn't automatic; it's threaded through by hand at every input-handling site: `Player.gd::_input()`/`_unhandled_input()` both special-case `slide` before the `is_input_locked` early-return/consume, and `WeaponAttack.gd::physics_update()` runs its dodge-cancel check *before* (outside of) the `if not player.is_input_locked:` block, not inside it. If you add a new consumer of `is_input_locked` or a new input-handling entry point, don't assume dodge is automatically exempt — you have to carry the exception over explicitly, the same way these three call sites do.

### VsMods (`VsMods/`)

A fully parallel framework, isolated from `classes/` — do not mix the two. The VsMods was fully rebuilt from scratch; the old character-subclass system no longer exists.

`VsMods/StateMachine/VsStateMachine.gd` extends `Node2D` directly and **auto-discovers child VsState nodes** into a `states` dict keyed by lowercase node name (same discovery pattern as `classes/StateMachine.gd`, but a separate class). `transition_to(name)` has a re-entry guard. A parallel entry point `set_state_quiet(name)` switches `current_state`/`current_state_name` without calling `enter()`/`exit()` — used exclusively during rollback state restoration, never for normal gameplay transitions.

`VsMods/StateMachine/VsState.gd` + `VsPlayerState.gd` — base contracts. `VsPlayerState` provides gravity/move/friction constants and `_apply_gravity(delta)`. `physics_update(delta, input) -> StringName` returns the next state name (empty string = stay); this return-value transition pattern is different from the main game's imperative `transition_to()` calls — don't mix them. Every VsState also exposes `save_state() -> Dictionary` / `restore_state(d)` / `sync_anim()` for rollback; the defaults are no-ops in `VsState.gd`, override only what the state actually needs.

`VsPlayerState`'s `MOVE_SPEED`/`AIR_SPEED` (150/130) and `VsDodge.DODGE_SPEED` (300) are intentionally lower than the main game's `Player.gd` `RUN_SPEED`/dash speed (350/400) — tried matching them 1:1 once, user reverted it (VsMods speed is tuned separately, not meant to mirror the main game's feel). Gravity (980, matches engine default) and jump force (VsMods -420 vs main game -410) are close and not a concern.

`VsMods/player/VsPlayer.gd` (`CharacterBody2D`) — HP/energy/invincibility, `apply_input(delta, input)` driven each frame by `vs_world`. Has `save_state()`/`restore_state()`/`sync_anim_to_state()` for rollback. States live under `VsMods/player/states/` and are all scene children in `VsPlayer.tscn`: `VsIdle`, `VsRun`, `VsJump`, `VsFall`, `VsHurt`, `VsKnockdown`, `VsGetup`, `VsDodge`, `VsGuard`, `VsAttack`.

Scene flow: `title_screen.gd` → `VsMods/ui/LobbyScreen.tscn` (離線/主機/加入) → `VsMods/ui/SelectScreen.tscn` (角色+3 武藝槽選擇) → `VsMods/vs_world.tscn` (戰鬥). `VsGameManager` (autoload, `VsMods/ui/VsGameManager.gd`) caches `p1_arts`/`p2_arts`/`selection_confirmed` across scene changes.

### VsMods rollback netcode (`VsMods/network/`)

`VsNetworkManager` (autoload) drives frame-locked synchronization:

- **Input delay** — `INPUT_DELAY = 4` is actually applied: `_send_frame` starts at `INPUT_DELAY` while `_game_frame` starts at 0, and frames `0..INPUT_DELAY-1` are pre-filled with empty input `[0,0]` on both sides (in `reset_for_match()`/`_reset()`). This means local input collected on tick N executes on frame N+4, giving remote packets ~67ms head start and cutting prediction depth accordingly. OFFLINE mode bypasses the delay entirely (uses the raw current-tick input).
- **`tick(local_input, cs_frame, checksums) -> Array`** — normally returns `[p1_input, p2_input]`, never stalls. Returns `[]` (empty) during the match-sync waiting phase (see below). If confirmed remote input for the current frame hasn't arrived yet, predicts using `_last_remote_input` (last confirmed remote frame) and records the prediction in `_predicted_remote[frame]`. Predictions are kept until confirmed input arrives — do NOT add early-erase logic here, that was the root cause of a previous "silent permanent desync" bug.
- **Input redundancy** — the DataChannel is unordered/no-retransmit, so a lost packet would otherwise leave that frame's remote input permanently unconfirmed (= permanent silent desync; this was a real bug). Every game packet therefore carries the last `INPUT_REDUNDANCY = 10` frames of input (newest→oldest). `_recv_packet` scans them oldest→newest, storing any not-yet-confirmed frame and setting `_pending_rollback_frame` to the earliest mismatch.
- **`_recv_packet()`** — handles three packet kinds: 4-byte forfeit (`0xFFFFFFFF`), 7-byte sync packet (ready-signal only, carries no real input), and variable-length game packet (min 28 bytes): `[u8 seq][u32 frame][u8 n][n×2B inputs][u32 cs_frame][4×u32 cs]`.
- **Checksums are "settled-frame only"** — comparing checksums of frames simulated with *predicted* input would produce false DESYNC reports, so `vs_world` keeps `_cs_history[frame]` (recorded in `_save_snapshot`, auto-corrected during rollback re-simulation) and each tick sends only the checksum of `VsNetworkManager.get_settled_frame()` (= min(last confirmed remote frame, pending-rollback-start − 1, last simulated frame)), tagged with its explicit frame number. `CS_FAIL_LIMIT = 120` consecutive mismatches (~2s) emits `sync_lost` → both sides independently abort the match to the lobby instead of silently playing divergent realities.
- **`_match_seq`** (1 byte, 0–255) — incremented by `reset_for_match()` each new match. Packets with wrong seq are silently discarded, preventing stale DataChannel-buffered packets from a previous match from polluting the new one.
- **Match-sync waiting** — `reset_for_match()` sets `_waiting_for_sync = true`. While true, `tick()` sends a 7-byte sync packet every 10 physics ticks (~6/s) and returns `[]` so vs_world skips simulation entirely. `_waiting_for_sync` clears when the first valid packet from the remote arrives. This guarantees both sides start from frame 0 simultaneously even if one side entered vs_world much earlier.
- Public API for `vs_world`: `needs_rollback()`, `consume_rollback_frame() -> int`, `get_game_frame() -> int`, `get_confirmed_remote_input(frame) -> InputState`, `get_prediction_depth() -> int` (prediction depth in frames ≈ one-way latency; displayed as ms in BattleHUD).

`vs_world.gd` owns rollback execution:

- Every frame: saves snapshot `_frame_states[frame] = {p1_state, p2_state, round_manager_state, inp1, inp2}` before simulating. Keeps only the last `MAX_ROLLBACK_FRAMES = 20` frames.
- When `needs_rollback()`: `_do_rollback(from_frame, cur_frame, cur_inputs)` — restores the nearest snapshot at or before `from_frame`, re-simulates each frame using `get_confirmed_remote_input()` to override stored remote predictions, then simulates the current frame.
- **`is_resimulating`** flag — set `true` during re-simulation so `_on_round_ended`/`_on_round_started`/`_on_match_ended` signal handlers skip HUD updates.
- After rollback completes, `sync_anim_to_state()` on both players re-syncs `AnimationPlayer` to the restored state.
- **Hit detection** — done exclusively by `_manual_check()` in `_check_manual_hits()`, never via Area2D overlap signals (which don't fire during re-simulation). `VsHitbox.has_hit` is saved in every snapshot to prevent a hit from being re-applied when rollback re-runs the same attack window.
- **Checksums** — `_compute_checksums()` hashes position, velocity, hp/energy/round-manager-state, and player state names into 4 independent u32 values sent with every packet. Divergence is logged as `⚠ DESYNC frame N: 欄位` and shown in BattleHUD. Desync alone does NOT kick players; only exceeding the rollback window triggers `_on_hard_desync()`.

**Signaling server** (`server/signaling_server.py`) — deployed at `wss://the-circle-of-ether-signal.onrender.com` (Render.com free tier, `server/requirements.txt` in subdirectory — Render Build Command must be `pip install -r server/requirements.txt`). Do **not** use `websockets ≥ 14.x` type annotations (`WebSocketServerProtocol` was removed). The `"arts"` message type is relay-only (server passes it through unchanged like `"offer"`/`"answer"`/`"ice"`). Room code is currently **1 character** (set in `_new_code()` with `k=1`) for easier testing; change `k` to restore longer codes for production.

### VsMods rollback 確定性規則

Rollback netcode 的正確性完全依賴「兩端從相同初始狀態 + 相同輸入序列，必定算出完全相同的結果」。任何非確定性行為都會造成無法修復的 desync。**在 `_simulate_frame` 的呼叫鏈內（包含 VsState、VsPlayer、VsRoundManager 的所有邏輯），嚴禁以下用法：**

| 禁止 | 原因 |
|---|---|
| `randf()` / `randi()` / `RandomNumberGenerator` 未共享種子 | 兩端產生不同亂數序列 |
| `Time.get_ticks_msec()` / `Time.get_unix_time_from_system()` | 兩台機器的真實時間不同 |
| `get_physics_process_delta_time()` / `Engine.get_physics_interpolation_fraction()` | 實際物理幀時間會因機器效能而漂移 |
| `Engine.time_scale` 影響的 `Timer` 節點 | VsMods 不用 `Engine.time_scale`，但若未來改動要特別注意 |
| Area2D 的 `body_entered` / `area_entered` 信號 | 信號在 `_physics_process` 內不會因幀內幾何計算而觸發，rollback 中間幀偵測不到 |
| `move_and_slide()` / `is_on_floor()` | `move_and_slide` 內部有「上一幀是否在地面」的隱藏記憶（地面吸附用），快照還原無法還原它 → 重模擬的移動結果與直跑不同（實測：一邊多施一次重力，y 永久分歧）。移動一律走 `VsPlayer._move_deterministic()`（無狀態的 `move_and_collide` + 顯式 motion 向量）；地面判定一律讀 `VsPlayer.grounded`（`test_move` 純位置查詢、隨快照保存），states 透過 `VsPlayerState._grounded()` 讀取 |
| `global_position` / `global_transform` | scene tree 的 transform 快取在 rollback 重模擬中不保證更新。模擬邏輯一律用 `position`（vs_world 直屬子節點兩者等值）；hitbox 來源方向用 `VsHitbox.owner_player.position` |
| AnimationPlayer 用真實時間播放 gameplay 軌道 | `VsPlayer.tscn` 的 AnimationPlayer 是 **MANUAL 模式**，由 `apply_input()` 以模擬 delta `advance()` 推進——所以攻擊動畫的 `.:can_combo` / `Graphics/VsHitbox:monitoring` 軌道值是模擬時間的純函數，可以安全參與判定（設計時間點請直接調動畫軌道，別在程式碼裡排程）。`restore_state()` 結尾 `sync_anim_to_state()` 重新對齊動畫時間，重模擬才會重跑軌道 key。若改回 PHYSICS/IDLE 播放模式，軌道值就會脫離模擬時間 → desync。非戰鬥階段（回合結算）玩家不被模擬，`vs_world._simulate_frame` 有純外觀的 advance 防止畫面凍住 |
| Call Method 動畫軌道不加防呆，或 `callback_mode_method` 留在預設值 | 「值」軌道（`can_combo`/`hitbox monitoring`）被 `sync_anim_to_state()` 的 `seek(elapsed, true)` 重複套用是無害的（冪等）；但 Call Method 軌道（例如 `strike_impulse`）每次真的被觸發都會執行一次有副作用的呼叫，不是冪等的。**兩個必要條件缺一不可：**(1) `AnimationMixer.callback_mode_method` 預設是 `ANIMATION_CALLBACK_MODE_METHOD_DEFERRED`（延遲執行）——真正呼叫的時機是 `call_deferred()` 排到這一幀稍後，不是 `advance()`/`seek()` 呼叫的當下；rollback 重模擬同一真實影格內會連續呼叫多次 `advance()`，若都排到延遲佇列，執行次數/順序不保證對應各自的模擬幀，直接破壞確定性——`VsPlayer._ready()` 必須設成 `ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE`。(2) 即使呼叫已經是即時的，`seek(..., true)` 做 rollback 視覺 resync 時仍可能回放沿途經過的 Call Method key（把已經是正確模擬結果的狀態再蓋一次）——`VsPlayer._resyncing_anim` 旗標防呆（`sync_anim_to_state()` 呼叫期間設 true，方法開頭檢查為 true 就跳過）。實測：只做 (2) 沒做 (1) 完全沒用（guard 早被重置才真的觸發），log 出現 `velocity=(-554.17,0)` 這種只有 `strike_impulse` 直接寫入才會有的異常值。之後新增任何 Call Method 軌道都要同時滿足這兩個條件 |

**正確做法：** 所有模擬邏輯用傳入的 `delta`（在 vs_world 中永遠是 `PHYS_DELTA = 1.0 / 60.0`）驅動。若未來需要亂數（例如角色特技的隨機效果），必須使用兩端共享的固定種子 `RandomNumberGenerator`，種子通過輸入或封包傳遞，不可各自獨立初始化。

### VsMods InputState (`VsMods/network/InputState.gd`)

2 bytes 序列化，所有欄位如下：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `move_dir` | float | −1.0 左 / 0.0 中立 / 1.0 右 |
| `is_crouch` | bool | 蹲下 |
| `jump` | bool | just_pressed |
| `attack` | bool | 普攻 just_pressed |
| `skill` | bool | 技能 just_pressed |
| `art_1/2/3` | bool | 武藝 1/2/3 just_pressed |
| `dodge` | bool | 閃避 just_pressed |
| `guard` | bool | 防禦 pressed（長按） |

**P1 操作特殊**：普攻/技能 = 無修飾左/右鍵；武藝 = E（`martial_modifier`）+ 左/右/中鍵。P2 純鍵盤，無修飾鍵。

### VsMods 體質效果與能量系統（已實作）

- **`VsPlayer.ArmorTier { NONE, HYPER, STRONG_HYPER }`** — 衍生值，`get_armor_tier()` 由當前狀態即時計算（`VsGuard` 狀態或 `post_dash_armor_left > 0` → STRONG_HYPER），**不獨立儲存**，所以不需要進快照。
- **`VsHitbox.BreakLevel { NONE, ARMOR_BREAK, STRONG_ARMOR_BREAK }`** — 取代舊的 `guard_break: bool`。判定矩陣在 `VsPlayer._on_hurtbox_hurt()`：STRONG_HYPER 免疫非強破霸的硬直/擊退並 50% 減傷（強破霸攻擊完整生效）；HYPER 免疫非破霸硬直（無減傷）。
- **雙能量池**：`dash_energy`（上限 100，永遠 10/s 回復，衝刺一次耗 30）與 `arts_energy`（上限 50，脫戰 2 秒後 10/s 回復；`out_of_combat_left` 是 float 計時、不用 Timer 節點）。HUD 各畫一條（金色=武藝、青色=衝刺）。
- **衝刺（`VsDodge`）**：前 0.3s 完美閃避判定窗；期間 `velocity.y = 0`（無重力）。結束後 2 秒強霸體（`post_dash_armor_left = 2.0`）**必須同時滿足**：`_completed`（正常走完，非被擊中打斷）**且** `_perfect_used`（前 0.3s 真的被打中觸發過完美閃避）——沒被打到的衝刺不給強霸體，這是規則明寫的，別誤改成走完就給。
- **防禦（`VsGuard`）**：即強霸體。普通攻擊 50% 傷害、無擊退硬直；`STRONG_ARMOR_BREAK` 破防 → 完整 `pending_hit` 流程進 VsHurt。
- 受擊方向（擊退的 dir_x）一律從 **`VsHitbox.owner_player.facing_dir`**（攻擊者當下面向）計算，不是兩者相對座標——與主遊戲 `classes/Hitbox.gd` 的 `attacker_dir` 同款慣例，`knockback.x` 為正值 = 「往攻擊者面向那側推開」。`owner_player` 由 `VsPlayer._ready()` 對所有 hitbox 設定，見確定性規則表的 `global_position` 條目（不用 `.position` 是因為算相對座標會依兩人左右位置而正負顛倒——同樣正值卻一下前一下後的 bug 曾發生過，別改回相對座標算法）。

### VsMods rollback 除錯工具

- 每場進 vs_world 會寫 `user://vs_session_p<本機id>.txt`（路徑與設定資訊），DESYNC 事件**即時附加**到 `user://desync_log_p<本機id>.txt` —— 按本機玩家 id 分檔，因為同一台電腦開兩個實例測試時共用 `user://`，不分檔會互相交錯。每場開頭寫 `═══ 場次開始 <時間戳> ═══` 分隔線；附加模式，最上方=最舊。
- desync log 每筆含：偵測當下即時狀態、**分歧幀的封存快照**（雙方 pos/vel/state）、該幀雙方輸入（hex）、預測深度、近期 rollback 記錄（`VsNetworkManager.get_recent_rollbacks()`）。診斷方法：兩台機器對照**同一幀號**的區塊——輸入 hex 不同 = 傳輸層 bug；輸入相同但快照不同 = 模擬層非確定性（可直接從數值差反推，例：vel.y 差 980/60 = 差一次重力）。
- 延遲容量：`INPUT_DELAY 4 + MAX_ROLLBACK_FRAMES 20 ≈ 400ms 單向上限`；超過時 `_do_rollback` 找不到快照 → hard desync 踢回大廳，**這是設計行為不是 bug**（那種延遲下也不可玩）。實測：Clumsy 50ms 整場穩定、零 checksum 分歧；200ms（本機雙實例下實際 ≈400ms）觸發回滾窗保護。

### VsMods 打擊回饋 VFX（震動/火花/殘影）

直接沿用主遊戲 `CombatManager`（autoload，全域可用，不用另外接線）：`apply_camera_shake`、`spawn_spark`、`spawn_ghost`、`spawn_dodge_spark` 四個函式完全通用（不依賴主遊戲的 Player/Enemy 類別），VsMods 直接呼叫即可，沒有重寫任何邏輯。**`CombatManager` 本身就是共用特效庫，不需要另外蓋一個「特效字典場景」**——`VsPlayer.vfx_*` 只是每個角色呼叫它的統一入口，跟主遊戲 `Player.gd` 的 `add_ghost()` 是同一種包裝模式。

- **位置基準**：`VsPlayer.vfx_anchor_position()` 回傳 `Graphics/Sprite2D` 的實際 `global_position`——VsPlayer 根節點對齊腳底（碰撞體/確定性 position 都在腳底），特效要對齊「看起來的身體位置」必須讀 Sprite2D 本身，不能直接用角色的 `global_position`（那是腳底，殘影會貼地錯位，曾經踩過）。`vfx_ghost`/`vfx_dodge_spark` 都走這個。
- **火花只綁在命中判定上，沒有動畫軌道版**（`vfx_spark_self` 這種東西刻意不做）：火花是「命中那一刻、命中對象身上」才有的反應，不該是招式動畫自己無條件帶的效果，所以 `vfx_spark` 只由 `vs_world._manual_check()` 在真正判定命中時呼叫，需要一顆實際命中的 `VsHitbox` 才能呼叫（拿不到就沒有簡化版可用）。
- **命中回饋 — 火花的角色預設 + 每招覆寫（比照主遊戲 `Weapon.get_weapon_default_spark()` 三層 fallback，簡化成二選一）**：`VsPlayer` 新增 `default_spark_*` 一組欄位（type/scale/color/aura_color/raw_intensity/random_angle/base_offset/random_offset/attach_to_victim/custom_scene，`@export_group("角色預設火花")`）作為整個角色的預設火花外觀。`VsHitbox` 新增同名的 `spark_*` 欄位＋一個開關 `use_character_default_spark`（**預設 `true`**）：開著時這顆 hitbox 完全套用角色預設，不用碰；想讓某一招火花不一樣才關掉開關、填這顆自己的完整參數。VsMods 是節點驅動（不是主遊戲那種資料表），所以簡化成「整組套角色預設」或「整組用這招自己的」二選一，不像主遊戲能單一欄位分開 fallback——多數情況已經夠用。`shake_intensity` 沒有這層 fallback（跟主遊戲一樣每招自己填，預設 0=不震動）。
  `vs_world._manual_check()` 確認幾何命中後呼叫 `hb_owner.vfx_spark(hb, hrb.global_position, hrb_owner)`／`hb_owner.vfx_shake(hb.shake_intensity)`——**不管防禦/霸體/無敵吸收與否都照樣給回饋**，「打中了」跟「打中造成多少效果」是兩件事，比照主遊戲 `Hitbox._execute_hit()` 的做法，別加條件判斷。`vfx_spark(hb, base_pos, victim)` 內部解析 use_character_default_spark、算隨機角度/偏移（`randf_range`，純視覺兩端各自獨立算不用同步）、決定跟隨目標，最後呼叫 `CombatManager.spawn_spark` 完整參數版——完整複刻主遊戲 `Hitbox._execute_hit()` 的邏輯，不是精簡版。
- **動畫軌道版（震動/殘影，不含火花）**：`vfx_shake(intensity)`／`vfx_ghost(color)` 可以**直接當動畫 Call Method 軌道呼叫**（NodePath 打 `.`、方法名填函式名，跟 `strike_impulse` 同一套用法），適合「這一幀就是要有這個特效」的固定時間點（出招瞬間塵土、蓄力震動等）——這些不是「命中回饋」，是招式本身自帶的效果，所以可以綁動畫時間點，跟火花的定位不同。
- **衝刺殘影**：`VsDodge` 每 `GHOST_INTERVAL`(0.05s) 呼叫一次 `vfx_ghost()`，計時器 `_ghost_timer` 進快照（純視覺但計時器本身要跟著模擬時間走，才不會 rollback 後間隔跑掉）。
- **完美閃避火花**：`VsDodge.trigger_perfect_dodge()` 呼叫 `vfx_dodge_spark()`。
- **⚠ rollback 防重複是這套系統的核心約束，兩層防呆缺一不可**：(1) `is_resimulating`（由 `vs_world._simulate_frame()` 每幀同步，**不進快照**——執行期中繼資訊不是模擬狀態）擋掉 rollback 重模擬時的重複觸發；(2) `_resyncing_anim`（`strike_impulse` 那條規則同款）擋掉動畫 resync 的 `seek()` 可能回放 Call Method key。`VsPlayer._vfx_blocked()` 統一檢查這兩者，`vfx_spark`/`vfx_shake`/`vfx_ghost`/`vfx_dodge_spark` 內建。**之後任何新增的打擊/招式特效都要走這幾個 `vfx_*` 函式，不要直接呼叫 `CombatManager.*`**，否則會在 rollback 下重複觸發或被 seek 誤觸發。
- **特寫運鏡** — `vfx_closeup(depth, duration)`，可當動畫 Call Method 軌道呼叫。**不是**移植主遊戲 `CombatManager.apply_camera_closeup`（那個直接 tween `camera.zoom` 再還原成固定 `base_zoom`，會跟 `VsCamera` 平常持續動態運算縮放（依兩位玩家距離即時調整 `zoom`）互搶屬性），而是走 `VsCamera`（`VsMods/object/Camera2D.gd`）**自己原本就有、但沒接完的**特寫系統：`cinematic_zoom(target, target_zoom, duration)` 設定 `is_in_cinematic=true` 後，`_physics_process` 會切到專門分支處理鏡頭拉近，不會跟一般立回模式的動態縮放衝突。**修復**：`cinematic_timer` 原本只宣告、從未倒數/檢查，特寫觸發後永遠不會自動結束——已補上倒數邏輯，`duration` 秒後自動退回一般立回模式。
- **⚠ 螢幕震動走 `VsCamera.shake()`，不是 `CombatManager.apply_camera_shake()`**：`VsCamera._physics_process()` 每幀都用自己的 `shake_timer`/`shake_intensity` 決定 `offset`（沒在震動就強制歸零），若改呼叫 `CombatManager` 那邊用 Tween 動 `camera.offset`，兩邊每幀互搶同一個屬性，Tween 效果會被 `VsCamera` 自己「沒在搖就歸零」的邏輯蓋掉，震動等於沒作用（`vfx_shake` 曾經這樣寫，已修正為呼叫 `VsCamera.shake(intensity, duration)`，並比照主遊戲尊重 `Game.config_enable_screen_shake` 設定）。`VsCamera` 早就有自己一套完整的震動系統，別重複做兩套。
- 刻意跳過的部分（不適合對戰模式）：`CombatManager` 的 domain 時停/`Engine.time_scale`（VsMods 明確禁用）、`spawn_energy_orbs`（主遊戲拾取式能量球，跟 VsMods 自己的雙能量池系統不搭）、`spawn_damage_number`（傷害數字，未要求）。
- **`spawn_anim_vfx(vfx_name, ...)`**（`VsPlayer.gd`，完整移植主遊戲 `Player.gd` 同名函式）— 跟上面 `vfx_*` 系列是不同系統：`vfx_spark`/`vfx_shake`/`vfx_ghost` 是固定打擊回饋（走 `Hitbox.SparkType` 枚舉／`CombatManager` 內建 scene）；`spawn_anim_vfx` 是**字典庫**系統，用 `@export var vfx_common/vfx_weapon/vfx_system: Dictionary`（三個字典，`vfx_name: String → PackedScene`，在 Inspector 展開字典逐一登記）讓任意自訂特效場景都能掛，供招式/武藝專屬視覺使用（不限於打擊）。動畫 Call Method 軌道或程式碼都能直接用字串名稱呼叫，跟主遊戲武器腳本（`Talisman.gd` 的 `player.spawn_anim_vfx("heal_flash", 0, -30)`）完全同一套用法。位置基準是角色 `global_position`（腳底）＋呼叫端自己指定的 `offset_x`/`offset_y`（**不是** `vfx_anchor_position()`——主遊戲的既有特效呼叫本來就是靠 offset 手動校正，換基準點會跟舊的 offset 數值對不上）。同樣受 `_vfx_blocked()` 防呆（`is_resimulating` + `_resyncing_anim`）保護。`VsPlayer.tscn` 的 `vfx_common` 已整批搬入主遊戲 `player.tscn` 原本 `vfx_weapon`+`vfx_system` 的全部 11 個特效（`Circular cut`/`Circular shock wave`/`Cross slash sparks`/`Dimensional Slash`/`Spiral Thrust`/`Thrust`/`blunt_spark`/`chop`/`cut`/`whirlwind`/`Aggregation ring`，場景資源都在 `Explod/tscn/`）——VsMods 目前不分類別，全部塞進 `vfx_common` 一個字典裡，`vfx_weapon`/`vfx_system` 兩個字典留空（@export 還在，之後有需要分類可以用，非必要）。
- **`attack_1~5` 已接上對應的 `spawn_anim_vfx` Call Method key**（從主遊戲 `player.tscn` 的 `Katana/light_1~5` 動畫逐一比對移植，兩邊動畫長度剛好一致：0.5/0.7/0.7/0.6/0.8，時間點可以直接沿用）：attack_1→`"chop"`、attack_2~4→`"cut"`（各自不同的 offset/scale/rotation/color 沿用主遊戲原始數值）、attack_5→`"Thrust"`。觸發時間點對齊到該招**已存在的 `strike_impulse` key**（+0.01s 避免同一條 Call Method 軌道出現重複時間戳——Godot 的 keyframe times 陣列要求嚴格遞增，不能有兩個一樣的時間點），因為使用者自訂的 5 招 `strike_impulse` 時間點本來就幾乎精準對齊各自的 `HitboxAN:monitoring` 開啟時刻（3 招完全相同、2 招極接近），衝力跟火花同一瞬間發生是合理的預設，之後想要拆開時間點直接在動畫面板調 key 即可。

### VsMods 攻擊系統目前狀態（Phase 4）

- **地面普攻** — `VsAttack.gd` 5 段連技，**每招的所有資料都在 `VsPlayer.tscn`，程式碼零資料表**：時間點在 attack_1~5 動畫軌道（`.:can_combo` 軌=連段窗口、`Graphics/HitboxAN:monitoring` 軌=判定框開關，與主遊戲 player.tscn 同款做法）；判定框大小/位置/傷害/硬直/擊退在**每招一顆的 `HitboxA1~A5` 節點**（VsHitbox @export，編輯器直接調）。`VsPlayer.hitboxes` 收集 Graphics 下所有 VsHitbox，快照統一保存各框 `[monitoring, has_hit]`，`vs_world._check_manual_hits` 迭代全部。0.2s 攻擊輸入緩衝（`ATTACK_BUFFER`，必須小於各段窗口開啟時間）；窗口開啟＋有緩衝→立刻取消剩餘動畫接下一段。打斷優先級：衝刺（任何時點）> 防禦（地面限定）> 武藝（未實作，接入點已留）> 連段派生。`combo_step` 在 `exit()` 才重置；連段繼續直接呼叫 `enter()` 繞過防重入鎖。
- `VsAttack.IMPULSE_FRICTION = 8750.0`（比照主遊戲 `Katana.gd` 的 `FLOOR_ACCELERATION = RUN_SPEED/0.04`）是攻擊狀態專用的水平減速率，跟 `VsPlayerState.FRICTION`（900，一般移動用）是分開的兩個常數，別搞混。`strike_impulse` 打出的前衝力道要靠這麼強的摩擦力才煞得住——用一般移動摩擦力的話同樣衝力強度會飛遠將近 20 倍（滑行距離 ∝ v²/摩擦力），這是把主遊戲的 strike_impulse 力道數值直接套用到 VsMods 卻飛超遠的根因，不是 strike_impulse 本身的問題。
- **`strike_impulse(strength)`**（`VsPlayer.gd`，主遊戲 `Player.strike_impulse` 同款設計）— 給動畫 Call Method 軌道呼叫用，在攻擊動畫的前衝/突刺幀把 `velocity.x` 直接設成 `facing_dir * strength`，取代殘留動量；只在 `state_machine.current_state is VsAttack` 時生效。軌道路徑跟 `.:can_combo` 同一套慣例（NodePath 指向場景根節點 `.`，方法名 `strike_impulse`），時間點與力道在編輯器動畫面板調，不寫程式碼。配套修正：`VsAttack.enter()` 現在會先把 `velocity.x` 歸零（跑步衝進攻擊不再殘留慣性滑行），前衝感全部改由這個函式的動畫軌道呼叫負責。攻擊狀態的摩擦衰減改用 `VsAttack.IMPULSE_FRICTION`（見上）而非一般移動摩擦力，否則衝力煞不住會飛超遠。
  **⚠ 實測抓到過的 rollback desync**：`sync_anim_to_state()`（每次 rollback 還原快照都會呼叫、重模擬結束後也會再呼叫一次）內部用 `seek(elapsed, true)` 把動畫時間跳到還原後的位置。`can_combo`/`hitbox monitoring` 是「值」軌道，seek 重複套用同一個值無害（冪等）；但 `strike_impulse` 是「呼叫方法」軌道，每次真的觸發都會改一次 `velocity`，不是冪等的——Godot 的 `seek(..., true)` 是否會回放沿途經過的 Call Method key 行為不夠明確保證不會，一旦真的回放了，就會拿「已經是正確模擬結果」的 velocity 再蓋一次錯的衝力，而且每次 rollback 都疊加一次，實測連續幾次 rollback 後兩端 `vsattack` 狀態下的 `position`/`dash_energy` 對不上。修法：`VsPlayer._resyncing_anim` 旗標，`sync_anim_to_state()` 呼叫期間設 true，`strike_impulse()` 開頭檢查此旗標為 true 就直接跳過——只允許「真的走過這一幀模擬」（`_do_rollback` 重模擬迴圈裡的 `advance()`，或正常單幀模擬）觸發衝力，純視覺 resync 觸發的一律擋掉。**這是唯一的 Call Method 軌道，之後若新增別的 Call Method 軌道（不是值軌道）都要套用同一個 `_resyncing_anim` 防呆，否則遲早會踩到同一個坑。**
- **輔助鎖敵** — `VsPlayer.face_towards_x(x)` / `face_opponent()` 是共用輔助（`opponent` 由 vs_world 注入；用 `position` 算，確定性安全；rollback 走 `set_state_quiet` 不經過這些函式，面向由快照還原）。`VsIdle` 靜止（`input.move_dir == 0`）時**每幀**持續呼叫 `face_opponent()`，不是只在 `enter()` 算一次——對手左右移動時待機角色會跟著轉；一旦有移動輸入交回 `_apply_ground_move` 決定面向，不會互相蓋掉。**`enter()` 裡刻意不轉向**：`enter()` 跟上一個狀態的收尾轉場發生在同一模擬幀，這時 MANUAL 模式的 `play("idle")` 要等下一幀 `advance()` 才會真的把畫面換成 idle 姿勢，但 `graphics.scale.x` 是每幀無條件套用——若 `enter()` 就轉向，上一個狀態最後一幀顯示的畫面會被新朝向鏡像，看起來像「攻擊最後一幀也跟著轉」；轉向必須延到真正進入 idle（下一幀）由 `physics_update` 生效。

**MANUAL 動畫模式的轉場時機——兩種轉場的視覺延遲不一樣，別搞混**：`VsPlayer.apply_input()` 的呼叫順序是 `_apply_pending_hit()` → `anim_player.advance(delta)` → `state_machine.physics_update(delta, input)`。這決定了兩類轉場的視覺同步性完全不同：
  - **命中觸發的轉場**（`_apply_pending_hit()` 內直接呼叫 `state_machine.transition_to(...)`，例如受擊進 `vshurt`/`vslaunched`）發生在本幀 `advance()` **之前**——新動畫的 `play()` 呼叫完，緊接著同一幀的 `advance()` 就會推進新動畫，視覺當幀就會同步，沒有延遲。
  - **狀態自己 `physics_update()` 回傳字串觸發的轉場**（例如 `VsHurt`/`VsLaunched` 判斷條件成立後 `return &"vsknockdown"`，或任何「狀態跑完自己邏輯才決定換下一狀態」的轉場）發生在本幀 `advance()` **之後**——新動畫的 `play()` 要等到下一幀的 `advance()` 才會真的推進，本幀畫面還停在舊動畫最後一次 `advance()` 的姿勢。
  
  任何在 `enter()` 裡對「每幀無條件套用」的即時效果（`graphics.scale.x` 朝向、`position` 瞬移之類）做修改，只要是走**第二種**轉場，就會出現「邏輯已經生效、畫面卻還停在舊姿勢」的錯位（VsIdle 的鎖敵轉向、VsKnockdown 的瞬移都踩過這個坑）。修法是把該效果從 `enter()` 延後到該狀態自己 `physics_update()` 第一次真正執行時做（用一個旗標擋住只執行一次，記得存進快照）——那一幀的動畫視覺才真的追上。`VsPlayer._on_hurtbox_hurt()` 在 `is_invincible()` 檢查之後、不論後續走哪個分支（硬直/防禦/擊飛），立刻呼叫 `face_towards_x(hitbox.owner_player.position.x)` 面向攻擊者。`VsDodge.enter()` 算出 `dodge_dir` 後必須同時寫回 `facing_dir = dodge_dir`——不寫會出現「滑動動畫朝左、卻往右衝」（衝刺前後轉身時特別明顯）。
- **恢復狀態的跑步預輸入** — `VsPlayerState._recovery_transition(input)` 是共用收尾：地面+有方向輸入→直接 `vsrun`（同時把 `facing_dir` 設對，跳過「無腦轉 idle」再等下一幀才轉 run 的空檔）；地面無輸入→`vsidle`；未落地→`vsfall`。套用在 `VsDodge`/`VsHurt`（非落地分支）/`VsGetup`/`VsGuard`/`VsFall` 的收尾。**`VsAttack` 刻意不用**——攻擊收招不支援預輸入直接接 run，規則明講。
- **硬直/落地（倒地）/起身流程** — `causes_knockdown` 攻擊按擊退 y 分流（`VsPlayer._apply_pending_hit`）：y<0 → `VsLaunched` 擊飛（忽略硬直，弧線飛行，落地瞬間進 `VsKnockdown`、水平動量保留；空中再被擊飛=juggle 重入）；y=0 → `VsHurt` 正常硬直，結束後進 `VsKnockdown`（`queued_knockdown`）。`launched` 是純躺地姿勢，站姿切過去沒有任何過渡動作——解法是補一段一次性過場動畫 `launched_start`（站姿倒下→躺地），`VsKnockdown.enter()` 先播它，`physics_update()` 每幀檢查 `elapsed >= _start_anim_length` 播完就接 `LOOP_ANIM`（`launched`）循環；純視覺銜接，不影響下面的貼地/彈起/起身物理判定時機。（之前試過「進場把 y 瞬移到上方、重力帶回原位」的假摔方案，使用者否決了，改用這個補動畫的做法。）**「真正到地上」判定綁在 `launched_start` 過場動畫播完（`not _in_start_anim`），不是單純 `_grounded()`**——地面硬直（y=0 擊退）進來的角色從沒離地過，`enter()` 第一個 tick 就已經貼地，若拿 `_grounded()` 當判定，等於進場那一刻立刻無敵+彈起，前面應該能被 OTG 命中的窗口長度變成 0（實測過的 bug：診斷數值顯示彈跳物理完全正確，問題其實是這段窗口被吃掉，玩家看到的第一幀就已經是彈起後下墜+無敵）。播 `launched_start` 期間＝規則講的「落地期間」（無敵無、只有 OTG 打得到）；播完才觸發無敵直到起身（`INVINCIBLE_COVER` 罩住，進 VsGetup 被覆寫）＋彈起一次（`BOUNCE_VELOCITY = -160`）→二次落地直接接 `VsGetup`。窗口長度＝`launched_start` 動畫長度，在編輯器調動畫即可調整，不是額外的數字常數。此判定對地面硬直/空中擊飛落地兩條路徑都適用。貼地摩擦隨貼地時間漸增（`FRICTION_RAMP_TIME`），不瞬間黏住；保護靠 `can_hit_downed` OTG 偵測層閘門，倒地/擊飛中被普通攻擊打到只吃傷害與速度、不換狀態。`VsHurt` 硬直**不給任何無敵**（連段要能全程命中；同攻擊窗防重複靠 `has_hit`——別把 0.15s/0.2s 的「防穿透/喘息」無敵加回來，A2 打空的 bug 就是它）。`VsGetup` 播 `launched_2`、時長讀動畫長度，給 2s 無敵（延續進 idle）、可衝刺打斷但無敵歸零。死亡演出：`VsRoundManager._tick_fighting` 判定回合結束時強制死者進 `VsKnockdown`（暫代死亡動畫）。AnimationPlayer 的 MANUAL 模式由 `VsPlayer._ready()` 在運行時設定，**不寫在 tscn**——否則編輯器動畫面板無法預覽播放。
- **空中普攻** — 尚未實作。素材 `player/Katana/air_A.png` 存在。計畫在 VsAttack 加 `is_grounded` 判斷分支，或拆出獨立 `VsAirAttack` 狀態。
- **技能（`input.skill`）** — 尚未實作，目前所有狀態的 `physics_update` 均忽略此輸入。
- **武藝（`input.art_1/2/3`）** — 尚未實作效果。`VsPlayer.art_slots: Array[String]` 儲存玩家選擇的 3 個武藝名稱（由 `vs_world` 從 `VsGameManager.p1_arts/p2_arts` 注入）；`apply_arts_bonus()` 目前只處理空槽加成。武藝名稱字串即武藝 class name，效果實作時需自行 lookup。

### Combat/hit detection — two separate implementations

Main game: `classes/Hurtbox.gd` (Area2D) just emits a `hurt(hitbox)` signal; `classes/Hitbox.gd` (Area2D) owns damage/knockback/poise, multi-hit tracking (`hit_targets`), and dispatches spark/shake/audio via the `CombatManager`/`AudioManager` autoloads before calling into the hurtbox. `classes/Damage.gd` is the payload (type LIGHT/HEAVY/THROW/NO_STUN; source_type MELEE/PROJECTILE/ASSIST).

VsMods: `VsMods/combat/VsHitbox.gd` (Area2D) has fighting-game-specific fields (`damage`, `hitstun_time`, `knockback`, `causes_knockdown`, `guard_break`). `VsMods/combat/VsHurtbox.gd` emits `hurt(hitbox)` signal received by `VsPlayer._on_hurtbox_hurt()`. No code is shared between the main-game and VsMods hit systems — know which mode you're editing before touching either.

### Armor / hyperarmor defense system (main game only)

Player side: `Player.gd` has a 3-tier `ArmorTier` enum (`NONE` / `HYPER_ARMOR` / `STRONG_HYPER_ARMOR`). `HYPER_ARMOR` blocks LIGHT hits only (no stagger, full damage); `STRONG_HYPER_ARMOR` blocks LIGHT+HEAVY with a 50% damage reduction. Only `Spear.gd` currently overrides `Weapon.get_armor_tier()` (its 4 收槍強化技 report `STRONG_HYPER_ARMOR`) — Katana/Sickle/Talisman don't yet; a weapon that wants tiered armor for a specific `combo_step` should override `get_armor_tier()` the same way, not invent a parallel flag. `Player.is_in_hitstun()` (state is Hurt/Launched) is a separate immunity path from `invincible_time_left` — both are checked wherever damage is gated.

**Player invincibility has three call-site patterns — they look redundant but are each pinned to a different `Engine.time_scale` situation, don't collapse them:**
1. `grant_invincibility(duration)` — the default helper; sets `invincible_time_left` **and** starts the `invincible_timer` Timer node. Use this for anything at normal game speed: `Hurt.gd`/`Launched.gd`'s post-hitstun grace window, `Guard.gd`'s chain-lock window, `Art_Katana_1.gd`'s counter.
2. Writing `player.invincible_time_left` directly, skipping `invincible_timer` entirely — used by every weapon ultimate (`Spear.gd`/`Katana.gd`/`Sickle.gd`/`Talisman.gd`'s `start_ultimate()`, `Art_Katana_6.gd`, `Art_Talisman_20.gd`). These all pair with `trigger_time_stop(_, 0.001)` (near-zero time scale) — a `Timer` node's countdown is itself slowed by `Engine.time_scale`, so at `0.001` a 3-second Timer-based invincibility would take ~3000 real seconds to expire. `invincible_time_left` is decremented with `unscaled_delta` in `Player.gd`, so it stays a true real-time duration regardless of time-stop.
3. Calling `invincible_timer.start(duration)` directly, skipping the float — used only by `Slide.gd::trigger_perfect_dodge()` (極限閃避), which does a **partial** slowdown (`time_scale = 0.3`), not a stop. Here the Timer's time-scale sensitivity is the wanted behavior: the 0.5s invincibility stretches proportionally with the bullet-time so it keeps covering the whole slow-motion window, instead of expiring in real time before the slowdown visually ends.

Before adding a new time-manipulating skill, decide which of these two axes it's on (full time-stop vs. partial slowdown vs. normal speed) and use the matching pattern — don't reflexively route everything through `grant_invincibility()`.

Enemy side (`enemies/enemy.gd`): two independent bools, `is_hyper_armored` (blocks player-inflicted stagger/knockback, not damage) and `is_invincible` (blocks everything), plus `Tier { LOW, MID, HIGH }`. **Convention:** any enemy attack state that should be hyperarmored calls `enter_attack_state()` on entry and `exit_attack_state()` on exit (it internally checks `tier == MID or HIGH` — LOW-tier enemies get no armor). Don't hand-roll `grant_hyper_armor()`/`clear_hyper_armor()` calls inside individual attack states; wrap the whole state's `enter()`/`exit()` instead so armor duration always matches the state's actual lifetime.

The **only** mechanism that pierces a defender's armor/guard is `hitbox.requires_countermeasure = true` (paired with the "yellow-ring" `start_guard_window()`/`try_guard_break()` flow on `Enemy.gd`) — before adding a new "breaks hyperarmor" field or system, check whether `requires_countermeasure` already covers it.

Status outline VFX (`StatusOutline.gdshader`, wired on both `Player.gd` and `Enemy.gd`) renders armor/invincibility as a colored edge glow. Both scripts resolve the sprite's live `.material` through a single function (`_resolve_main_sprite_material()`/`_refresh_main_sprite_material()` on `Enemy.gd`) rather than having the white-hit-flash and the outline effect each independently snapshot/restore `sprite.material` — the two used to race and leave sprites stuck fully white. Any new effect that touches the main body sprite's material must go through that same resolver, not add its own snapshot/restore.

`Enemy.gd::show_attack_warning(icon, delay, duration, fade_duration)` / `hide_attack_warning(icon)` is a generic, self-contained "驚嘆號" telegraph VFX utility — call it directly at the moment you want the icon to appear (it handles its own fade in/out and cancellation via an internal token), don't build a dedicated state/flow just to time a warning icon.

### Global autoloads (declared in `project.godot`)

| Autoload | Script | Responsibility |
|---|---|---|
| `Game` | `globals/game.gd` (`GameManager`) | Settings persistence (ConfigFile), fullscreen, custom keybindings, cross-scene world/player stats |
| `CombatManager` | `Explod/CombatManager.gd` | `Engine.time_scale` arbitration (domain slowdown/time-stop vs. UI pause — no hitstop, the game deliberately doesn't use it), camera shake, hit-spark VFX spawning |
| `AudioManager` | `sound/AudioManager.gd` | SFX/hit-SFX playback (`play_sfx`, `play_hit_sfx`) |
| `VsGameManager` | `VsMods/ui/VsGameManager.gd` | Cross-scene P1/P2 character & custom-skill selection cache for VsMods |
| `Vignette`, `PauseMenu` | scene autoloads | Screen vignette effect; pause UI |

Hitbox/Weapon code guards autoload calls with `has_method()` checks — treat this as the existing convention when adding new cross-autoload calls, not as something to "clean up".

### UI theme (`ui/`)

`ui/PixelTheme.tres` is the project-wide default `Theme` (wired via `project.godot`'s `[gui] theme/custom`), giving every menu Control (Panel/Button/CheckButton/OptionButton/HSlider/ScrollBar) a flat black-and-white pixel-line look — no rounded corners, no anti-aliasing, hover/pressed states invert to a white fill with black text. `Panel` (translucent, alpha 0.75 — full-screen menu backgrounds like `pause_menu.tscn`/`settings_panel.tscn`) and `PanelContainer` (fully opaque — `PixelOptionButton`'s dropdown list) are deliberately two separate StyleBoxFlats; don't collapse them back into one, they're translucent/opaque for different reasons. `ui/icons/` holds small generated pixel icons (checkbox, dropdown arrow, slider grabber) that back this theme.

**Don't use engine-native `OptionButton`/`PopupMenu` dropdowns anywhere in the main game UI.** At this project's base resolution (384x216, stretched via `canvas_items` mode), a native Popup is a separate `Window` that doesn't share the main viewport's stretch/oversampling, so its text renders visibly blurrier than everything else on screen — confirmed via screenshot, and there is no simple Theme/property fix (`Window.content_scale_factor` does **not** fix it — it just scales layout size, not render fidelity). Use `ui/PixelOptionButton.gd`/`.tscn` instead: a custom dropdown that opens a plain overlay of `Button` nodes (via a `CanvasLayer`, so it isn't clipped by parent `ScrollContainer`s) instead of a native Popup, staying inside the normal embedded-Control rendering pipeline that's guaranteed crisp. Its API deliberately mirrors `OptionButton` (`clear`/`add_item`/`set_item_metadata`/`get_item_metadata`/`selected`/`select`/`item_count`/`disabled`/`item_selected` signal) so it's close to a drop-in replacement. `VsMods/ui/select.tscn` still uses a native OptionButton — that's the separate VsMods framework and is out of scope for this fix.

## Conventions to know before editing

- Comments are bilingual (Traditional Chinese + English) with emoji section banners (`# ==...==`) — match this style in files that already use it.
- Player/weapon code frequently uses duck-typed `.get("property_name")` lookups instead of typed references — this is intentional loose coupling, not an oversight to "fix" with static typing.
- `PixelBaker/PixelBaker.gd.gd` has a doubled extension — this is the actual filename on disk, not a typo to silently rename.
- `Object.get_meta(key, default)` does **not** suppress the "meta not found" error when `default` is `null` — Godot can't distinguish "no default given" from "default explicitly `null`". Check `has_meta(key)` first instead of relying on a `null` default.
- A `Control` positioned via anchors+offsets under a plain (non-`Container`) parent does **not** auto-shrink to its children's content, even if the control itself is a `Container` type (e.g. `PanelContainer`) — its size is whatever the offsets say. If it needs to hug dynamically-changing content (e.g. a row of icons whose count varies), call `reset_size()` manually whenever that content changes.
