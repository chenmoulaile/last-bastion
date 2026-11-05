class_name BossEngine
extends RefCounted
## wp7-boss-rework：统一 Boss 引擎。每个关卡的 Boss 由 LEVEL_CFG 里一份配置驱动
##（名字 / 外观图集 / HP / 2-3 个带前摇与安全位的招牌招式 / 50% 血阶段变化 /
## 死亡奖励掉落），行为全部构建在 ZombieBase 框架上（level_runner.gd 零改动）。
##
## 接入方式：6 个 boss kind 场景脚本（zombie_tank / boss_armored_car /
## boss_nest_mother / boss_ironface / boss_signal_core / zombie_charger）在
## _ready 调 BossEngine.setup(self)，_ai_tick / apply_damage / _on_death_effect
## 委托 BossEngine.tick / mitigate / on_damaged / on_death。zombie_charger 仅在
## LEVEL_CFG 命中（l07/l08）时走 boss 模式，其余关卡保持普通特感 AI。
##
## 前摇提示 = TelegraphRing / TelegraphLine 地面预警（时长=前摇）+ 招式段动画 +
## 闪红 + 音效 + 每招本战首次 notify（含安全位说明）。安全位 = 每招几何判定
##（范围圈 / 直线弹道 / 落点圈），跳起（y 差 >Y_BAND）或离开预警区即免伤。
## 阶段 = 血量阈值触发：notify + 变色 + 速度/冷却乘区 + 追加新招（换招）。
## 死亡 = drop_boss_loot（医疗/弹药/手雷/金币）+ 按章节追加金币。

# ---------------------------------------------------------------- 配置表 ----
# KIND_CFG：kind 级兜底（关卡不在 LEVEL_CFG 时使用，如测试直接 spawn_boss）。
const KIND_CFG := {
	&"tank": "l10",
	&"armored_car": "l05",
	&"nest_mother": "l02",
	&"ironface": "l09",
	&"signal_core": "l11",
}

