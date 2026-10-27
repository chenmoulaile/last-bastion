# LAST BASTION · 项目约定

## 工具链（全部在 E 盘）
- Godot：`E:/Tools/Godot47/Godot_v4.7.2-stable_win64_console.exe`
- 项目根：`E:/Last Bastion`
- 不使用 C 盘的 Python/Node/工具链；无 PIL/NumPy，素材生成器 `tools/*.py` 不参与构建

## 命令
```bash
GODOT="/e/Tools/Godot47/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path . --import          # 新增 class_name 后必须执行
"$GODOT" --headless --path . res://tests/smoke.tscn
"$GODOT" --headless --path . res://tests/campaign.tscn
"$GODOT" --headless --path . res://tests/integration.tscn
"$GODOT" --headless --path . res://tests/narrative.tscn
"$GODOT" --path . --resolution 1280x720 res://tests/screenshot.tscn   # 视觉回归 → build/screens
```

## 架构约束
- 跨系统通信只走 `EventBus`；Autoload 顺序见 `project.godot`
- 叙事四单例：`ArchiveManager → FactionManager → DialogueManager → EnemyPerception`（均在 ConfigManager 之后）
- `AIDirector` 由 `LevelRunner` 每关实例化，不是 Autoload
- `DirectorSystem` 保留尸潮/特感核心循环，派系层只叠加权重与生成请求
- 所有叙事内容走 JSON/`.tres`：`resources/data/{archives,factions,dialogues,characters,levels}`
- 新角色 = 新 `.tres` + 新 passive 脚本 + `PassiveRegistry` 注册，不改 `player.gd`
- 关卡叙事节点写在 `LevelData.narrative` 数组，由 `LevelRunner._build_narrative()` 生成 Area2D

## 测试基线
smoke 32 / campaign 209 / integration 91 / narrative 104，必须全绿后再提交。
