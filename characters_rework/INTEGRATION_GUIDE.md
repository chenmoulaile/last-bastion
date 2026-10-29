# characters_rework 集成指南

本包与现有 `scripts/`、`scenes/` 系统**并列共存**，不覆盖、不删除任何旧文件。默认运行时仍由旧玩家/士兵/角色选择系统出战，重构系统已可独立实例化并通过冒烟测试，便于逐步切换与随时回滚。

## 1. 安装

把整个 `characters_rework/` 放到项目根目录（与 `scripts/`、`resources/` 同级）即可。无需注册 Autoload，无需修改 `project.godot`。

依赖探测全部是可选的：

- `EventBus`、`GameManager`、`AudioManager` 通过 `/root/<Name>` 探测；不存在时自动降级。
- 武器数据从 `res://resources/data/weapons/` 读取。
- 渲染器不依赖任何外部贴图。

## 2. 信号映射表（EventBusBridge）

`EventBusBridge` 是**单向只读**桥：新系统内部信号 → 旧 `EventBus` 信号。旧总线没有新增信号，签名不变。

| 新系统信号 | 转发到 EventBus | 说明 |
|---|---|---|
| `PlayerControllerV2.character_state_changed("hurt"/"healed"/"downed"/"revived"/"dead"/"respawn"/"fire"/"controlled"/"spawn")` | `health_changed(hp, temp_hp, max_hp)` | 状态变化时合并推送一次 |
| `character_state_changed("spawn")` | `health_changed` + `ammo_changed(mag, reserve)` | 出生时补一次弹药 |
| `PlayerControllerV2.damage_taken(amount, source)` | `damage_flash()` | 只触发屏幕受击反馈 |
| `PlayerControllerV2.passive_triggered(id, payload)` | `notify(text)` | 文本取 `payload.notify_text`，缺省用被动 ID |
| `PlayerControllerV2.died` | `player_died()` | 直接转发 |
| `PlayerControllerV2.downed` | `player_downed()` | 直接转发 |
| `PlayerControllerV2.revived` | `player_rescued()` | 直接转发 |
| `SoldierBase.soldier_state_changed("dead"/"downed"/"revived"/"respawn")` | `teammate_status_changed()` | 队友状态刷新 |
| `SoldierBase.soldier_state_changed("healing")` | `notify("战地医疗兵正在治疗伤兵")` | 战地医疗兵行为提示 |
| `SoldierBase.soldier_order_acknowledged(cmd, state)` | `teammate_status_changed()` + `notify(指令文本)` | follow/advance/hold/focus 映射为中文提示 |
| `SoldierBase.shots_fired(pos)` | — | 仅供渲染/音效钩子使用 |

桥在首个 `PlayerControllerV2` / `SoldierBase` 进入场景树时自动创建：

```gdscript
EventBusBridge.attach_for(actor)   # 控制器 _ready() 内部已调用
EventBusBridge.instance()          # 测试/调试用；未创建时返回 null
```

`_bus` 通过 `Engine.get_main_loop().root.get_node_or_null("EventBus")` 解析，因此在 `add_child.call_deferred` 之前调用 `attach_for` 也不会丢信号。

## 3. 替换步骤（可选，默认不执行）

> 默认保持旧系统出战。以下步骤按需逐项启用，每一步都可以单独回滚。

### 3.1 玩家

旧玩家场景 `res://scenes/actors/player.tscn` 保留不动。切换时在生成点改为：

```gdscript
const REWORK_PLAYER := preload("res://characters_rework/playable/PlayerControllerV2.gd")

var p := REWORK_PLAYER.new()
p.character_data = load("res://characters_rework/data/playable/assault.tres")
p.position = Vector2(220, get_ground_y(220))
p.auto_camera = false          # 沿用现有相机；独立运行时才设 true
actors.add_child(p)
player = p
```

旧玩家节点不要 `queue_free()`，改为：

```gdscript
old_player.process_mode = Node.PROCESS_MODE_DISABLED
old_player.visible = false
```

注意：旧 HUD 在 `scripts/ui/hud.gd` 中以 `CharacterData` 类型读取 `player.get("character")`。`PlayerControllerV2.character` 返回 `ReworkCharacterData`，直接切换会让 HUD 类型转换失败。切换前需要：