# LEVEL_CFG：11 关各一份。字段：
#   name           Boss 名（运行时覆写 data.display_name，HUD 血条/出场文案同步）
#   hp             最大生命（普通僵尸 39HP 的 61.5~107.7 倍，按关卡递增）
#   prefix/size/scale/tint   外观：图集前缀 / 帧尺寸 / 显示缩放 / 染色
#   collision      碰撞盒尺寸
#   role           melee 追击 / kite 保持距离 / stationary 站桩
#   kite_min/max   role=kite 的保持距离带
#   moves          招式表（2-3 个）：id/anim/windup/cooldown/min_r/max_r/weight/
#                  type/dmg/sfx/hint（hint 写安全位，首次前摇时 notify）
#   phases         阶段表：血量阈值触发（各关均有 ≤50% 档）
#   interference   战斗期间信号干扰（l11 专属）
#   armor          运行时减伤/弱点（l05 装甲 / l02 l06 巢母 50% 前减伤 / l09 正面免伤）
const LEVEL_CFG := {
	"l01": {
		"name": "锈钩屠夫", "hp": 2400, "prefix": "riot", "size": Vector2i(48, 48),
		"scale": 1.3, "tint": Color(0.82, 0.38, 0.34), "collision": Vector2(26, 42),
		"role": "melee",
		"intro": "锈钩屠夫现身——钩链拉人、横扫近身，保持距离！",
		"moves": [
			{"id": "hook_pull", "anim": "atk_lunge", "windup": 0.7, "cooldown": 6.5,
				"min_r": 140.0, "max_r": 330.0, "weight": 1.0, "type": "pull",
				"dmg": 22, "sfx": &"smoker_tongue",
				"hint": "钩链拉拽——离开红色弹道或躲到掩体后！"},
			{"id": "cleave", "anim": "atk_smash", "windup": 0.5, "cooldown": 4.0,
				"min_r": 0.0, "max_r": 150.0, "weight": 1.4, "type": "slam",
				"dmg": 34, "radius": 130.0, "knock": Vector2(300, -120), "sfx": &"melee_swing",
				"hint": "横扫——后撤出红圈或跳起躲避！"},
		],
		"phases": [{"below": 0.5, "notify": "锈钩屠夫咆哮着进入狂怒——新增践踏！",
			"tint": Color(1.0, 0.45, 0.38), "speed_mult": 1.25, "cd_mult": 0.75,
			"add": [{"id": "quake_stomp", "anim": "atk_smash", "windup": 0.75,
				"cooldown": 7.0, "min_r": 0.0, "max_r": 220.0, "weight": 1.2, "type": "slam",
				"dmg": 46, "radius": 190.0, "knock": Vector2(260, -280), "sfx": &"tank_punch",
				"hint": "践踏——冲出红圈或跳起！"}]}],
	},
	"l02": {
		"name": "码头巢母", "hp": 2520, "prefix": "boomer", "size": Vector2i(48, 48),
		"scale": 1.55, "tint": Color(0.62, 0.86, 0.52), "collision": Vector2(44, 52),
		"role": "stationary",
		"intro": "码头巢母扎根码头——孢子减速、召唤 brood、孢子池封锁！",
		"armor": {"pre50_reduce": 0.3},
		"moves": [
			{"id": "spore_scream", "anim": "attack", "windup": 0.6, "cooldown": 9.0,
				"min_r": 0.0, "max_r": 430.0, "weight": 1.0, "type": "spores",
				"slow": 2.5, "sfx": &"zombie_scream_2",
				"hint": "孢子尖啸——冲出范围免于减速！"},
			{"id": "brood", "anim": "attack", "windup": 0.9, "cooldown": 11.0,
				"min_r": 0.0, "max_r": 9999.0, "weight": 0.9, "type": "summon",
				"count": 2, "sfx": &"boomer_burp", "hint": "召唤孢子群——优先击杀增援！"},
			{"id": "acid_pool", "anim": "attack", "windup": 0.8, "cooldown": 8.0,
				"min_r": 90.0, "max_r": 420.0, "weight": 1.0, "type": "acid",
				"radius": 80.0, "duration": 4.0, "sfx": &"acid_splash",
				"hint": "孢子池——离开落点红圈！"},
		],
		"phases": [{"below": 0.5, "notify": "码头巢母的菌毯沸腾了——召唤更多、更快！",
			"tint": Color(0.5, 1.0, 0.4), "cd_mult": 0.8, "count_bonus": 1}],
	},
	"l03": {
		"name": "锈蚀尖啸者", "hp": 2640, "prefix": "witch", "size": Vector2i(64, 72),
		"scale": 1.05, "tint": Color(0.8, 0.7, 0.95), "collision": Vector2(30, 52),
		"role": "kite", "kite_min": 260.0, "kite_max": 430.0,
		"intro": "锈蚀尖啸者鸣响——尖啸减速、召唤尸群、回声波直线弹道！",
		"moves": [
			{"id": "shriek", "anim": "scream", "windup": 0.5, "cooldown": 7.0,
				"min_r": 0.0, "max_r": 430.0, "weight": 1.0, "type": "spores",
				"slow": 3.0, "sfx": &"witch_scream", "hint": "尖啸——冲出范围免于减速！"},
			{"id": "call_swarm", "anim": "attack", "windup": 0.8, "cooldown": 10.0,
				"min_r": 0.0, "max_r": 9999.0, "weight": 0.9, "type": "summon",
				"count": 2, "sfx": &"zombie_scream", "hint": "召唤尸群——保持火力压制！"},
			{"id": "echo_wave", "anim": "atk_lunge", "windup": 0.7, "cooldown": 6.0,
				"min_r": 120.0, "max_r": 470.0, "weight": 1.2, "type": "wave",
				"length": 470.0, "dmg": 14, "slow": 2.0, "sfx": &"witch_attack",
				"hint": "回声波——垂直跳出红色弹道！"},
		],
		"phases": [{"below": 0.5, "notify": "尖啸声变成金属摩擦——狂乱尖啸与更多尸群！",
			"tint": Color(0.95, 0.55, 0.95), "cd_mult": 0.8, "count_bonus": 1,
			"add": [{"id": "shriek2", "anim": "scream", "windup": 0.45, "cooldown": 7.0,
				"min_r": 0.0, "max_r": 470.0, "weight": 1.3, "type": "spores",
				"slow": 2.5, "dmg": 20, "sfx": &"witch_scream",
				"hint": "狂乱尖啸——出范围且远离本体！"}]}],
	},
	"l04": {
		"name": "废墟暴君", "hp": 2760, "prefix": "hardhat", "size": Vector2i(48, 48),
		"scale": 1.7, "tint": Color(0.86, 0.74, 0.46), "collision": Vector2(38, 52),
		"role": "melee",
		"intro": "废墟暴君推着残墙前进——横扫与抛掷，小心落点！",
		"moves": [
			{"id": "wreck_swing", "anim": "atk_smash", "windup": 0.6, "cooldown": 4.2,
				"min_r": 0.0, "max_r": 155.0, "weight": 1.4, "type": "slam",
				"dmg": 40, "radius": 140.0, "knock": Vector2(320, -140), "sfx": &"melee_swing",
				"hint": "重锤横扫——后撤或跳起！"},
			{"id": "rubble_throw", "anim": "atk_lunge", "windup": 0.7, "cooldown": 7.0,
				"min_r": 150.0, "max_r": 720.0, "weight": 1.0, "type": "lob",
				"dmg": 36, "radius": 120.0, "sfx": &"throw",
				"hint": "抛掷废墟——离开落点红圈！"},
		],
		"phases": [{"below": 0.5, "notify": "废墟暴君掀翻了残墙——新增震地！",
			"tint": Color(1.0, 0.62, 0.38), "speed_mult": 1.3, "cd_mult": 0.8,
			"add": [{"id": "ground_slam", "anim": "atk_smash", "windup": 0.8,
				"cooldown": 7.0, "min_r": 0.0, "max_r": 230.0, "weight": 1.2, "type": "slam",
				"dmg": 46, "radius": 200.0, "knock": Vector2(280, -300), "sfx": &"tank_punch",
				"hint": "震地——冲出红圈或跳起！"}]}],
	},
	"l05": {
		"name": "铁蹄", "hp": 3120, "prefix": "charger", "size": Vector2i(60, 60),
		"scale": 1.05, "tint": Color(0.72, 0.72, 0.76), "collision": Vector2(40, 46),
		"role": "melee",
		"intro": "铁蹄点火——正面装甲减伤 85%，冲撞撞墙或攒够命中暴露弱点！",
		"armor": {"hits_to_expose": 12, "expose_time": 2.5, "expose_mult": 4.0,
			"front_reduce": 0.85},
		"moves": [
			{"id": "ram", "anim": "charge", "windup": 0.8, "cooldown": 7.0,
				"min_r": 0.0, "max_r": 620.0, "weight": 1.0, "type": "charge",
				"speed": 560.0, "duration": 0.95, "dmg": 30,
				"knock": Vector2(340, -320), "sfx": &"charger_charge",
				"hint": "冲撞——跳出红色直线或贴身绕后！"},
			{"id": "mortar", "anim": "atk_lunge", "windup": 0.7, "cooldown": 8.0,
				"min_r": 220.0, "max_r": 720.0, "weight": 1.0, "type": "lob",
				"dmg": 30, "radius": 110.0, "sfx": &"throw",
				"hint": "车载迫击——离开落点红圈！"},
		],
		"phases": [{"below": 0.5, "notify": "铁蹄引擎过载——装甲变脆、冲撞更频繁！",
			"tint": Color(0.95, 0.72, 0.55), "speed_mult": 1.25, "cd_mult": 0.75,
			"armor_override": {"front_reduce": 0.6}}],
	},
	"l06": {
		"name": "沼气母巢", "hp": 3180, "prefix": "boomer", "size": Vector2i(48, 48),
		"scale": 1.55, "tint": Color(0.9, 0.72, 0.4), "collision": Vector2(44, 52),
		"role": "stationary",
		"intro": "沼气母巢膨胀——毒雾、催生自爆体、胆汁三连喷，别站桩！",
		"armor": {"pre50_reduce": 0.3},
		"moves": [
			{"id": "gas_cloud", "anim": "attack", "windup": 0.7, "cooldown": 9.0,
				"min_r": 220.0, "max_r": 520.0, "weight": 1.1, "type": "acid",
				"radius": 130.0, "duration": 5.0, "bridge": 0.85, "sfx": &"acid_splash",
				"hint": "毒雾喷发——离开你和它之间的红圈！"},
			{"id": "bloater", "anim": "attack", "windup": 0.9, "cooldown": 12.0,
				"min_r": 0.0, "max_r": 9999.0, "weight": 0.9, "type": "summon",
				"count": 1, "summon_kind": &"boomer", "sfx": &"boomer_burp",
				"hint": "催生自爆体——提前击杀防止爆炸！"},
			{"id": "bile_spit", "anim": "atk_smash", "windup": 0.6, "cooldown": 7.0,
				"min_r": 220.0, "max_r": 560.0, "weight": 1.0, "type": "volley_lob",
				"count": 3, "radius": 55.0, "acid_mode": true, "duration": 3.5,
				"sfx": &"bile_splash", "hint": "胆汁三连喷——移动离开落点！"},
		],
		"phases": [{"below": 0.5, "notify": "沼气母巢胀裂——催生更多自爆体！",
			"tint": Color(1.0, 0.85, 0.4), "cd_mult": 0.8, "count_bonus": 1}],
	},
	"l07": {
		"name": "泵站迫击兽", "hp": 3240, "prefix": "spitter", "size": Vector2i(48, 48),
		"scale": 1.35, "tint": Color(0.55, 0.9, 0.55), "collision": Vector2(30, 44),
		"role": "kite", "kite_min": 380.0, "kite_max": 640.0,
		"intro": "泵站迫击兽供压就绪——弹幕与酸池封锁走位，贴近它会推开你！",
		"moves": [
			{"id": "mortar_volley", "anim": "spit", "windup": 0.8, "cooldown": 8.0,
				"min_r": 240.0, "max_r": 780.0, "weight": 1.2, "type": "volley_lob",
				"count": 3, "radius": 100.0, "dmg": 30, "sfx": &"spitter_hiss",
				"hint": "迫击弹幕——连续移动离开落点红圈！"},
			{"id": "acid_line", "anim": "spit", "windup": 0.7, "cooldown": 9.0,
				"min_r": 200.0, "max_r": 640.0, "weight": 1.0, "type": "acid",
				"radius": 90.0, "duration": 4.5, "bridge": 0.8, "sfx": &"acid_splash",
				"hint": "酸液封锁——绕开道路上的绿池！"},
			{"id": "repel_pulse", "anim": "atk_smash", "windup": 0.5, "cooldown": 5.0,
				"min_r": 0.0, "max_r": 175.0, "weight": 1.0, "type": "slam",
				"dmg": 22, "radius": 170.0, "knock": Vector2(430, -160), "sfx": &"melee_swing",
				"hint": "排斥脉冲——保持距离，别贴脸！"},
		],
		"phases": [{"below": 0.5, "notify": "供弹管爆裂——弹幕密度上升！",
			"tint": Color(0.7, 1.0, 0.5), "cd_mult": 0.8, "count_bonus": 1}],
	},
	"l08": {
		"name": "净化区处刑者", "hp": 3360, "prefix": "hunter", "size": Vector2i(48, 48),
		"scale": 1.3, "tint": Color(0.65, 0.75, 0.9), "collision": Vector2(28, 44),
		"role": "melee",
		"intro": "净化区处刑者跃入战场——扑击落点与连爪，注意红圈！",
		"moves": [
			{"id": "leap_slam", "anim": "pounce", "windup": 0.55, "cooldown": 5.5,
				"min_r": 110.0, "max_r": 430.0, "weight": 1.2, "type": "leap",
				"dmg": 34, "radius": 180.0, "knock": Vector2(280, -200), "sfx": &"hunter_pounce",
				"hint": "扑击重压——离开落点红圈！"},
			{"id": "flurry", "anim": "atk_scratch", "windup": 0.4, "cooldown": 4.0,
				"min_r": 0.0, "max_r": 115.0, "weight": 1.0, "type": "multihit",
				"hits": 3, "dmg": 12, "interval": 0.25, "radius": 115.0, "sfx": &"zombie_attack",
				"hint": "连爪——后撤出范围，段与段之间可脱身！"},
			{"id": "howl", "anim": "attack", "windup": 0.7, "cooldown": 11.0,
				"min_r": 0.0, "max_r": 9999.0, "weight": 0.8, "type": "summon",
				"count": 1, "sfx": &"hunter_scream",
				"hint": "嚎叫唤援——注意新增感染者的位置！"},
		],
		"phases": [{"below": 0.5, "notify": "处刑者进入嗜血——移动更快、扑击范围扩大！",
			"tint": Color(0.95, 0.5, 0.55), "speed_mult": 1.4, "cd_mult": 0.8,
			"radius_bonus": 40.0}],
	},
	"l09": {
		"name": "铁面", "hp": 3420, "prefix": "riot", "size": Vector2i(48, 48),
		"scale": 1.2, "tint": Color(0.62, 0.7, 0.85), "collision": Vector2(26, 44),
		"role": "melee",
		"intro": "铁面举盾推进——正面免伤，绕背或用爆炸物/火焰打破防！",
		"armor": {"front_immune": true},
		"moves": [
			{"id": "shield_bash", "anim": "atk_smash", "windup": 0.5, "cooldown": 4.5,
				"min_r": 0.0, "max_r": 135.0, "weight": 1.3, "type": "slam",
				"front": true, "dmg": 30, "radius": 120.0, "knock": Vector2(360, -180),
				"sfx": &"metal_hit", "hint": "盾击只打正面——绕到背后！"},
			{"id": "sidearm", "anim": "attack", "windup": 0.6, "cooldown": 6.0,
				"min_r": 160.0, "max_r": 580.0, "weight": 1.0, "type": "volley_shot",
				"count": 3, "dmg": 8, "interval": 0.22, "sfx": &"m9",
				"hint": "压制点射——利用掩体断视线或跳起！"},
			{"id": "call_guards", "anim": "attack", "windup": 0.9, "cooldown": 13.0,
				"min_r": 0.0, "max_r": 9999.0, "weight": 0.8, "type": "summon",
				"count": 1, "summon_kind": &"riot", "sfx": &"zombie_scream_2",
				"hint": "呼叫残党——优先清增援！"},
		],
		"phases": [{"below": 0.5, "notify": "铁面丢弃盾牌——正面护甲失效，进入狂暴！",
			"tint": Color(1.2, 0.8, 0.8), "speed_mult": 1.35, "cd_mult": 0.75,
			"clear_front_immune": true,
			"add": [{"id": "double_slam", "anim": "atk_smash", "windup": 0.65,
				"cooldown": 6.0, "min_r": 0.0, "max_r": 175.0, "weight": 1.2, "type": "slam",
				"dmg": 38, "radius": 170.0, "knock": Vector2(300, -240), "sfx": &"tank_punch",
				"hint": "狂暴重砸——后撤或跳起！"}]}],
	},
	"l10": {
		"name": "坦克", "hp": 3600, "prefix": "tank", "size": Vector2i(96, 96),
		"scale": 1.0, "tint": Color(1.0, 1.0, 1.0), "collision": Vector2(40, 56),
		"role": "melee",
		"intro": "TANK！重拳与投石——50% 血狂怒加速！",
		"moves": [
			{"id": "punch", "anim": "punch", "windup": 0.42, "cooldown": 2.6,
				"min_r": 0.0, "max_r": 110.0, "weight": 1.3, "type": "slam",
				"dmg": 29, "radius": 95.0, "knock": Vector2(260, -260), "sfx": &"tank_punch",
				"hint": "重拳——后撤出范围！"},
			{"id": "throw", "anim": "throw", "windup": 0.6, "cooldown": 5.5,
				"min_r": 140.0, "max_r": 720.0, "weight": 1.0, "type": "lob",
				"dmg": 36, "radius": 85.0, "predict": 0.35, "sfx": &"throw",
				"hint": "投石——离开落点红圈！"},
		],
		"phases": [{"below": 0.5, "notify": "TANK 狂怒了——拳头更密、移动更快！",
			"tint": Color(1.15, 0.75, 0.7), "speed_mult": 1.35, "cd_mult": 0.7}],
	},
	"l11": {
		"name": "信号核心·终焉体", "hp": 4200, "prefix": "witch", "size": Vector2i(64, 72),
		"scale": 1.2, "tint": Color(0.85, 0.6, 1.0), "collision": Vector2(36, 58),
		"role": "stationary", "interference": true,
		"intro": "信号核心·终焉体上线——三阶段形态，随血量换招！",
		"moves": [
			{"id": "echo_wave", "anim": "atk_lunge", "windup": 0.65, "cooldown": 6.0,
				"min_r": 120.0, "max_r": 520.0, "weight": 1.2, "type": "wave",
				"length": 520.0, "dmg": 20, "slow": 2.0, "sfx": &"witch_attack",
				"hint": "回声波——垂直跳出红色弹道！"},
			{"id": "summon", "anim": "attack", "windup": 0.8, "cooldown": 9.0,
				"min_r": 0.0, "max_r": 9999.0, "weight": 1.0, "type": "summon",
				"count": 2, "sfx": &"zombie_scream", "hint": "信号召唤——优先清增援！"},
		],
		"phases": [
			{"below": 0.66, "notify": "信号核心——第二形态：武器挂架展开！",
				"tint": Color(1.1, 0.75, 1.05),
				"add": [
					{"id": "mortar_volley", "anim": "spit", "windup": 0.75, "cooldown": 8.0,
						"min_r": 180.0, "max_r": 780.0, "weight": 1.2, "type": "volley_lob",
						"count": 3, "radius": 100.0, "dmg": 30, "sfx": &"spitter_hiss",
						"hint": "样本库弹幕——连续移动离开落点！"},
					{"id": "drain", "anim": "attack", "windup": 0.3, "cooldown": 4.0,
						"min_r": 0.0, "max_r": 9999.0, "weight": 0.7, "type": "drain",
						"radius": 280.0, "sfx": &"boomer_burp",
						"hint": "吸收尸体回血——射击尸体点阻止它！"}]},
			{"below": 0.33, "notify": "信号核心——终焉形态：全面狂暴！",
				"tint": Color(1.25, 0.5, 0.55), "cd_mult": 0.7, "count_bonus": 1,
				"add": [{"id": "death_scream", "anim": "scream", "windup": 0.5,
					"cooldown": 6.0, "min_r": 0.0, "max_r": 470.0, "weight": 1.3,
					"type": "spores", "dmg": 15, "slow": 3.0, "sfx": &"witch_scream",
					"hint": "终焉尖啸——出范围免于减速与伤害！"}]},
		],
	},
}

