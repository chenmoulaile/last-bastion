class_name StoryChoices
extends RefCounted
## Data table for mid-campaign choices. Each option can set story flags, shift
## faction hostility and spawn a world event.

const CHOICES := {
	"c2_side": {
		"title": "旧城区 · 帮谁？",
		"prompt": "锈帮和残警在街区交火。你的选择会改变这座城对你的态度。",
		"options": [
			{
				"id": "rust",
				"label": "帮锈帮",
				"desc": "马洛欠你一个人情。残警会记住你。",
				"flags": ["side_rust"],
				"hostility": {"rust": -0.15, "remnants": 0.20},
				"spawn": "rust_ambush",
			},
			{
				"id": "remnants",
				"label": "帮残警",
				"desc": "雷耶斯会给你火力支援。锈帮会封锁码头。",
				"flags": ["side_remnants"],
				"hostility": {"remnants": -0.20, "rust": 0.25},
				"spawn": "remnant_support",
			},
		],
	},
	"c2_chip": {
		"title": "残警警局 · 芯片",
		"prompt": "芯片里有传输日志，也有名单。雷耶斯想烧掉它。",
		"options": [
			{
				"id": "keep",
				"label": "保留芯片",
				"desc": "解锁 3-1A 排水系统绕后路线。信号局会盯上你。",
				"flags": ["chip_kept", "route_sewer"],
				"hostility": {"signal_bureau": 0.20},
				"spawn": "",
			},
			{
				"id": "give",
				"label": "交给信号局",
				"desc": "换取净化区通行许可，走 3-1B 正门。",
				"flags": ["chip_given"],
				"hostility": {"signal_bureau": -0.25, "remnants": 0.15},
				"spawn": "",
			},
		],
	},
	"c4_samples": {
		"title": "地下样本库 · 214 个生命体征",
		"prompt": "终端上有两个按钮：RELEASE / PURGE。",
		"options": [
			{
				"id": "release",
				"label": "释放实验体",
				"desc": "它们会涌向地平线。也会涌向你。",
				"flags": ["specimens_released"],
				"hostility": {"horizon": 0.15},
				"spawn": "zombie_surge",
			},
			{
				"id": "purge",
				"label": "净化样本库",
				"desc": "维克多会把这一切写进报告。",
				"flags": ["specimens_purged"],
				"hostility": {},
				"spawn": "",
			},
		],
	},
}


static func has(choice_id: String) -> bool:
	return CHOICES.has(choice_id)


static func get_choice(choice_id: String) -> Dictionary:
	return CHOICES.get(choice_id, {})
