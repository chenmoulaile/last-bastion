extends Node
## EventBus - the single communication channel between game systems.
## Nothing outside a parent/child pair should hold a direct node reference.

# --- Combat / actors -------------------------------------------------------
signal enemy_died(kind: StringName, pos: Vector2, score: int)
signal enemy_killed(kind: StringName, source: StringName, pos: Vector2)
signal player_downed
signal player_died
signal player_rescued
signal player_hit(amount: int)
signal player_healed(amount: int)
signal ally_pinned(ally: Node)
signal ally_unpinned(ally: Node)
signal ally_downed(ally: Node)
signal ally_died(ally: Node)
signal ally_revived(ally: Node)
signal gunshot(pos: Vector2, loudness: float)
signal zombie_scream(pos: Vector2, radius: float)
signal witch_woken(pos: Vector2)
signal witch_crowned(pos: Vector2)
signal boss_spawned(kind: StringName)
signal boss_killed(kind: StringName)
signal boss_health_changed(current: int, maximum: int)
signal door_broken(pos: Vector2)
signal door_kicked(pos: Vector2)
signal barrel_exploded(pos: Vector2)
signal explosion(pos: Vector2, radius: float)
signal special_spawned(kind: StringName)
signal special_escaped(kind: StringName)

# --- Director --------------------------------------------------------------
signal director_request_horde(count: int)
signal director_request_special(kind: StringName)
signal director_request_supply(kind: StringName)
signal director_intensity_changed(value: float)
signal horde_started(count: int)
signal horde_ended

# --- Flow / progression ----------------------------------------------------
signal start_level_requested
signal level_completed(score: int, rank: String)
signal level_failed(reason: String)
signal unlock_earned(id: StringName)
signal achievement_unlocked(id: StringName)
signal return_to_menu_requested
signal retry_level_requested
signal next_level_requested
signal game_paused(paused: bool)

# --- UI / feedback ---------------------------------------------------------
signal score_changed(score: int)
signal combo_changed(combo: int, mult: float)
signal health_changed(hp: int, temp_hp: int, max_hp: int)
signal ammo_changed(mag: int, reserve: int)
signal weapon_changed(id: StringName, display_name: String)
signal skill_state_changed(ratio: float, active: bool)
signal interact_prompt(text: String)
signal notify(text: String)
signal level_event(text: String)
signal objective_changed(text: String)
signal checkpoint_reached(pos: Vector2)
signal extraction_started(seconds: float)
signal extraction_arrived
signal safe_room_entered(entered: bool)
signal command_issued(cmd: StringName)
signal formation_changed(formation: StringName)
signal screen_shake(amount: float)
signal hitstop(duration: float)
signal damage_flash
signal bile_splashed(duration: float)
signal pickup_collected(kind: StringName, amount: int)
signal supply_spawned(kind: StringName, pos: Vector2)
signal teammate_status_changed
signal debug_panel_toggled
signal debug_vision_toggled
signal toast(title: String, detail: String)


func announce(text: String) -> void:
	notify.emit(text)


func shake(amount: float) -> void:
	screen_shake.emit(amount)