const Y_BAND := 52.0        # 玩家跳起（y 差超此值）可躲范围招
const LOB_FLIGHT := 0.55    # 投掷物滞空秒数
const VOLLEY_GAP := 0.25    # 连发默认间隔


class BossMind extends RefCounted:
	## 每个 boss 实例一份运行时状态（挂在宿主 _mind）。
	var cfg: Dictionary
	var state: String = "chase"
	var windup: float = 0.0
	var recover: float = 0.0
	var phase: int = 0
	var moves: Array = []              # 运行时招式表（含 cd 剩余）
	var notified: Dictionary = {}      # 招式首次提示
	var active: Dictionary = {}        # 当前前摇/结算中的招式
	var volley_left: int = 0
	var volley_timer: float = 0.0
	var volley_params: Dictionary = {}
	var charge_hit: bool = false       # l05 冲撞是否已命中（一次冲撞只结算一次）
	var exposed: float = 0.0           # l05 弱点暴露期
	var hits_since: int = 0            # l05 弱点命中计数
	var telegraph: Node2D = null


## 内部类：地面圆形预警（渐显红圈 + 边界弧）。
class TelegraphRing extends Node2D:
	var radius: float = 60.0
	var duration: float = 0.5
	var t: float = 0.0

	func _process(delta: float) -> void:
		t += delta
		if t >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var p := clampf(t / maxf(0.01, duration), 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius, Color(0.9, 0.15, 0.1, 0.10 + 0.10 * p))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(1.0, 0.25, 0.2, 0.65), 2.0, true)
		draw_arc(Vector2.ZERO, radius * p, 0.0, TAU, 40, Color(1.0, 0.45, 0.3, 0.5), 3.0, true)