1. 给 HUD 增加一个 `ReworkCharacterData` 分支，或
2. 在玩家控制器上提供一个 `CharacterData` 兼容别名（推荐新增 `character_compat` 字段，不改旧 HUD 的公开接口路径）。

因此本包默认不替换玩家，避免破坏现有 HUD 与流程。

### 3.2 指挥士兵

旧士兵场景保留。切换时：

```gdscript
var s := SoldierBase.new()
s.soldier_data = load("res://characters_rework/data/soldiers/rifleman.tres")
s.slot_index = i
s.position = Vector2(px, gy)
actors.add_child(s)
```

`SoldierBase` 自动加入 `allies` 组并调用 `EventBusBridge.attach_for(self)`。旧士兵节点设为 `PROCESS_MODE_DISABLED` + `visible = false`，不要删除。

### 3.3 角色选择

旧 `res://scenes/ui/character_select.tscn` 保留。可并排提供：

```gdscript
const REWORK_SELECT := preload("res://characters_rework/ui/CharacterSelectV2.tscn")
```

`CharacterSelectV2` 发出 `character_selected(id)` / `character_confirmed(id)`，确认时若 `GameManager` 存在会写入 `selected_character`，与旧存档键兼容。

### 3.4 旧节点处理原则

- 不物理删除任何旧场景、脚本、资源。
- 旧节点用 `process_mode = PROCESS_MODE_DISABLED` 或 `visible = false` 停用。
- 需要彻底回滚时，删除本目录并恢复上述单行改动即可。

## 4. 输入映射

控制器读取项目现有动作，缺失的动作会被安全忽略：

`move_left` / `move_right` / `jump` / `crouch` / `fire`（别名 `shoot`）/ `reload` / `melee` / `switch_weapon` / `skill`（别名 `dash`）/ `throw` / `medkit` / `pills` / `interact`。

`cmd_formation`（别名 `formation_cycle`）供指挥模式使用。所有输入通过 `InputMap.has_action()` 探测，不新增项目动作。

## 5. 数值与被动一致性

角色属性、武器 ID、被动 ID 全部在 `.tres` 中，与旧系统同源：

| 可玩角色 | HP | 速度 | 被动 | 主武器 |
|---|---|---|---|---|
| assault | 100 | 220 | `assault_rush` | `ar15` |
| heavy | 150 | 160 | `shield_wall` | `lmg` |
| medic | 100 | 210 | `field_medic` | `smg` |
| scout | 85 | 260 | `tactical_roll` | `smg` |
| operative | 90 | 250 | `shadow_strike` | `katana` |
| officer | 100 | 220 | `inspire` | `ar15` |

数值取自资源文件；如与旧 `resources/data/characters/*.tres` 有差异，以本包 `.tres` 为准，但不会影响旧系统运行。

## 6. 附录：叙事角色映射

| 重构角色 | `narrative_id` | 叙事主角 | 映射理由 | 被动兼容性 |
|---|---|---|---|---|
| `operative` 特勤 | `lin_yuan` | 林远 | 潜行、近战、处决 | `shadow_strike` 瞬步到最近敌人背后处决，与林远的潜行/近战人设一致 |
| `heavy` 重装兵 | `marcus` | 马库斯 | 重甲、前排、掩护 | `shield_wall` 正面减伤，符合马库斯的盾墙/军士定位 |
| `scout` 侦察兵 | `lucia` | 露西亚 | 高速、翻滚、侦察 | `tactical_roll` 位移与无敌帧，符合露西亚的敏捷侦察定位 |
| `medic` 医疗兵 | `victor` | 维克多 | 治疗、支援、生物学家 | `field_medic` 治疗与支援，符合维克多的医疗/生物学家背景 |
| `assault` 突击兵 | `""` | 通用 | 全能 frontline | `assault_rush` 换弹/移速爆发，不绑定剧情 |
| `officer` 军官 | `""` | 通用 | 指挥、激励 | `inspire` 团队增益，可作为后续扩展角色 |

约束：

- `narrative_id` 为新增可选字段，旧存档/旧资源缺省为空，不影响加载。
- 映射只用于档案解锁与叙事触发，不参与伤害、血量、射速计算。
- 突击兵与军官保留为通用角色；后续新增叙事主角时只需在 `.tres` 填 `narrative_id`，并在档案系统注册对应 ID。

