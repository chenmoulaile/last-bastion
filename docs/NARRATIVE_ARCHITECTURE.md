# 叙事架构 · RIFT CITY 2019

> 本文件描述 v2.0「锈蚀频率档案」叙事层的系统结构、数据格式与扩展方式。
> 玩法核心（跑射、8 种特感、AI Director、11 关战役）保持不变，叙事层是叠加
> 在 `LevelRunner` 之上的四个子系统：角色、档案、派系、对话。

---

## 1. 世界观与术语

| 术语 | 含义 |
|---|---|
| 锈蚀热 Rust Fever | 2019 年 9 月在裂城（Rift City）爆发的感染事件 |
| 1.7 GHz 窄带异常 | 覆盖全城的窄带载波；感染者对其有相位反应 |
| 适配体 Adapter | 对 1.7 GHz 有稳定锁相能力的儿童实验体，编号 A-01…A-09 |
| 适配体 07 | 林小满，林远之女；状态「活跃」，位于核心室下层 |
| 地平线安保 Horizon | 私营军事承包商，封锁城市并运输「样本」 |
| 信号局 Signal Bureau | 联邦异常信号调查局，批准并监管适配体计划 |
| 锈帮 Rust Gang | 码头走私与拾荒者，与地平线有交易 |
| 残警 Remnants | 第十三分局残部，断补给后仍维持巡逻 |

四章十一关：

| 章 | 关卡 | 场景 | 叙事节点 |
|---|---|---|---|
| 1 | 1-1 / 1-2 / 1-3 | 港口外围 / 锈帮码头 / 废弃检疫站 | 四人相遇、马洛交易、装甲车 BOSS、交易记录 |
| 2 | 2-1 / 2-2 / 2-3 | 旧城区 / 地铁隧道 / 残警警局 | 站队抉择、巢穴母体、芯片抉择（决定 3-1 路线） |
| 3 | 3-1A / 3-1B / 3-2 / 3-3 | 排水系统 或 净化区正门 / 净化区外围 / 地平线大厦底层 | 双路线、三方混战、「铁面」、林小满的名字 |
| 4 | 4-1 / 4-2 | 地下样本库 / 信号核心室 | 实验体抉择、最终 BOSS、二元结局 |

> 3-1A 与 3-1B 共用 `l07` 关卡槽：`GameManager.route_variant()` 读取
> `route_sewer` 存档标记，`LevelRunner._apply_route_variant()` 在构建地形前
> 深拷贝并改写标题/主题/黑暗标记，因此 11 个场景文件对应 12 个叙事关卡。

---

## 2. 系统总览

```text
                 ┌──────────────────────────┐
                 │        EventBus          │  所有跨系统通信
                 └────┬─────────┬───────────┘
      ┌───────────────┘         └──────────────┐
┌─────▼──────┐   ┌──────────────┐   ┌──────────▼───────┐
│ ArchiveManager │ FactionManager │ DialogueManager │
│ 碎片/密级/结局 │ 四派系知情/敌意 │ 台词/字幕/沉默规则 │
└─────┬──────┘   └──────┬───────┘   └──────────┬───────┘
      │                 │                      │
      │        ┌────────▼────────┐             │
      └────────►    AIDirector   ◄─────────────┘
               │ 巡逻/混战/刷新权重 │
               └────────┬────────┘
                        │ 请求
               ┌────────▼────────┐
               │   LevelRunner   │ 唯一拥有世界节点的对象
               │  地形/敌人/触发器 │
               └────────┬────────┘
      ┌─────────────────┼──────────────────┐
┌─────▼──────┐   ┌──────▼───────┐   ┌──────▼──────────┐
│ Player + 被动 │   │ FactionUnit  │   │ NarrativeTrigger │
│ 潜行/处决/格挡 │   │ 8 种派系单位  │   │ 对话/档案/抉择    │
└────────────┘   └──────────────┘   └─────────────────┘
```

Autoload 顺序（`project.godot`）：

```text
EventBus → GameManager → DirectorSystem → AudioManager → SaveSystem
→ ConfigManager → ArchiveManager → FactionManager → DialogueManager
→ EnemyPerception
```

