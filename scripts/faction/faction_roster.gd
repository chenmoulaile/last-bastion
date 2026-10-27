class_name FactionRoster
extends RefCounted
## Data table for the eight faction units. Visuals reuse existing character
## sprite strips + palette tint (no new art), per the art direction.

const UNITS := {
	"horizon_enforcer": {
		"display": "地平线执法者",
		"hp": 190, "speed": 118, "damage": 16, "interval": 1.2, "range": 34.0,
		"visual": "heavy", "tint": Color(0.86, 0.76, 0.56),
		"shield": true, "score": 620,
		"desc": "重甲、盾牌，用声波驱散器把感染者推开。",
	},
	"evidence_destroyer": {
		"display": "证据销毁员",
		"hp": 120, "speed": 152, "damage": 12, "interval": 1.0, "range": 240.0,
		"visual": "assault", "tint": Color(0.92, 0.62, 0.42),
		"burn_archives": true, "score": 560,
		"desc": "携带燃烧弹，优先烧毁档案刷新点。",
	},
	"signal_agent": {
		"display": "信号局特工",
		"hp": 92, "speed": 176, "damage": 14, "interval": 0.85, "range": 270.0,
		"visual": "ninja", "tint": Color(0.60, 0.86, 0.82),
		"silenced": true, "score": 520,
		"desc": "消音武器，主动追踪持有高密级档案的玩家。",
	},
	"signal_jammer": {
		"display": "信号干扰器",
		"hp": 104, "speed": 108, "damage": 7, "interval": 1.4, "range": 180.0,
		"visual": "medic", "tint": Color(0.52, 0.80, 0.78),
		"jammer": true, "score": 480,
		"desc": "部署设备，让区域内的档案碎片暂时无法交互。",
	},
	"rust_enforcer": {
		"display": "锈帮打手",
		"hp": 142, "speed": 150, "damage": 19, "interval": 0.95, "range": 150.0,
		"visual": "assault", "tint": Color(0.82, 0.52, 0.36),
		"score": 460,
		"desc": "改装武器，近距离伤害极高。",
	},
	"rust_trader": {
		"display": "锈帮商人",
		"hp": 110, "speed": 96, "damage": 0, "interval": 2.0, "range": 0.0,
		"visual": "medic", "tint": Color(0.86, 0.70, 0.40),
		"neutral": true, "score": 0,
		"desc": "中立。可以交易，价格随敌意上涨。",
	},
	"remnant_patrol": {
		"display": "残警巡逻兵",
		"hp": 154, "speed": 128, "damage": 13, "interval": 1.15, "range": 66.0,
		"visual": "heavy", "tint": Color(0.56, 0.68, 0.86),
		"shield": true, "score": 500,
		"desc": "防御型，持防暴盾推进。",
	},
	"remnant_sniper": {
		"display": "残警狙击手",
		"hp": 82, "speed": 92, "damage": 30, "interval": 2.1, "range": 430.0,
		"visual": "scout", "tint": Color(0.62, 0.74, 0.92),
		"hunt_specials": true, "score": 540,
		"desc": "远程，优先攻击特殊感染者。",
	},
}


static func has_unit(unit_kind: String) -> bool:
	return UNITS.has(unit_kind)


static func spec(unit_kind: String) -> Dictionary:
	return UNITS.get(unit_kind, UNITS["rust_enforcer"])


static func display_name(unit_kind: String) -> String:
	return String(spec(unit_kind).get("display", unit_kind))


static func all_kinds() -> Array[String]:
	var out: Array[String] = []
	for key in UNITS.keys():
		out.append(String(key))
	return out
