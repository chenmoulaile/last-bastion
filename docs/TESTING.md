# TESTING · 测试与验收手册

本文档记录 LAST BASTION v1.0.0 的自动化测试、性能门禁、截图回归和导出验证方法。所有命令均在仓库根目录执行。

## 环境

| 项 | 值 |
|---|---|
| 引擎 | Godot 4.7.2 stable（标准版，GDScript） |
| 渲染器 | Compatibility（OpenGL 3.3） |
| 测试机 GPU | Intel Arc Graphics |
| 测试分辨率 | 1280×720 窗口（内部 640×360） |
| 测试日期 | 2026-10-26 |

把 Godot 可执行文件路径写入环境变量，后续命令可直接复用：

```bash
GODOT=/path/to/Godot_v4.7.2-stable_win64.exe
```

## 自动化测试

### 1. 冒烟测试

```bash
"$GODOT" --headless --path . res://tests/smoke.tscn
```

覆盖：11 个关卡资源、12 把武器、10+ 角色、15+ 僵尸条目、全部菜单场景实例化、L01 小队模式与 L07 指挥模式启动、玩家移动、敌人生成、指挥小队人数。

最近结果：`[SMOKE] checks=32 failures=0` → **PASS**

### 2. 战役测试

```bash
"$GODOT" --headless --path . res://tests/campaign.tscn
```

覆盖：11 关逐一实例化、关卡数据绑定、玩家/队友/HUD/地形生成、武器与技能、投掷物、8 种特感逐只生成并清除、Tank 生成、检查点、隐藏房间、防守/撤离流程、结算与评级。

最近结果：`[CAMPAIGN] checks=209 failures=0` → **PASS**

### 3. 集成测试

```bash
"$GODOT" --headless --path . res://tests/integration.tscn
```

覆盖：

- 门（踹门、僵尸抓门、破坏）、油桶爆炸、木箱破坏、拾取物；
- 检查点全灭重整；
- 倒地-救助-黑白模式-医疗包全流程；
- 控制状态与 3s 控制免疫；
- 防守战计时与奖励；
- 同屏上限（普感 ≤120、特感 ≤4）；
- 调试面板 / 视线 / 时间缩放 / 生成特感；
- 指挥模式：四兵种编制、爆破手手雷、检查点补兵、玩家阵亡溃败；
- 窗户绳降（本项 4 个检查）；
- 评分公式：连击倍率、S/A/B/C 阈值、关卡基础分；
- 四层音乐与 Director 强度、Tank 层独占、环境音；
- 存档原子写入、成就、角色解锁、设置持久化；
- 撤离触发与结算。

最近结果：`[INTEGRATION] checks=91 failures=0` → **PASS**

### 4. 性能门禁

```bash
"$GODOT" --path . --resolution 1280x720 res://tests/performance.tscn
```

该测试必须使用真实窗口（不能 `--headless`），因为要统计渲染与 draw call。测试会：

1. 关闭垂直同步并把 `Engine.max_fps` 设为 0，避免远程桌面/虚拟显示器把 vsync 锁在 30 Hz；
2. 生成 120 只普感 + 4 只特感，等待 1 秒编译着色器；
3. 采样 5 秒，统计平均/最低 FPS、draw call、对象数、物理碰撞对和内存峰值。

最近结果（Intel Arc，1280×720）：

```text
[PERF] frames=4066 avg_fps=813.2 min_fps=72.4 commons=111 specials=3
[PERF] draw_calls=201 memory=82.0MB peak=82.1MB
[PERF] RESULT: PASS
```

预算对照：

| 指标 | 预算 | 实测 | 结果 |
|---|---|---|---|
| 同屏普感 | ≤120 | 111 | PASS |
| 同屏特感 | ≤4 | 3 | PASS |
| 平均帧率 | ≥60 FPS | 813 FPS（未锁帧） | PASS |
| 最低帧率 | ≥60 FPS | 72.4 FPS | PASS |
| 内存峰值 | <600 MB | 82.1 MB | PASS |

> 正常游玩时项目开启 vsync，帧率由显示器刷新率决定。本测试关闭 vsync 是为了测量真实的帧预算，而不是被 30/60 Hz 刷新率掩盖。

### 5. 截图回归

```bash
"$GODOT" --path . --resolution 1280x720 res://tests/screenshot.tscn
```

输出到 `build/screens/`，共 15 张：

- 主菜单、关卡选择、角色选择、设置、成就、图鉴、简报、制作名单；
- L01 开场 / 交火 / HUD；
- L07 开场 / 交火 / HUD / 调试面板；
- 结算页。

`build/` 已被 `.gitignore` 排除；文档配图精选后放在 `docs/screenshots/`。

## 导出验证

```bash
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/LastBastion.exe
"$GODOT" --headless --path . --export-release "Linux" build/linux/LastBastion.x86_64
"$GODOT" --headless --path . --export-release "macOS" build/macos/LastBastion.zip
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
```

Windows/Linux 预设使用 `binary_format/embed_pck=true`，发行包为单文件可执行程序。macOS 导出使用 Universal（x86_64 + arm64），要求项目设置 `rendering/textures/vram_compression/import_etc2_astc=true`（仓库已启用）。

Windows 发行版启动验证：

```bash
./build/windows/LastBastion.exe --headless --quit-after 120
```

退出码为 0，仅出现 Godot 退出时的资源泄漏提示（不影响运行）。

## 已知警告

以下输出是预期行为，不视为失败：

- `Camera2D overridden to physics process mode due to use of physics interpolation.` —— 项目使用物理插值，Godot 会自动切换 Camera2D 的更新模式。
- 退出时 `N resources still in use at exit` —— 测试场景快速 `quit()` 时，部分资源尚未释放；发行版正常退出不会出现。
- 无头模式下音频驱动使用 Dummy，音频测试只验证总线、层音量与播放状态，不验证实际声卡输出。

## CI

仓库包含 `.github/workflows/ci.yml`，在 Ubuntu 上使用 Godot 4.7.2 headless 依次运行 smoke / campaign / integration 三个测试场景。性能门禁依赖真实 GPU，保留为发布前手动步骤。

## 叙事层测试（v2.0）

```bash
"$GODOT" --headless --path . res://tests/narrative.tscn
```

覆盖 104 项：

| 分组 | 检查内容 |
|---|---|
| 数据 | 4 名幸存者、被动注册表、独白、23 份档案、四层密级、4 个派系 |
| 档案 | 专家门槛拒绝/接受、配额判定、额外刷新、深渊前置、遮蔽标题 |
| 派系 | 敌意公式（档案/击杀/任务）、关系矩阵、巡逻密度、单位权重、混战配对 |
| 对话 | 四角色 bark 池、林远 1/3 台词量与 1.5s 沉默、4-1 台词占比 |
| 被动 | 林远潜行不可见、马库斯背刺格挡与正面伤害、维克多 1.2× 特感增伤、露西亚掩体探测器 |
| 表现 | 档案拾取点/掩体/派系调度器存在、漫画层 shader material、gore 参数 |
| UI | 角色选择 4 卡、档案库列表、阅读器暂停/恢复、最终抉择解锁条件、中局抉择写标记 |
| 关卡 | 11 关章节映射、3-1A/3-1B 路线切换 |

测试会临时改写 `SaveSystem.data` 与 `ArchiveManager` 运行时状态，结束后不落盘；
`ArchiveManager.reset_progress(false)` 保证不污染真实存档。