后四个只依赖前六个；`AIDirector` 不是 Autoload，由 `LevelRunner` 每关实例化，
因此不存在跨关状态泄漏。

---

## 3. 角色层

### 3.1 数据

`CharacterData`（`scripts/data/character_data.gd`）同时承载旧版 6 名原型与新版
4 名幸存者，用 `roster` 字段区分：

```gdscript
roster = "legacy"   # assault/heavy/medic/scout/ninja/officer + 4 名士兵
roster = "archive"  # lin_yuan / marcus / lucia / victor
```

叙事相关字段：

| 字段 | 说明 |
|---|---|
| `character_id` | 叙事数据使用的字符串 id（`cid()` 兜底到 `id`） |
| `codename` | 代号：山猫 / 老兵 / 街头 / 标本 |
| `stealth_speed_multiplier` | 潜行移速倍率；林远 1.0，其余 0.6 |
| `melee_damage` | 处决伤害基数（×6 为实际处决伤害） |
| `passive_ability_id` | 被动脚本键，见 `PassiveRegistry.SCRIPTS` |
| `passive_cooldown` | 马库斯格挡等被动的冷却 |
| `dialogue_color` | 对话气泡/字幕颜色 |
| `visual_base` | 复用哪套像素动画（不重画素材） |
| `palette_tint` | 调色板偏移，`PlayerController` 用 modulate 应用 |
| `unlock_archive_types` | 该角色可解读的档案类型（叙事标签） |
| `monologue` | 角色选择界面的一段独白 |

资源文件：`resources/data/characters/survivor_*.tres`。
路径别名：`scripts/character/character_data.gd` 仅 `extends` 主脚本，供规格
要求的路径引用，避免重复 `class_name`。

### 3.2 被动

| 角色 | 被动 | 实现要点 |
|---|---|---|
| 林远 | 山猫步 | 潜行不减速；背后处决时 `EnemyPerception.ignore_source(victim)` + `suppress_noise`；处决后 `visibility = 0` 持续 3s |
| 马库斯 | 老兵直觉 | `take_damage()` 内做几何判定：`facing.dot(source_dir) > 0.5` 视为背后，伤害归零并进入 30s 冷却 |
| 露西亚 | 街头直觉 | `CoverDetector`（Area2D，mask=64）监听 `area_entered`，对 320px 内感染者调用 `reveal_through_walls(3.0)` |
| 维克多 | 生物学家 | `damage_multipliers["special_infected"] = 1.2`；监听 `EventBus.enemy_died`，50% 掉落 `SamplePickup` |

被动生命周期：`PassiveAbility._ready → _on_activate()` 连接信号，
`_exit_tree → _on_deactivate()` 断开。玩家在 `PlayerController._install_passive()`
中通过 `PassiveRegistry.create()` 挂载，因此新增角色只需新增 `.tres` + 脚本。

### 3.3 潜行与处决

```text
is_stealthed = 蹲下 && 非滑铲 && 手电关闭 && 距上次开火 >1.2s && 未倒地
visibility   = 0（处决窗口） / 0.45（潜行） / 1.0（常态）
```

感染者通过 `ZombieBase._target_visibility()` 读取该值：
- `_can_see_target()` 直接返回 false（visibility ≤ 0.02）
- 未警觉时视野半径按 visibility 缩放
- `_acquire_target()` 把玩家作为目标的权重按 `1/visibility` 降低

处决：潜行状态下按近战键，若目标在正面 54px 内且玩家位于其背后
（`sign(dx) == zombie.facing`），触发 `_execute()`：伤害 ×6、`silent_execution`
信号、`EnemyPerception.suppress_noise()` 静音 3s，避免惊动整层。

---

## 4. 档案层

### 4.1 资源

`ArchiveFragment`（`scripts/archive/archive_fragment.gd`）：

```gdscript
fragment_id, title, content_type, content_text, content_audio, content_image
security_level   # 1 RUMOR / 2 EVIDENCE / 3 COMPLICITY / 4 THE_DEEP
required_character, required_passive, chapter, level
archive_type, source, timestamp, translation
```

