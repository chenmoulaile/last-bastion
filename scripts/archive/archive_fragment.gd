class_name ArchiveFragment
extends Resource
## One collectible piece of the RUST FREQUENCY archive.
##
## Security levels:
##   1 RUMOR       传闻   —— 街头流言、广播碎片
##   2 EVIDENCE    证据   —— 舱单、采样记录、照片
##   3 COMPLICITY  共谋   —— 内部邮件、授权签字
##   4 THE_DEEP    深渊   —— 信号核心录音、适配体名单

const SECURITY_NAMES := {
	1: "RUMOR",
	2: "EVIDENCE",
	3: "COMPLICITY",
	4: "THE_DEEP",
}

const SECURITY_LABELS_ZH := {
	1: "传闻",
	2: "证据",
	3: "共谋",
	4: "深渊",
}

const SECURITY_COLORS := {
	1: Color(0.72, 0.72, 0.68),
	2: Color(0.55, 0.72, 0.86),
	3: Color(0.88, 0.66, 0.32),
	4: Color(0.86, 0.36, 0.34),
}

@export var fragment_id: String = ""
@export var title: String = ""
@export var content_type: String = "text" # text / audio / image / video
@export var content_text: String = ""
@export var content_audio: AudioStream = null
@export var content_image: Texture2D = null
@export var security_level: int = 1 # 1=Rumor 2=Evidence 3=Complicity 4=TheDeep
@export var required_character: String = "" # ""=任何人；"victor"=仅维克多
@export var required_passive: String = "" # 可选：需要特定被动
@export var chapter: int = 1
@export var level: int = 1
@export var archive_type: String = "rumor" # rumor/evidence/complicity/the_deep
@export var source: String = "" # 归档机构 / 作者
@export var timestamp: String = "2019-09-11"
@export var translation: String = "" # 原文的中文翻译（英文档案用）


func security_name() -> String:
	return SECURITY_NAMES.get(security_level, "RUMOR")


func security_label_zh() -> String:
	return SECURITY_LABELS_ZH.get(security_level, "传闻")


func security_color() -> Color:
	return SECURITY_COLORS.get(security_level, Color.WHITE)


## True when this fragment is gated behind a specific survivor's expertise.
func is_specialist_gated() -> bool:
	return required_character != "" or required_passive != ""


func required_specialist_name() -> String:
	if required_character == "":
		return ""
	var character: CharacterData = GameManager.get_character(StringName(required_character))
	return character.display_name if character != null else required_character


## Human-readable redaction used by the archive menu for locked entries.
func redacted_title() -> String:
	var out := ""
	for i in title.length():
		out += "█"
	return out if out != "" else "█████"
