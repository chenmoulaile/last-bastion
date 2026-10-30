extends SceneTree
## Headless harness for GameManager multiplayer kill attribution (task 1a).
## Run:  godot --headless --path "E:/Last Bastion" --script res://tests/verify_player_stats.gd
##
## Integration probe, not a unit test: it drives the real autoload singleton
## through the same entry points level_runner uses, then reads the real result
## dictionary that the save system and result screen consume.

var _fails := 0
var _passes := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		_passes += 1
		print("  PASS  " + label)
	else:
		_fails += 1
		printerr("  FAIL  " + label)


func _initialize() -> void:
	# Autoload `_ready` (and thus GameManager's level table) has not run yet at
	# SceneTree::_initialize time. Defer the probe to the first idle frame.
	_run_probe.call_deferred()


func _run_probe() -> void:
	print("== GameManager attribution probe ==")
	var gm := root.get_node_or_null("GameManager")
	_check(gm != null, "GameManager autoload present")
	if gm == null:
		_quit()
		return

	# --- reset path -----------------------------------------------------------
	gm.player_stats = {}
	_check(gm.player_stats.is_empty(), "player_stats starts empty")

	# --- accumulate ----------------------------------------------------------
	# peer 2: 3 kills (1 headshot, 1 special), peer 3: 1 kill
	gm.record_player_kill(2, false, false, &"ar15")
	gm.record_player_kill(2, true, false, &"ar15")
	gm.record_player_kill(2, false, true, &"shotgun")
	gm.record_player_kill(3, false, false, &"sniper")
	gm.record_player_damage(2, 340)
	gm.record_player_down(3)
	gm.record_player_rescue(2)

	var s2: Dictionary = gm.player_stats.get(2, {})
	var s3: Dictionary = gm.player_stats.get(3, {})
	_check(int(s2.get("kills", -1)) == 3, "peer2 kills == 3 (got %s)" % str(s2.get("kills")))
	_check(int(s2.get("headshots", -1)) == 1, "peer2 headshots == 1")
	_check(int(s2.get("specials", -1)) == 1, "peer2 specials == 1")
	_check(int(s2.get("rescues", -1)) == 1, "peer2 rescues == 1")
	_check(int(s2.get("damage_dealt", -1)) == 340, "peer2 damage_dealt == 340")
	_check(int(s3.get("kills", -1)) == 1, "peer3 kills == 1")
	_check(int(s3.get("downs", -1)) == 1, "peer3 downs == 1")
	_check(int(s3.get("damage_dealt", -1)) == 0, "peer3 damage untouched == 0")

	# --- per-weapon breakdown -------------------------------------------------
	var w2: Dictionary = s2.get("by_weapon", {})
	_check(int(w2.get("ar15", -1)) == 2, "peer2 ar15 kills == 2 (got %s)" % str(w2.get("ar15")))
	_check(int(w2.get("shotgun", -1)) == 1, "peer2 shotgun kills == 1")

	# --- boss kill path -------------------------------------------------------
	gm.record_player_boss_kill(3, &"lmg")
	var s3b: Dictionary = gm.player_stats.get(3, {})
	_check(int(s3b.get("bosses", -1)) == 1, "peer3 bosses == 1")
	_check(int(s3b.get("specials", -1)) == 1, "peer3 specials incremented by boss kill")
	_check(int((s3b.get("by_weapon", {}) as Dictionary).get("lmg", -1)) == 1, "peer3 lmg recorded")

	# --- invalid peers ignored, not crashed -----------------------------------
	var before: int = gm.player_stats.size()
	gm.record_player_kill(0, true, true, &"ar15")
	gm.record_player_kill(-5, true, true, &"ar15")
	gm.record_player_damage(2, 0)
	gm.record_player_damage(2, -99)
	_check(gm.player_stats.size() == before, "invalid peers create no entries")
	_check(int(gm.player_stats[2]["damage_dealt"]) == 340, "non-positive damage ignored")

	# --- snapshot -------------------------------------------------------------
	var rows: Array = gm.get_all_player_stats()
	_check(rows.size() == 2, "snapshot has 2 rows (got %d)" % rows.size())
	var ids: Array = []
	for r in rows:
		ids.append(int(r["peer_id"]))
	_check(ids == [2, 3], "rows sorted by peer id: %s" % str(ids))
	_check(rows[0].has("name") and rows[0].has("character_id"), "row carries name + character_id")
	_check(rows[0].get("by_weapon") is Dictionary, "row carries a by_weapon dictionary")

	# --- snapshot must be a copy ---------------------------------------------
	rows[0]["kills"] = 999
	(rows[0]["by_weapon"] as Dictionary)["ar15"] = 999
	_check(int(gm.player_stats[2]["kills"]) == 3, "live kills immune to snapshot mutation")
	_check(int((gm.player_stats[2]["by_weapon"] as Dictionary)["ar15"]) == 2,
		"live by_weapon deep-copied")

	# --- merge into a result dictionary --------------------------------------
	var result := {"score": 1234, "failed": false}
	gm._merge_player_stats_into_result(result)
	_check(result.has("player_stats"), "result.player_stats injected")
	_check((result["player_stats"] as Array).size() == 2,
		"result.player_stats has both peers")
	_check(not result.has("kills"),
		"multi-peer result does NOT synthesise a global kills field")

	# --- single peer -> fields mirrored for the solo result screen -----------
	# Must reset first: the 2-peer tallies above are still live state.
	gm.player_stats = {}
	var solo := {}
	gm._merge_player_stats_into_result(solo)
	_check((solo["player_stats"] as Array).size() == 1, "solo snapshot falls back to 1 row")

	# --- reset on start_level -------------------------------------------------
	gm.player_stats = {2: {"kills": 9}}
	var no_squad: Array[StringName] = []
	gm.start_level(&"l01", &"SQUAD", &"NORMAL", &"assault", no_squad)
	_check(not gm.player_stats.has(2) or int(gm.player_stats[2]["kills"]) == 0,
		"start_level clears previous run tallies")
	_check(gm.player_stats.size() >= 1, "start_level seeds the local peer row")

	_quit()


func _quit() -> void:
	print("\n== result: %d passed, %d failed ==" % [_passes, _fails])
	quit(0 if _fails == 0 else 1)