批量内容存放在 `resources/data/archives/archive_fragments.json`（23 条），
特殊条目可用 `.tres` 提供音频/图片（如 `the_deep_pulse_pattern.tres`）。
`ArchiveManager` 先读 `.tres` 再读 JSON，同名 id 后者覆盖前者。

### 4.2 规则

- 解锁条件：`required_character` 为空或等于当前角色；合作模式下任一玩家满足即可。
- 失败提示：「需要[角色名]的专业知识」。
- 进度持久化：`SaveSystem.data["archives"]`（字符串数组）。
- 章节阈值：第 1 章 ≥2 个 RUMOR，第 2 章 ≥2 个 EVIDENCE，第 3 章 ≥2 个 COMPLICITY。
- 未达标时 `extra_spawn_slots()` 返回 2，`LevelRunner._build_archives()` 增加刷新点。
- 达标时 `EventBus.archive_quota_changed` 可用于解锁安全屋隐藏对话（`truth_1..3`）。
- 第 4 章解码前置：`can_decode_signal()` 需要至少 1 个 THE_DEEP 碎片。

### 4.3 UI

| 场景 | 作用 |
|---|---|
| `scenes/ui/archive/ArchiveViewer.tscn` | 拾取瞬间的全屏阅读器，暂停游戏，播放音频/图片 |
| `scenes/ui/archive/ArchiveMenu.tscn` | 按密级筛选、滚动列表、未解锁显示 █████ |
| 暂停菜单「档案库」按钮 | 在暂停层叠加 `ArchiveMenu`（`PROCESS_MODE_ALWAYS`） |

---

## 5. 派系层

### 5.1 数据

`FactionData`（`resources/data/factions/*.tres`）：

```gdscript
faction_id, display_name, short_name, knowledge_level
base_hostility_to_player, hostility_to_zombies
hostility_to_other_factions   # 非对称关系矩阵
patrol_density, special_units, accent
```

关系矩阵（行 → 列）：

|  | 地平线 | 信号局 | 锈帮 | 残警 |
|---|---|---|---|---|
| 地平线 | — | 0.2 | 0.6 | 0.9 |
| 信号局 | 0.2 | — | 0.4 | 0.3 |
| 锈帮 | 0.3 | 0.5 | — | 0.8 |
| 残警 | 0.9 | 0.3 | 0.8 | — |

### 5.2 敌意公式

```text
effective = clamp(base
  + highest_security_level * 0.15
  + kills * 0.05
  - quests * 0.20
  + story_bonus, 0, 1)
```

`> 0.7` 即进入主动敌对：`FactionUnit` 会把玩家纳入目标列表。
`set_hostility()` 通过反解 `story_bonus` 精确落在指定值，供叙事触发器使用。

### 5.3 刷新联动

| 条件 | 效果 |
|---|---|
| 密级 ≥ 2 | 地平线巡逻密度 ×1.2 |
| 密级 ≥ 3 | 信号局 ×1.3；`signal_agent` 权重 ×1.3；`evidence_destroyer` 出现 |
| 密级 = 4 | 地平线/信号局 ×1.4；`horizon_enforcer`、`evidence_destroyer` 权重 ×2 |

### 5.4 八种派系单位

| 单位 | 阵营 | 行为 |
|---|---|---|
| `horizon_enforcer` | 地平线 | 重甲 + 盾牌，正面子弹减伤 65%，近战推开 |
| `evidence_destroyer` | 地平线 | 冲向最近的档案刷新点并烧毁 |
| `signal_agent` | 信号局 | 消音武器，优先追踪持档玩家 |
| `signal_jammer` | 信号局 | 每 5s 部署 240px / 6s 干扰区，档案不可交互 |
| `rust_enforcer` | 锈帮 | 高伤害中距离 |
| `rust_trader` | 锈帮 | 中立，受击后才反击 |
| `remnant_patrol` | 残警 | 防暴盾推进 |
| `remnant_sniper` | 残警 | 远程，优先攻击特殊感染者 |

实现：`scripts/faction/faction_unit.gd` 继承 `ZombieBase`，复用受击/硬直/击退/
死亡管线，仅替换 `_ai_tick()` 与射击；视觉复用角色像素条 + `palette_tint`。

### 5.5 混战

