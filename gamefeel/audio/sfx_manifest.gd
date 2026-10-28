class_name SfxManifest
extends RefCounted
## Event -> resource/procedural layer map used by AudioLayerManager.
## Kept declarative so sound design can be tuned without touching playback code.

## Low layer weight per weapon (0 = light click, 1 = heavy boom).
const WEAPON_WEIGHT := {
	&"m9": 0.32,
	&"smg": 0.38,
	&"ar15": 0.52,
	&"shotgun": 0.95,
	&"lmg": 0.78,
	&"sniper": 0.88,
	&"katana": 0.42,
	&"axe": 0.55,
	&"chainsaw": 0.60,
	&"throwable": 0.35,
}

## Existing sample paths (used only as documentation / fallback if the legacy
## AudioManager is ever removed).
const WEAPON_SAMPLE := {
	&"m9": "res://assets/audio/sfx/m9.ogg",
	&"smg": "res://assets/audio/sfx/smg.ogg",
	&"ar15": "res://assets/audio/sfx/ar15.ogg",
	&"shotgun": "res://assets/audio/sfx/shotgun.ogg",
	&"lmg": "res://assets/audio/sfx/lmg.ogg",
	&"sniper": "res://assets/audio/sfx/sniper.ogg",
	&"katana": "res://assets/audio/sfx/katana.ogg",
	&"axe": "res://assets/audio/sfx/axe.ogg",
	&"chainsaw": "res://assets/audio/sfx/chainsaw.ogg",
}

const IMPACT_KIND := {
	&"blood": &"meat",
	&"human": &"meat",
	&"spore": &"squish",
	&"armor": &"metal",
	&"debris": &"debris",
	&"blood_burst": &"meat",
}

const RELOAD_STAGES := [0.0, 0.25, 0.5]

const STREAK_STREAMS := {
	3: &"streak_3",
	5: &"streak_5",
	10: &"streak_10",
}


static func weapon_weight(weapon_id: StringName) -> float:
	return float(WEAPON_WEIGHT.get(weapon_id, 0.4))


static func impact_sound(kind: StringName) -> StringName:
	return StringName(IMPACT_KIND.get(kind, &"meat"))


static func streak_stream(tier: int) -> StringName:
	return StringName(STREAK_STREAMS.get(tier, &"streak_3"))
