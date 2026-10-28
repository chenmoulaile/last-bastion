class_name ReworkPalettes
extends RefCounted
## ---------------------------------------------------------------------------
## 职责: 10 个角色(6 可玩 + 4 士兵)的配色方案,静态字典,渲染器唯一取色来源。
## 依赖: 无。
## 对外接口:
##   - ReworkPalettes.all() -> Dictionary            (id -> palette)
##   - ReworkPalettes.for_id(id) -> Dictionary       (缺省回退 generic)
##   - ReworkPalettes.with_overrides(base, overrides) (供 .tres 局部覆盖)
## 键约定(渲染器只认这 7 个键):
##   body_primary   躯干主色(作战服)
##   body_secondary 躯干辅色(背心/护具/裤装)
##   skin           皮肤
##   weapon         武器金属色
##   accent         职业强调色(臂章/描边/状态图标)
##   gear           背包/挂件/头盔附件
##   visor          护目镜/面罩反光
## ---------------------------------------------------------------------------

const GENERIC: Dictionary = {
	"body_primary": Color(0.31, 0.36, 0.31),
	"body_secondary": Color(0.22, 0.25, 0.23),
	"skin": Color(0.76, 0.58, 0.44),
	"weapon": Color(0.20, 0.21, 0.24),
	"accent": Color(0.85, 0.85, 0.85),
	"gear": Color(0.26, 0.28, 0.26),
	"visor": Color(0.55, 0.70, 0.80),
}

## 突击兵: 橄榄绿 + 钢灰,标准特种兵配色
const ASSAULT: Dictionary = {
	"body_primary": Color(0.33, 0.40, 0.29),
	"body_secondary": Color(0.24, 0.27, 0.22),
	"skin": Color(0.76, 0.58, 0.44),
	"weapon": Color(0.18, 0.19, 0.22),
	"accent": Color(0.55, 0.78, 0.45),
	"gear": Color(0.28, 0.30, 0.24),
	"visor": Color(0.60, 0.72, 0.60),
}

## 重装兵: 军绿 + 橙(现有 accent 0.95,0.75,0.38),厚重护甲
const HEAVY: Dictionary = {
	"body_primary": Color(0.27, 0.33, 0.23),
	"body_secondary": Color(0.20, 0.24, 0.17),
	"skin": Color(0.72, 0.55, 0.42),
	"weapon": Color(0.16, 0.17, 0.20),
	"accent": Color(0.95, 0.75, 0.38),
	"gear": Color(0.35, 0.36, 0.30),
	"visor": Color(0.90, 0.68, 0.30),
}

## 医疗兵: 灰白 + 红十字色 accent
const MEDIC: Dictionary = {
	"body_primary": Color(0.72, 0.73, 0.70),
	"body_secondary": Color(0.52, 0.54, 0.52),
	"skin": Color(0.80, 0.62, 0.48),
	"weapon": Color(0.22, 0.23, 0.26),
	"accent": Color(0.92, 0.30, 0.30),
	"gear": Color(0.85, 0.86, 0.84),
	"visor": Color(0.70, 0.82, 0.90),
}

## 侦察兵: 深蓝灰 + 青色 accent,轻装
const SCOUT: Dictionary = {
	"body_primary": Color(0.26, 0.33, 0.40),
	"body_secondary": Color(0.19, 0.24, 0.30),
	"skin": Color(0.78, 0.60, 0.46),
	"weapon": Color(0.17, 0.18, 0.21),
	"accent": Color(0.45, 0.82, 0.90),
	"gear": Color(0.30, 0.34, 0.38),
	"visor": Color(0.55, 0.90, 1.00),
}

## 特勤(operative/ninja): 深灰 + 紫,兜帽刺客
const OPERATIVE: Dictionary = {
	"body_primary": Color(0.16, 0.16, 0.20),
	"body_secondary": Color(0.11, 0.11, 0.15),
	"skin": Color(0.70, 0.54, 0.42),
	"weapon": Color(0.13, 0.13, 0.16),
	"accent": Color(0.72, 0.55, 0.90),
	"gear": Color(0.22, 0.20, 0.28),
	"visor": Color(0.80, 0.62, 1.00),
}

## 军官: 卡其 + 金 accent,肩章帽檐
const OFFICER: Dictionary = {
	"body_primary": Color(0.45, 0.42, 0.30),
	"body_secondary": Color(0.33, 0.31, 0.22),
	"skin": Color(0.77, 0.59, 0.45),
	"weapon": Color(0.20, 0.20, 0.23),
	"accent": Color(0.92, 0.80, 0.35),
	"gear": Color(0.38, 0.35, 0.25),
	"visor": Color(0.85, 0.80, 0.55),
}

## 爆破手: 棕绿 + 安全橙,安全帽
const DEMOLITION: Dictionary = {
	"body_primary": Color(0.38, 0.34, 0.25),
	"body_secondary": Color(0.28, 0.25, 0.19),
	"skin": Color(0.74, 0.56, 0.43),
	"weapon": Color(0.19, 0.19, 0.22),
	"accent": Color(0.95, 0.50, 0.20),
	"gear": Color(0.45, 0.36, 0.22),
	"visor": Color(0.90, 0.60, 0.25),
}

## 机枪手: 深军绿 + 黄铜 accent,粗壮
const MG: Dictionary = {
	"body_primary": Color(0.24, 0.30, 0.22),
	"body_secondary": Color(0.18, 0.22, 0.16),
	"skin": Color(0.73, 0.55, 0.42),
	"weapon": Color(0.15, 0.16, 0.19),
	"accent": Color(0.85, 0.70, 0.30),
	"gear": Color(0.30, 0.31, 0.25),
	"visor": Color(0.80, 0.70, 0.35),
}

## 步枪手: 标准陆战队灰绿
const RIFLEMAN: Dictionary = {
	"body_primary": Color(0.30, 0.36, 0.30),
	"body_secondary": Color(0.22, 0.26, 0.22),
	"skin": Color(0.76, 0.58, 0.44),
	"weapon": Color(0.18, 0.19, 0.22),
	"accent": Color(0.60, 0.75, 0.55),
	"gear": Color(0.27, 0.29, 0.25),
	"visor": Color(0.62, 0.74, 0.70),
}

## 战地医疗兵: 沙色 + 白十字
const FIELD_MEDIC: Dictionary = {
	"body_primary": Color(0.55, 0.50, 0.38),
	"body_secondary": Color(0.40, 0.37, 0.28),
	"skin": Color(0.79, 0.61, 0.47),
	"weapon": Color(0.21, 0.22, 0.25),
	"accent": Color(0.95, 0.95, 0.95),
	"gear": Color(0.80, 0.78, 0.72),
	"visor": Color(0.75, 0.85, 0.85),
}

const _TABLE: Dictionary = {
	&"assault": ASSAULT,
	&"heavy": HEAVY,
	&"medic": MEDIC,
	&"scout": SCOUT,
	&"operative": OPERATIVE,
	&"ninja": OPERATIVE,
	&"officer": OFFICER,
	&"demolition": DEMOLITION,
	&"demolisher": DEMOLITION,
	&"mg": MG,
	&"gunner": MG,
	&"rifleman": RIFLEMAN,
	&"field_medic": FIELD_MEDIC,
	&"medic_soldier": FIELD_MEDIC,
}


static func all() -> Dictionary:
	return _TABLE


static func for_id(id: StringName) -> Dictionary:
	return _TABLE.get(id, GENERIC)


static func with_overrides(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var merged: Dictionary = base.duplicate()
	merged.merge(overrides, true)
	return merged
