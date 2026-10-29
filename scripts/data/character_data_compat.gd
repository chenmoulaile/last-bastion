class_name CharacterDataCompat extends CharacterData
## 适配器：将 ReworkCharacterData 映射为旧 CharacterData 结构，供旧 HUD
## 读取。旧 HUD 的强类型代码 `var character: CharacterData = player.get("character")`
## 可无感读取。只读，不修改底层 ReworkCharacterData。

var _source: ReworkCharacterData

func _init(source: ReworkCharacterData) -> void:
	_source = source
	id = source.id
	display_name = source.display_name
	callsign = source.callsign
	character_id = String(source.id)
	codename = source.callsign
	roster = &"archive" if source.narrative_id != &"" else &"legacy"
	max_hp = source.max_hp
	speed = source.speed
	stealth_speed_multiplier = 1.0
	melee_damage = 40.0
	passive_ability_id = source.passive_ability_id
	passive_name = source.skill_name
	passive_desc = source.skill_desc
	passive_cooldown = source.skill_cd
	skill_id = source.passive_ability_id
	skill_name = source.skill_name
	skill_desc = source.skill_desc
	skill_cd = source.skill_cd
	primary_weapon = source.primary_weapon
	secondary_weapon = source.secondary_weapon
	melee_weapon = source.melee_weapon
	unlock_score = source.unlock_score
	portrait = String(source.id)
	portrait_texture = null
	visual_base = String(source.visual_base) if source.has_method("visual_base") else String(source.visual_profile)
	palette_tint = Color.WHITE
	accent = _source.palette_color("accent", Color(0.55, 0.78, 0.45))
	dialogue_color = Color(0.86, 0.86, 0.80)
	description = source.description
	soldier_role = &""
	unlock_archive_types = []
	monologue = ""
	language = "zh"
	voice_pitch = 1.0
	rework_passive_id = source.passive_ability_id

## 只读兼容别名（旧 CharacterData 字段）。
func get_max_health() -> int:
	return _source.max_hp


func get_move_speed() -> float:
	return _source.speed