## 内部类：直线弹道预警（矩形条）。
class TelegraphLine extends Node2D:
	var length: float = 300.0
	var width: float = 70.0
	var duration: float = 0.5
	var t: float = 0.0

	func _process(delta: float) -> void:
		t += delta
		if t >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var p := clampf(t / maxf(0.01, duration), 0.0, 1.0)
		draw_rect(Rect2(0.0, -width * 0.5, length * p, width), Color(0.9, 0.15, 0.1, 0.12 + 0.10 * p))
		draw_rect(Rect2(0.0, -width * 0.5, length, width), Color(1.0, 0.25, 0.2, 0.55), false, 2.0)


## 内部类：投掷物（抛物线 crate/酸团）。落地对玩家与盟友结算——修复
## spawn_tank_rock 爆炸只结算给僵尸组、打不到玩家的旧限制（boss 招式专用）。
class BossLob extends Node2D:
	var level: Node = null
	var to: Vector2 = Vector2.ZERO
	var radius: float = 100.0
	var dmg: int = 30
	var knock: Vector2 = Vector2(220, -140)
	var acid_mode: bool = false
	var acid_duration: float = 4.0

	func _ready() -> void:
		z_index = 22
		var tex: Texture2D = null
		if not acid_mode:
			tex = SpriteLibrary.prop_texture("crate")
		if tex != null:
			var s := Sprite2D.new()
			s.texture = tex
			s.scale = Vector2(0.7, 0.7)
			add_child(s)
		else:
			modulate = Color(0.8, 1.0, 0.5, 0.9)

	func launch(from: Vector2, target: Vector2, flight: float) -> void:
		var mid := Vector2((from.x + target.x) * 0.5, minf(from.y, target.y) - 110.0)
		position = from
		var tw := create_tween()
		tw.tween_property(self, "position", mid, flight * 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_property(self, "position", target, flight * 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(_impact)

	func _impact() -> void:
		if level != null and is_instance_valid(level):
			if acid_mode:
				AudioManager.play_sfx_2d(&"acid_splash", to, 900.0)
				Fx.acid(level.fx_layer, to)
				level.call("spawn_acid_zone", to, radius, acid_duration, 18.0)
			else:
				AudioManager.play_sfx_2d(&"explosion", to, 1000.0)
				Fx.explosion(level.fx_layer, to, 1.1)
				EventBus.shake(4.0)
				BossEngine.melee_area(level, to, radius, dmg, knock)
		queue_free()


# ------------------------------------------------------------- 接入 API ----
## 在宿主 _ready（super() 之后）调用：按关卡（其次按 kind 兜底）取配置，覆写
## 外观/名字/HP/碰撞，挂 BossMind。返回配置（宿主存 _bcfg；空 = 走原生 AI）。
static func setup(z: ZombieBase) -> Dictionary:
	var level_id := ""
	if z.level != null and z.level.get("data") != null:
		level_id = String(z.level.data.id)
	var cfg: Dictionary = {}
	if LEVEL_CFG.has(level_id):
		cfg = LEVEL_CFG[level_id]
	else:
		var kind := String(z.data.id)
		if KIND_CFG.has(StringName(kind)):
			cfg = LEVEL_CFG[KIND_CFG[StringName(kind)]]
	if cfg.is_empty():
		return {}
	var mind := BossMind.new()
	mind.cfg = cfg
	for m in cfg.get("moves", []):
		var mm: Dictionary = m.duplicate(true)
		mm["cd"] = randf_range(1.2, 2.6)
		mind.moves.append(mm)
	z.set("_mind", mind)
	z.set("_bcfg", cfg)
	# —— 外观覆写（共享 Resource 按关覆写：display_name 供 HUD 血条/出场文案用）——
	z.data.display_name = String(cfg.get("name", z.data.display_name))
	var prefix := String(cfg.get("prefix", z.data.sprite_prefix))
	var size: Vector2i = cfg.get("size", z.data.sprite_size)
	var sc: float = cfg.get("scale", 1.0)
	z.data.sprite_prefix = prefix
	z.data.sprite_size = size
	z.data.collision_size = cfg.get("collision", z.data.collision_size)
	z._visual_prefix = prefix
	z.sprite.sprite_frames = SpriteLibrary.zombie_frames(prefix, size)
	z.sprite.position = Vector2(0, -float(size.y) * 0.5 * sc)
	z.sprite.scale = Vector2(sc, sc)
	z._base_tint = cfg.get("tint", z.data.tint)
	z.sprite.modulate = z._base_tint
	if z.collision != null and z.collision.shape is RectangleShape2D:
		var rect: RectangleShape2D = z.collision.shape
		rect.size = z.data.collision_size
		z.collision.position = Vector2(0, -z.data.collision_size.y * 0.5)
	# —— HP：关卡递增基准 × 难度系数（NORMAL 1.0 / HARD 4/3 / EXPERT 5/3，
	# 与 zombie_base 对 tank 的既有难度系数一致）——
	var diff := GameManager.current_difficulty
	var mult := 1.0
	if diff == &"HARD":
		mult = 4.0 / 3.0
	elif diff == &"EXPERT":
		mult = 5.0 / 3.0
	z.max_health = int(round(float(cfg.get("hp", z.data.max_hp)) * mult))
	z.health = z.max_health
	z.collision_layer = 16
	EventBus.notify.emit("【BOSS】%s" % String(cfg.get("intro", cfg.get("name", ""))))
	EventBus.shake(4.0)
	if cfg.get("interference", false):
		EventBus.signal_interference.emit(true)
	return cfg


## 宿主 _ai_tick 委托入口。
static func tick(z: ZombieBase, delta: float) -> void:
	var mind: BossMind = z.get("_mind")
	if mind == null:
		return
	_update_phase(z, mind)
	if mind.exposed > 0.0:
		mind.exposed = maxf(0.0, mind.exposed - delta)
	for m in mind.moves:
		m["cd"] = maxf(0.0, float(m.get("cd", 0.0)) - delta)
	match mind.state:
		"windup":
			mind.windup -= delta
			_stop(z, delta)
			z.face_toward_target()
			if mind.windup <= 0.0:
				var move := mind.active
				mind.active = {}
				mind.state = "chase"
				_finish_move(z, mind, move)
		"recover":
			mind.recover -= delta
			_stop(z, delta)
			z._play_anim("idle")
			if mind.recover <= 0.0:
				mind.state = "chase"
		"charge":
			_tick_charge(z, mind, delta)
		"leap":
			# 跳跃由重力完成；落地瞬间结算扑击重压
			if z.is_on_floor() and z.velocity.y >= 0.0:
				var move: Dictionary = mind.active
				mind.active = {}
				_leap_impact(z, mind, move)
				mind.state = "recover"
				mind.recover = 0.8
		_:
			_tick_chase(z, mind, delta)
	# 连发（投掷/点射）独立于主状态推进
	_volley_tick(z, mind, delta)
	_visual_state(z, mind)


## 受伤管线（宿主 apply_damage 在 super 之前调用）：正面免伤 / 减伤 / 弱点计数。
## 返回调整后伤害；返回 0 表示被完全格挡（宿主直接 return）。
static func mitigate(z: ZombieBase, amount: int, from_dir: Vector2,
		damage_type: StringName) -> int:
	var mind: BossMind = z.get("_mind")
	if mind == null:
		return amount
	var armor := _armor(mind)
	if armor.get("front_immune", false) and damage_type != &"explosion" \
			and damage_type != &"fire" and from_dir.length() > 0.01 \
			and signf(from_dir.normalized().x) == signf(float(z.facing)):
		Fx.spark(z.level.fx_layer if z.level else z.get_parent(),
			z.global_position + Vector2(z.facing * 16.0, -22.0))
		AudioManager.play_sfx_2d(&"ricochet", z.global_position, 600.0)
		z.alerted = true
		return 0
	if mind.exposed > 0.0:
		return amount * int(armor.get("expose_mult", 4.0))
	var hits_to_expose := int(armor.get("hits_to_expose", 0))
	if hits_to_expose > 0:
		mind.hits_since += 1
		if mind.hits_since >= hits_to_expose:
			mind.hits_since = 0
			mind.exposed = float(armor.get("expose_time", 2.5))
			EventBus.notify.emit("%s 装甲被击穿——弱点暴露，火力全开！" % mind.cfg.get("name", ""))
			AudioManager.play_sfx_2d(&"metal_hit", z.global_position, 900.0)
	var reduce := float(armor.get("front_reduce", 0.0)) + float(armor.get("pre50_reduce", 0.0))
	if reduce > 0.0:
		return maxi(1, int(round(float(amount) * (1.0 - clampf(reduce, 0.0, 0.95)))))
	return amount


## 受伤后刷新 HUD 血条（宿主 super.apply_damage 之后、未死时调用）。
static func on_damaged(z: ZombieBase) -> void:
	EventBus.boss_health_changed.emit(z.health, z.max_health)


## 死亡管线（宿主 _on_death_effect 调用）：奖励掉落 + 收尾特效。
static func on_death(z: ZombieBase) -> void:
	var mind: BossMind = z.get("_mind")
	var cfg: Dictionary = mind.cfg if mind != null else {}
	if cfg.get("interference", false):
		EventBus.signal_interference.emit(false)
	if z.level == null:
		return
	z.level.drop_boss_loot(z.global_position)
	var chapter := 1
	if z.level.get("data") != null:
		chapter = maxi(1, int(z.level.data.chapter))
	z.level.call("_spawn_pickup", "gold", z.global_position + Vector2(18, -8), chapter * 400)
	Fx.explosion(z.level.fx_layer, z.global_position + Vector2(0, -24), 1.6)
	Fx.blood(z.level.fx_layer, z.global_position + Vector2(0, -24), Vector2.UP, 2.0)
	EventBus.shake(7.0)
	EventBus.notify.emit("%s 被击杀——掉落了战利品！" % String(cfg.get("name", "BOSS")))


# ------------------------------------------------------------ 行为细节 ----
static func _armor(mind: BossMind) -> Dictionary:
	var armor: Dictionary = mind.cfg.get("armor", {}).duplicate()
	for i in mind.phase:
		var ph := _phase(mind, i)
		if ph.has("armor_override"):
			armor.merge(ph["armor_override"], true)
		if ph.has("clear_front_immune"):
			armor["front_immune"] = false
	return armor


static func _phase(mind: BossMind, i: int) -> Dictionary:
	var phs: Array = mind.cfg.get("phases", [])
	if i >= 0 and i < phs.size():
		return phs[i]
	return {}


static func _update_phase(z: ZombieBase, mind: BossMind) -> void:
	var ratio := float(z.health) / float(maxi(1, z.max_health))
	var phs: Array = mind.cfg.get("phases", [])
	while mind.phase < phs.size() and ratio < float(_phase(mind, mind.phase).get("below", 0.5)):
		var ph := _phase(mind, mind.phase)
		mind.phase += 1
		EventBus.notify.emit(String(ph.get("notify", "BOSS 进入新阶段！")))
		EventBus.screen_shake.emit(4.0)
		AudioManager.play_sfx_2d(&"zombie_scream_2", z.global_position, 1300.0, 0.0)
		z._base_tint = ph.get("tint", z._base_tint)
		z.sprite.modulate = z._base_tint
		var cd_mult: float = ph.get("cd_mult", 1.0)
		for m in ph.get("add", []):
			var mm: Dictionary = m.duplicate(true)
			mm["cd"] = randf_range(0.8, 2.0)
			mind.moves.append(mm)
		for m in mind.moves:
			m["cd"] = float(m.get("cd", 0.0)) * cd_mult


static func _speed_mult(mind: BossMind) -> float:
	var mult := 1.0
	for i in mind.phase:
		mult *= float(_phase(mind, i).get("speed_mult", 1.0))
	return mult


static func _tick_chase(z: ZombieBase, mind: BossMind, delta: float) -> void:
	if z.target == null or not is_instance_valid(z.target):
		z._wander(delta)
		return
	var move := _pick_move(z, mind)
	if not move.is_empty():
		_start_move(z, mind, move, delta)
		return
	var speed_mult := _speed_mult(mind)
	match String(mind.cfg.get("role", "melee")):
		"stationary":
			_stop(z, delta)
			z._play_anim("idle")
		"kite":
			var dx := absf(z.target.global_position.x - z.global_position.x)
			z.face_toward_target()
			if dx < float(mind.cfg.get("kite_min", 300.0)):
				z.velocity.x = move_toward(z.velocity.x,
					-float(z.facing) * z.data.walk_speed_max * 0.7 * speed_mult, 600.0 * delta)
				z._play_anim("run")
			elif dx > float(mind.cfg.get("kite_max", 500.0)):
				z.chase_target(delta, speed_mult, "run")
			else:
				_stop(z, delta)
				z._play_anim("idle")
		_:
			z.chase_target(delta, speed_mult, "run")


static func _pick_move(z: ZombieBase, mind: BossMind) -> Dictionary:
	if z.target == null or not is_instance_valid(z.target):
		return {}
	var dist := z.distance_to_target()
	var pool: Array = []
	for m in mind.moves:
		if float(m.get("cd", 0.0)) > 0.0:
			continue
		if dist < float(m.get("min_r", 0.0)) - 1.0 or dist > float(m.get("max_r", 9999.0)) + 1.0:
			continue
		if String(m.get("type", "")) in ["volley_shot", "lob", "volley_lob"] \
				and not z.has_line_of_sight_to_target():
			continue
		pool.append([float(m.get("weight", 1.0)), m])
	if pool.is_empty():
		return {}
	var total := 0.0
	for p in pool:
		total += p[0]
	var roll := randf() * total
	for p in pool:
		roll -= p[0]
		if roll <= 0.0:
			return p[1]
	return pool.back()[1]


static func _start_move(z: ZombieBase, mind: BossMind, move: Dictionary, delta: float) -> void:
	mind.state = "windup"
	mind.active = move
	mind.windup = float(move.get("windup", 0.5))
	_stop(z, delta)
	z.face_toward_target()
	z._play_anim(String(move.get("anim", "attack")), true)
	AudioManager.play_sfx_2d(move.get("sfx", &"zombie_attack"), z.global_position, 1100.0, -2.0)
	if not mind.notified.has(move.get("id")):
		mind.notified[move.get("id")] = true
		EventBus.notify.emit("⚠ %s：%s" % [String(mind.cfg.get("name", "BOSS")),
			String(move.get("hint", ""))])
	_spawn_telegraphs(z, mind, move)


## 前摇期间生成地面预警图形（时长 = 前摇 = 玩家的躲避窗口）。
static func _spawn_telegraphs(z: ZombieBase, mind: BossMind, move: Dictionary) -> void:
	if z.level == null:
		return
	_clear_telegraphs(mind)
	var type := String(move.get("type", ""))
	var telegraph: Node2D = null
	match type:
		"slam":
			var ring := TelegraphRing.new()
			ring.radius = _move_radius(move, mind)
			ring.duration = mind.windup
			ring.position = z.global_position
			telegraph = ring
		"pull", "wave", "charge":
			var line := TelegraphLine.new()
			line.length = float(move.get("length", float(move.get("max_r", 320.0)))) * (1.4 if type == "charge" else 1.0)
			line.width = 80.0
			line.duration = mind.windup
			line.position = z.global_position
			line.rotation = 0.0 if z.facing > 0 else PI
			telegraph = line
		"lob", "volley_lob", "acid", "spores":
			var aim := _aim_point(z, move) if type != "spores" else z.global_position
			var ring := TelegraphRing.new()
			ring.radius = float(move.get("max_r", 430.0)) if type == "spores" else _move_radius(move, mind)
			ring.duration = mind.windup
			ring.position = aim
			telegraph = ring
	if telegraph != null:
		z.level.fx_layer.add_child(telegraph)
		mind.telegraph = telegraph


static func _clear_telegraphs(mind: BossMind) -> void:
	if mind.telegraph != null and is_instance_valid(mind.telegraph):
		mind.telegraph.queue_free()
	mind.telegraph = null


static func _move_radius(move: Dictionary, mind: BossMind) -> float:
	var r: float = float(move.get("radius", 120.0))
	for i in mind.phase:
		r += float(_phase(mind, i).get("radius_bonus", 0.0))
	return r


static func _aim_point(z: ZombieBase, move: Dictionary) -> Vector2:
	var aim := z.global_position
	if z.target != null and is_instance_valid(z.target):
		aim = z.target.global_position + Vector2(0, -6)
		if z.target is CharacterBody2D:
			aim += (z.target as CharacterBody2D).velocity * float(move.get("predict", 0.3))
	var bridge: float = float(move.get("bridge", 0.0))
	if bridge > 0.0:
		aim = z.global_position.lerp(aim, bridge)
	return aim


## 前摇到点 → 结算（每种 type 一个安全位几何）+ 收招硬直（安全反击窗口）。
static func _finish_move(z: ZombieBase, mind: BossMind, move: Dictionary) -> void:
	_clear_telegraphs(mind)
	var type := String(move.get("type", ""))
	var cd_mult := 1.0
	for i in mind.phase:
		cd_mult *= float(_phase(mind, i).get("cd_mult", 1.0))
	move["cd"] = float(move.get("cooldown", 5.0)) * cd_mult
	match type:
		"slam":
			var r := _move_radius(move, mind)
			var hits := melee_area(z.level, z.global_position, r, int(move.get("dmg", 20)),
				move.get("knock", Vector2(220, -120)), bool(move.get("front", false)), z)
			if hits > 0:
				EventBus.hitstop.emit(0.05)
			if z.level:
				Fx.explosion(z.level.fx_layer, z.global_position + Vector2(float(z.facing) * 24.0, -6), 0.9)
			mind.recover = 0.75
			mind.state = "recover"
		"pull":
			_cast_pull(z, move)
			mind.recover = 0.7
			mind.state = "recover"
		"wave":
			_cast_wave(z, move)
			mind.recover = 0.6
			mind.state = "recover"
		"spores":
			_cast_spores(z, move)
			mind.recover = 0.6
			mind.state = "recover"
		"summon":
			_cast_summon(z, mind, move)
			mind.recover = 0.6
			mind.state = "recover"
		"lob":
			_begin_volley(z, mind, move, 1)
		"volley_lob":
			_begin_volley(z, mind, move, int(move.get("count", 3)))
		"volley_shot":
			_begin_volley(z, mind, move, int(move.get("count", 3)))
		"charge":
			mind.active = move
			mind.state = "charge"
			mind.charge_hit = false
			z.velocity.x = float(z.facing) * float(move.get("speed", 520.0))
			AudioManager.play_sfx_2d(&"charger_charge", z.global_position, 1000.0)
		"leap":
			mind.active = move
			mind.state = "leap"
			if z.target != null and is_instance_valid(z.target):
				var to := z.target.global_position - z.global_position
				z.velocity.x = clampf(to.x * 1.6, -460.0, 460.0)
			z.velocity.y = -520.0
			AudioManager.play_sfx_2d(&"hunter_pounce", z.global_position, 900.0)
		"multihit":
			_begin_volley(z, mind, move, int(move.get("hits", 3)))
		"acid":
			var aim := _aim_point(z, move)
			if z.level:
				z.level.call("spawn_acid_zone", aim, float(move.get("radius", 80.0)),
					float(move.get("duration", 4.0)), 18.0)
			mind.recover = 0.6
			mind.state = "recover"
		"drain":
			_cast_drain(z, move)
			mind.recover = 0.4
			mind.state = "recover"


static func _begin_volley(z: ZombieBase, mind: BossMind, move: Dictionary, count: int) -> void:
	mind.volley_left = count
	mind.volley_timer = 0.0
	mind.volley_params = move.duplicate(true)


static func _cast_pull(z: ZombieBase, move: Dictionary) -> void:
	if z.level == null:
		return
	var hit_any := false
	for body in z.level.get_damageable_near(z.global_position, float(move.get("max_r", 320.0))):
		var to_me: Vector2 = z.global_position - body.global_position
		if absf(to_me.y) > Y_BAND * 2.2:
			continue
		# 拉拽 = 朝 boss 的大冲量 + 直线弹道伤害
		if body.has_method("take_damage"):
			body.take_damage(int(move.get("dmg", 22)), to_me.normalized(), &"zombie", &"melee")
			hit_any = true
		if body.has_method("apply_knockback"):
			body.apply_knockback(to_me.normalized() * 620.0 + Vector2(0, -80))
	if hit_any:
		EventBus.hitstop.emit(0.05)
	AudioManager.play_sfx_2d(&"zombie_attack_2", z.global_position, 900.0)


static func _cast_wave(z: ZombieBase, move: Dictionary) -> void:
	if z.target == null or not is_instance_valid(z.target):
		return
	var to := z.target.global_position - z.global_position
	# 安全位：跳出弹道（y 差 > Y_BAND）或超出波长
	if absf(to.x) > float(move.get("length", 400.0)) or absf(to.y) > Y_BAND:
		return
	var sx := signf(to.x)
	if z.target.has_method("take_damage"):
		z.target.take_damage(int(move.get("dmg", 14)), Vector2(sx, 0), &"zombie", &"melee")
	if z.target.has_method("apply_knockback"):
		z.target.apply_knockback(Vector2(sx * 180.0, -60.0))
	_set_target_slow(z.target, float(move.get("slow", 2.0)))
	if z.level:
		var line := TelegraphLine.new()
		line.length = float(move.get("length", 400.0))
		line.width = 84.0
		line.duration = 0.22
		line.position = z.global_position
		line.rotation = 0.0 if sx > 0.0 else PI
		z.level.fx_layer.add_child(line)


static func _cast_spores(z: ZombieBase, move: Dictionary) -> void:
	if z.level == null:
		return
	var radius := float(move.get("max_r", 430.0))
	z.level.alert_commons_near(z.global_position, radius * 0.7)
	for body in z.level.get_damageable_near(z.global_position, radius):
		if absf(body.global_position.y - z.global_position.y) > Y_BAND * 3.0:
			continue
		_set_target_slow(body, float(move.get("slow", 2.5)))
		if int(move.get("dmg", 0)) > 0 and body.has_method("take_damage"):
			body.take_damage(int(move.get("dmg", 0)), Vector2.ZERO, &"zombie", &"melee")


static func _cast_summon(z: ZombieBase, mind: BossMind, move: Dictionary) -> void:
	if z.level == null:
		return
	var count := int(move.get("count", 1)) + _count_bonus(mind)
	var kind: StringName = move.get("summon_kind", &"common")
	for i in count:
		var side := -1.0 if randf() < 0.5 else 1.0
		var x := z.global_position.x + side * randf_range(110.0, 240.0)
		var gy: float = z.level.call("get_ground_y", x)
		if gy < 0.0:
			gy = z.global_position.y
		if kind == &"common":
			z.level.call("spawn_horde_at", Vector2(x, gy - 2.0), 1, true)
		else:
			z.level.call("_spawn_zombie", kind, Vector2(x, gy - 2.0), true)


static func _cast_drain(z: ZombieBase, move: Dictionary) -> void:
	if z.level == null or not z.level.has_method("consume_corpse_near"):
		return
	var consumed := 0
	for i in 3:
		if z.level.call("consume_corpse_near", z.global_position, float(move.get("radius", 280.0))):
			consumed += 1
	if consumed > 0:
		z.health = mini(z.max_health, z.health + int(round(float(z.max_health) * 0.02)) * consumed)
		Fx.blood(z.level.fx_layer, z.global_position + Vector2(0, -30), Vector2.DOWN, 0.6)
		EventBus.notify.emit("%s 吸收了尸体——射击尸体阻止回血！" % mind_name(z))
		on_damaged(z)


## 扑击落地结算（l08 leap_slam）。
static func _leap_impact(z: ZombieBase, mind: BossMind, move: Dictionary) -> void:
	var r := _move_radius(move, mind)
	var hits := melee_area(z.level, z.global_position, r, int(move.get("dmg", 34)),
		move.get("knock", Vector2(280, -200)))
	if hits > 0:
		EventBus.hitstop.emit(0.05)
	if z.level:
		Fx.explosion(z.level.fx_layer, z.global_position, 1.0)
		EventBus.shake(4.0)
		AudioManager.play_sfx_2d(&"zombie_land", z.global_position, 900.0)


static func _tick_charge(z: ZombieBase, mind: BossMind, delta: float) -> void:
	var move := mind.active
	var speed: float = float(move.get("speed", 520.0))
	z.velocity.x = float(z.facing) * speed
	z._play_anim(String(move.get("anim", "charge")))
	var left: float = maxf(0.0, float(move.get("_left", float(move.get("duration", 0.9)))) - delta)
	move["_left"] = left
	if not mind.charge_hit and z.level != null:
		var ahead := z.global_position + Vector2(float(z.facing) * 34.0, 0)
		for body in z.level.get_damageable_near(ahead, 36.0):
			if absf(body.global_position.y - z.global_position.y) > Y_BAND:
				continue
			var knock: Vector2 = move.get("knock", Vector2(300, -260))
			if body.has_method("take_damage"):
				body.take_damage(int(move.get("dmg", 30)), Vector2(float(z.facing), 0), &"zombie", &"melee")
			if body.has_method("apply_knockback"):
				body.apply_knockback(Vector2(float(z.facing) * knock.x, knock.y))
			mind.charge_hit = true
			EventBus.hitstop.emit(0.06)
			break
	if left <= 0.0 or z.is_on_wall():
		z.velocity.x = 0.0
		if z.is_on_wall():
			# l05：冲撞撞墙自晕 → 弱点暴露
			var armor := _armor(mind)
			if armor.has("hits_to_expose"):
				mind.exposed = float(armor.get("expose_time", 2.5))
				EventBus.notify.emit("%s 抛锚——攻击弱点！" % mind.cfg.get("name", ""))
				EventBus.shake(3.0)
				AudioManager.play_sfx_2d(&"charger_impact", z.global_position, 900.0)
		move.erase("_left")
		mind.active = {}
		mind.state = "recover"
		mind.recover = 0.7


static func _volley_tick(z: ZombieBase, mind: BossMind, delta: float) -> void:
	if mind.volley_left > 0:
		mind.volley_timer -= delta
		if mind.volley_timer <= 0.0:
			mind.volley_timer = float(mind.volley_params.get("interval", VOLLEY_GAP))
			mind.volley_left -= 1
			if String(mind.volley_params.get("type", "")) == "volley_shot":
				_fire_shot(z, mind.volley_params)
			elif String(mind.volley_params.get("type", "")) == "multihit":
				var move := mind.volley_params
				var hits := melee_area(z.level, z.global_position, float(move.get("radius", 110.0)),
					int(move.get("dmg", 12)), Vector2.ZERO)
				if hits > 0:
					EventBus.shake(2.0)
					z._play_anim(String(move.get("anim", "atk_scratch")), true)
			else:
				_fire_lob(z, mind.volley_params)


static func _fire_lob(z: ZombieBase, move: Dictionary) -> void:
	if z.level == null:
		return
	var lob := BossLob.new()
	lob.level = z.level
	lob.to = _aim_point(z, move)
	lob.radius = float(move.get("radius", 100.0))
	lob.dmg = int(move.get("dmg", 30))
	lob.acid_mode = bool(move.get("acid_mode", false))
	lob.acid_duration = float(move.get("duration", 4.0))
	z.level.fx_layer.add_child(lob)
	lob.launch(z.global_position + Vector2(float(z.facing) * 20.0, -40.0), lob.to, LOB_FLIGHT)


static func _fire_shot(z: ZombieBase, move: Dictionary) -> void:
	if z.target == null or not is_instance_valid(z.target) or z.level == null:
		return
	AudioManager.play_sfx_2d(&"m9", z.global_position, 900.0, -4.0)
	if not z.has_line_of_sight_to_target():
		return
	var from := z.global_position + Vector2(float(z.facing) * 14.0, -26.0)
	var to := z.target.global_position + Vector2(0, -14)
	Fx.tracer(z.level.fx_layer, from, to, Color(0.9, 0.9, 0.6, 0.8))
	if z.target.has_method("take_damage"):
		z.target.take_damage(int(move.get("dmg", 8)), Vector2(float(z.facing), 0), &"zombie", &"bullet")


# ------------------------------------------------------------- 工具函数 ----
static func mind_name(z: ZombieBase) -> String:
	var mind: BossMind = z.get("_mind")
	return String(mind.cfg.get("name", "BOSS")) if mind != null else "BOSS"


static func _count_bonus(mind: BossMind) -> int:
	var bonus := 0
	for i in mind.phase:
		bonus += int(_phase(mind, i).get("count_bonus", 0))
	return bonus


static func _set_target_slow(body: Node, seconds: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	if "slow_timer" in body:
		body.set("slow_timer", maxf(float(body.get("slow_timer")), seconds))


## 范围伤害结算：玩家 + 盟友。y 差 > Y_BAND（跳起）免伤；front_node 非 null 时
## 只结算其正面（盾击）。
static func melee_area(level: Node, pos: Vector2, radius: float, dmg: int,
		knock: Vector2 = Vector2(220, -120), front: bool = false,
		front_node: Node2D = null) -> int:
	if level == null:
		return 0
	var hits := 0
	for body in level.get_damageable_near(pos, radius):
		if absf(body.global_position.y - pos.y) > Y_BAND:
			continue
		var dir: Vector2 = body.global_position - pos
		dir.y = 0.0
		if dir.length() < 0.01:
			dir = Vector2(float(front_node.facing) if front_node != null else 1.0, 0)
		dir = dir.normalized()
		if front and front_node != null and signf(dir.x) != signf(float(front_node.facing)):
			continue
		if body.has_method("take_damage"):
			body.take_damage(dmg, dir, &"zombie", &"melee")
			hits += 1
		if knock != Vector2.ZERO and body.has_method("apply_knockback"):
			body.apply_knockback(Vector2(dir.x * knock.x, knock.y))
	return hits


static func _stop(z: ZombieBase, delta: float) -> void:
	z.velocity.x = move_toward(z.velocity.x, 0.0, 1100.0 * delta)


## 前摇闪红 / 弱点期闪黄（zombie_base 每帧把 modulate 复位为 _base_tint，
## 本函数在其后执行，可覆盖出闪烁效果）。
static func _visual_state(z: ZombieBase, mind: BossMind) -> void:
	if z.sprite == null:
		return
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
	if mind.state == "windup":
		z.sprite.modulate = z._base_tint.lerp(Color(1.6, 0.35, 0.3), blink * 0.8)
	elif mind.exposed > 0.0:
		z.sprite.modulate = z._base_tint.lerp(Color(1.8, 1.6, 0.4), blink * 0.85)
