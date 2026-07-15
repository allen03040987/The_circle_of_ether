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

`VsMods/player/VsPlayer.gd` (`CharacterBody2D`) — HP/energy/invincibility, `apply_input(delta, input)` driven each frame by `vs_world`. Has `save_state()`/`restore_state()`/`sync_anim_to_state()` for rollback. States live under `VsMods/player/states/`: `VsIdle`, `VsRun`, `VsJump`, `VsFall`, `VsHurt`, `VsKnockdown`, `VsGetup`, `VsDodge`, `VsGuard`, `VsAttack`. `VsAttack` is registered programmatically in `VsPlayer._register_attack_state()` (not a scene child) because its combo animation data is built in code.

Scene flow: `title_screen.gd` → `VsMods/ui/LobbyScreen.tscn` (離線/主機/加入) → `VsMods/ui/SelectScreen.tscn` (角色+3 武藝槽選擇) → `VsMods/vs_world.tscn` (戰鬥). `VsGameManager` (autoload, `VsMods/ui/VsGameManager.gd`) caches `p1_arts`/`p2_arts`/`selection_confirmed` across scene changes.

### VsMods rollback netcode (`VsMods/network/`)

`VsNetworkManager` (autoload) drives frame-locked synchronization:

- **`tick(local_input) -> Array`** — always returns `[p1_input, p2_input]`, never stalls. If confirmed remote input for the current frame hasn't arrived yet, predicts using `_last_remote_input` (last confirmed remote frame) and records the prediction in `_predicted_remote[frame]`.
- **`_recv_packet()`** — when confirmed remote input arrives, compares against `_predicted_remote[frame]` if present; if they differ, sets `_pending_rollback_frame` to the earliest mismatched frame.
- Public API for `vs_world`: `needs_rollback()`, `consume_rollback_frame() -> int`, `get_game_frame() -> int`, `get_confirmed_remote_input(frame) -> InputState`.

`vs_world.gd` owns rollback execution:

- Every frame: saves snapshot `_frame_states[frame] = {p1_state, p2_state, round_manager_state, inp1, inp2}` before simulating. Keeps only the last `MAX_ROLLBACK_FRAMES = 10` frames.
- When `needs_rollback()`: `_do_rollback(from_frame, cur_frame, cur_inputs)` — restores the nearest snapshot at or before `from_frame`, re-simulates each frame using `get_confirmed_remote_input()` to override stored remote predictions, then simulates the current frame.
- **`is_resimulating`** flag — set `true` during re-simulation so `_on_round_ended`/`_on_round_started`/`_on_match_ended` signal handlers skip HUD updates.
- After rollback completes, `sync_anim_to_state()` on both players re-syncs `AnimationPlayer` to the restored state.

**Known limitation:** Godot's `Area2D` overlap detection doesn't update within a single `_physics_process` call, so hitbox collisions are not re-detected during re-simulation. Hit outcomes are reconstructed from the `pending_hit` dict stored in snapshots. Positions and velocity are always correct; in rare rollback edge-cases, HP from a hit that changes timing may briefly diverge.

**Signaling server** (`server/signaling_server.py`) — deployed at `wss://the-circle-of-ether-signal.onrender.com` (Render.com free tier, `server/requirements.txt` in subdirectory — Render Build Command must be `pip install -r server/requirements.txt`). Do **not** use `websockets ≥ 14.x` type annotations (`WebSocketServerProtocol` was removed). The `"arts"` message type is relay-only (server passes it through unchanged like `"offer"`/`"answer"`/`"ice"`).

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