## 7. 共存与回滚

当前策略是**共存**而不是强切：

- 旧 `scenes/actors/player.tscn`、旧士兵生成、旧 `character_select.tscn` 均保持原样。
- 新系统通过 `characters_rework/` 自带场景/脚本独立运行，冒烟测试不启动关卡。
- 不修改 `project.godot`、不新增 Autoload、不修改 `EventBus` 信号。

回滚：

```bash
# 删除本目录
rm -rf res://characters_rework/
# 若曾按 §3 修改生成逻辑，恢复对应单行即可
```

## 8. 测试

```bash
Godot --headless --path . --quit-after 600 res://characters_rework/integration/smoke_tests.tscn
```

结果应为 `checks=94 failures=0`、`RESULT: PASS`。

测试不启动关卡、不写入存档；结束后退出码可能因引擎资源泄漏告警为 1，以 `RESULT` 行为准。

## 9. 已知限制

1. 旧 HUD 的 `CharacterData` 强类型读取与 `ReworkCharacterData` 不兼容，默认未切换玩家；需兼容层后才能启用。
2. 投掷物、医疗包、药片在 `PlayerControllerV2` 中仍是 stub，沿用旧系统的物品逻辑需要额外适配。
3. 士兵寻路为水平槽位跟随 + 跳跃脱困，不含导航网格，复杂地形需手工路径或外部导航。
4. `CharacterSelectV2` 的离屏预览依赖真实渲染帧；headless 下回退为色块占位。
5. 重构系统尚未接入关卡叙事触发器、档案解锁与联机同步，需在后续集成阶段完成。


## 10. 主流程切换记录（M11）

### 10.1 替换的节点

| 位置 | 旧节点 | 新节点 | 处理方式 |
|------|--------|--------|----------|
| `res://scripts/levels/level_runner.gd` `_spawn_player()` | `res://scenes/actors/player.tscn` | `res://characters_rework/playable/PlayerControllerV2.gd` | 新节点实例化，旧场景文件保留不删除 |
| 关卡运行时 | 旧 `player` 节点 | 新 `player` + `Player_Legacy_Disabled` (`PROCESS_MODE_DISABLED`) | 旧节点保留为 disabled，不参与逻辑 |

### 10.2 适配器字段映射

`PlayerControllerV2.character` 返回 `CharacterDataCompat extends CharacterData`，映射字段：

| ReworkCharacterData 字段 | CharacterDataCompat 字段 | 说明 |
|-------------------------|------------------------|------|
| `id` | `id` | 角色 ID |
| `display_name` | `display_name` | 显示名称 |
| `max_hp` | `max_hp` / `max_health` | 最大生命 |
| `speed` | `speed` / `move_speed` | 移动速度 |
| `passive_ability_id` | `passive_ability_id` | 被动技能 ID |
| `palette["accent"]` | `accent` | 职业强调色 |
| `visual_profile` | `visual_base` | 绘制档案 |
| `id` | `portrait` | 肖像键（回退为 id） |

### 10.3 回滚步骤

1. 将 `res://scripts/levels/level_runner.gd` 中 `PLAYER_SCENE` 改回 `preload("res://scenes/actors/player.tscn")`。
2. 删除 `_spawn_player()` 中的 `Player_Legacy_Disabled` 生成逻辑。
3. 删除 `res://scripts/data/character_data_compat.gd`。
4. 删除 `res://scripts/items/ItemComponent.gd`。
5. 恢复 `gamefeel/integration/GameFeelBridge.gd` 中的 `_poll_enabled` 为 `true`（或保留 `false`，仅影响反馈链路）。
6. 不删除任何旧文件，仅恢复单行改动即可。

### 10.4 已知限制

1. `CharacterDataCompat` 是运行时生成的包装器，不从 `.tres` 加载；如需编辑器内编辑角色属性，仍使用旧 `resources/data/characters/*.tres`。
2. `InputBuffer` 换弹取消依赖 `InputBuffer` Autoload 已注册（project.godot 已配置）。
3. HealthComponent 信号驱动模式下，`GameFeelBridge._poll_enabled` 默认 `false`；如需回退到轮询，设为 `true`。
4. `ItemComponent` 仅处理投掷/医疗包/药片，不处理武器切换或技能。