`AIDirector` 每 45s 调用 `FactionManager.pick_skirmish_pair()`：
关系分最高且双方 `hostility_to_zombies ≥ 0.5` 时触发，双方各生成 2 个单位，
同时引发 6 只感染者围观。55s 后或一方全灭结束，双方敌意各 +0.02。

---

## 6. 对话与叙事触发

### 6.1 数据

- `resources/data/dialogues/barks.json`：战斗短句，按角色 → bark_id → 数组。
- `resources/data/dialogues/conversations.json`：`{id: {title, lines:[{speaker,text,translation,lang,duration}]}}`。

林远规则：
- 每个 `bark_id` 只有 1 条，总量约为其他角色的 1/3（10 vs 27）。
- 冷却 9s（其他角色 3s）。
- 每次发言让全队沉默 1.5s（`_silence_until`）。
- 中文台词显示中文字幕；回忆段配英文字幕（`translation`）。

### 6.2 触发器

`NarrativeTrigger`（Area2D，mask=2）由 `LevelData.narrative` 数组生成：

```json
{"at": 0.08, "type": "conversation", "conversation": "c1_meet"}
{"at": 0.44, "type": "memory", "conversation": "ly_memory_1", "character": "lin_yuan"}
{"at": 0.20, "type": "choice", "choice": "c2_side"}
{"at": 0.74, "type": "hostility", "faction": "horizon", "value": 0.85}
{"at": 0.78, "type": "archive", "fragment": "evidence_adapter_list"}
{"at": 0.82, "type": "faction_event", "event": "rust_ambush"}
{"at": 0.94, "type": "final_choice"}
```

`type` 支持：`conversation` / `memory` / `archive` / `hostility` / `faction_event`
/ `flag` / `choice` / `final_choice` / `tip`。

### 6.3 抉择

`StoryChoices.CHOICES` 定义三个中局抉择（2-1 站队、2-3 芯片、4-1 实验体）。
每个选项可写存档标记、调整派系敌意、触发世界事件。2-3 的 `route_sewer`
标记决定 3-1 走 A 线（排水系统）还是 B 线（正门）。

---

## 7. 最终抉择与结局

`FinalChoiceUI` 在 4-2 BOSS 死亡后（或 `final_choice` 触发器）弹出：

| 选项 | 前置 | 结果 |
|---|---|---|
| A 摧毁信号核心 | 无 | 白屏 + 爆炸；成就「沉默的代价」；NG+ 广播「信号消失，但 1.7 GHz 背景噪声仍在」 |
| B 解码信号 | ≥1 个 THE_DEEP 碎片 | 90s / 3 波防守（持有深渊时额外 2 波）；成就「回应」；解锁林远尾声「山猫的搜索」 |

结局写入 `SaveSystem.data["final_choice"]`，`ArchiveManager.new_game_plus_broadcast()`
与 `unlocks_lin_yuan_epilogue()` 供后续版本读取。

---

## 8. 表现层

### 8.1 漫画后处理

`shaders/comic_post_process.gdshader` + `scripts/fx/comic_post_process.gd`：

- 挂在 `CanvasLayer(30)`，位于 HUD(40) 之下，保证文字清晰。
- 亮度梯度描边（采样 2px，避免雨滴/抖动把整帧描黑）。
- `floor()` 量化到 8 级（向下取整，避免暗部被抬亮）。
- `NoiseTexture2D` 纸张颗粒，围绕中灰调制，强度 0.08。
- `EventBus.gore_event` → `gore_boost` 0.5s 内衰减，增强描边与红色。
- `EventBus.signal_noise_changed` → 随密级提高纸张强度、降低饱和度。

### 8.2 调色板

四名角色复用 `ninja/heavy/scout/medic` 的像素条，通过
`CharacterData.palette_tint` 在 `PlayerController._apply_palette()` 中
对 `Sprite`/`WeaponSprite` 施加 modulate。

### 8.3 1.7 GHz 噪声

`AudioManager.set_signal_noise(level)` 使用 `AudioStreamGenerator`
实时合成 1700Hz 正弦 + 噪声，音量 -42…-18dB，脉冲频率 0.6…2.8Hz。
`ArchiveManager._refresh_noise()` 在每次解锁后调用，密级越高越明显。

