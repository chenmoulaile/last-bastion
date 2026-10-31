class_name ArchiveFragment
extends Resource
## 单条档案碎片（「锈蚀频率」剧情层收集品）。

@export var id: StringName = &""
@export var level_id: StringName = &""        # 所在关卡（旧 id 体系 l01-l11）
@export var tier: int = 0                     # 密级 0谣言 1证据 2共谋 3深渊
@export var type: StringName = &"text"        # text / audio / image
@export var title: String = ""
@export var content: String = ""
@export var requires: StringName = &""        # 专家门槛 bio/logistics/security/terrain
@export var stamp: String = "内部资料"          # 盖章文字