---

## 9. 文件索引

```text
scripts/character/
  character_data.gd            # 路径别名（extends data/character_data.gd）
  passive_base.gd              # PassiveAbility 基类
  passive_registry.gd          # id -> 脚本
  passives/passive_lin_yuan.gd
  passives/passive_marcus.gd
  passives/passive_lucia.gd
  passives/passive_victor.gd

scripts/archive/
  archive_fragment.gd          # ArchiveFragment (Resource)
  archive_manager.gd           # Autoload：注册表/门槛/配额/结局
  archive_pickup.gd            # Area2D 拾取物
  archive_viewer.gd            # 全屏阅读器
  archive_menu.gd              # 档案库

scripts/faction/
  faction_data.gd              # FactionData (Resource)
  faction_manager.gd           # Autoload：矩阵/敌意/权重
  faction_roster.gd            # 8 种单位数据表
  faction_unit.gd              # 继承 ZombieBase 的派系单位

scripts/ai/
  ai_director.gd               # 派系调度层（每关实例化）
  enemy_perception_manager.gd  # Autoload：忽略/显形/静音

scripts/narrative/
  dialogue_manager.gd          # Autoload：bark/对话/字幕
  narrative_trigger.gd         # Area2D 触发器
  story_choices.gd             # 三个中局抉择的数据表
  story_choice_ui.gd           # 抉择 UI
  final_choice_ui.gd           # 最终二元抉择

shaders/comic_post_process.gdshader
scripts/fx/comic_post_process.gd

scenes/ui/survivors/CharacterSelect.tscn   # 规格中的 CharacterSelect（避开大小写冲突）
scenes/ui/archive/ArchiveViewer.tscn
scenes/ui/archive/ArchiveMenu.tscn
scenes/ui/narrative/FinalChoiceUI.tscn
scenes/ui/narrative/StoryChoiceUI.tscn
```

> **命名说明**：Windows 文件系统不区分大小写，`CharacterSelect.tscn` 会与既有
> `character_select.tscn` 冲突，因此放入 `scenes/ui/survivors/` 子目录，文件名
> 保持规格要求。

---

## 10. 扩展指南

**新增幸存者**
1. 在 `resources/data/characters/` 新建 `.tres`，`roster = &"archive"`。
2. 新建 `scripts/character/passives/passive_xxx.gd`（`extends PassiveAbility`）。
3. 在 `PassiveRegistry.SCRIPTS` 注册 id。
4. 在 `barks.json` / `conversations.json` 添加台词。
5. 无需修改 `PlayerController`。

**新增档案**
- 直接往 `archive_fragments.json` 追加对象；`chapter`/`level` 决定刷新关卡。

**新增派系单位**
1. `FactionRoster.UNITS` 增加条目（数值 + 视觉 + 行为开关）。
2. 若需要新行为，在 `FactionUnit` 中加分支，或新建脚本继承 `FactionUnit`。

**新增叙事节点**
- 在关卡 `.tres` 的 `narrative` 数组追加条目即可，无需改代码。

---

## 11. 测试

```bash
GODOT=/path/to/Godot_v4.7.2-stable_win64.exe
$GODOT --headless --path . res://tests/smoke.tscn        # 32 项
$GODOT --headless --path . res://tests/campaign.tscn     # 209 项
$GODOT --headless --path . res://tests/integration.tscn  # 91 项
$GODOT --headless --path . res://tests/narrative.tscn    # 106 项
```

`narrative.tscn` 覆盖：
- 四名角色/被动注册/独白
- 档案专家门槛、配额、额外刷新、深渊前置、遮蔽标题
- 派系敌意公式（档案/击杀/任务）、关系矩阵、巡逻密度、单位权重、混战配对
- 林远 bark 数量与沉默规则、4-1 台词占比
- 四名角色被动的运行时行为（潜行不可见、背刺格挡、特感增伤、掩体探测器）
- 漫画层与 gore 参数、档案拾取点/掩体/派系调度器存在性
- 角色选择、档案库、阅读器、最终抉择、中局抉择 UI
- 11 关章节映射与 3-1A/3-1B 路线切换
