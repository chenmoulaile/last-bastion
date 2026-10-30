# AUDIT_REPORT · LAST BASTION

**审计日期**：2026-10-30  
**发布标签**：`v3.1.1-GoldAudit`（用户确认；原任务写作 `v2.5.0-GoldAudit`，但仓库 HEAD 已是 `v3.1.0` 且 `v2.5.0` 旧标签已存在）  
**审计基线**：`fcdc1b5`（v3.1.0）+ 工作树中上一轮未提交修复 + 本轮修复  
**引擎**：Godot 4.7.2-stable，gl_compatibility  
**测试机**：Intel(R) UHD Graphics 630，OpenGL 3.3.0 Build 27.20.100.8783，Windows 10.0.26200 x64  
**证据目录**：`docs/evidence/v2.5.0/`（目录名沿用原任务要求；发布 tag 为 v3.1.1-GoldAudit）  
**Windows 构建**：`build/windows/LastBastion.exe`（128,403,880 字节，FileVersion 3.1.1.0）

---

## 0. 摘要

三个任务均已完成，但**不是全绿交付**：

- **任务一**：击杀统计在当前工作树中已存在（上一轮产出），本轮以 29 项断言验证通过；结算页原来把多人战绩表放在 `y=350`（画面高 360，表格完全在画面外），且多人主统计显示 0。已修复并纳入真实渲染截图。联机同步层原实现不可用（host/join 直接失败、玩家生成路径写死错误节点名、同步节点读写错对象），本轮修复后以**双进程 ENet 实测**验证：位置、血量、临时血量、朝向、状态、瞄准角全部复制成功，host/client 均 0 失败。
- **任务二**：用真实渲染后端（非 headless）产出五类截图、50+ 敌人压力截图、`--write-movie` 录像与抽帧。过程中发现并修复 **v3.1.0 的相机回归**：`CinematicCamera` 每帧把玩家相机强制写回世界原点 `(0,0)`，导致实际游玩镜头固定看天空、看不到玩家。这是无头测试不可能发现的缺陷，也是本轮最重要的视觉修复。真实 FPS 数据见 §2.3，官方性能门禁在本机通过，但 120 敌人场景是物理瓶颈（physics 33.58 ms/tick，最低 15 FPS 单帧）。
- **任务三**：清理了上一轮测试残留；发现并修复**导出版数据加载缺陷**——首版 exe 能启动但 PCK 内 `.tres` 变成 `.tres.remap`，动态加载器只认 `.tres`，导致关卡/派系/档案数据在 exe 中为空。修复后重导，exe 启动日志确认 11 关、20 武器、14 角色、19 僵尸、4 派系、81 个 SFX 全部加载。回归套件**并非全绿**：smoke/击杀统计/联机/证据/性能门禁通过；campaign/integration/narrative/integration_regression 仍有既有失败，详见 §3.1–3.2，本报告不把它们伪装成通过。

---

## 1. 任务一：击杀统计与联机同步

### 1.1 击杀统计：已存在，本轮验证而非重写

会话开始时，`record_player_kill()` / `get_all_player_stats()` 已经在工作树中（上一轮未提交产出），并非缺失。本轮没有重复实现，而是：

1. 用 `tests/verify_player_stats.gd` 驱动真实 `GameManager` autoload，覆盖 per-peer / per-weapon / 爆头 / 特感 / Boss / 倒地 / 救助 / 伤害、非法 peer、快照深拷贝、`complete_level` 合并、`start_level` 重置。结果：**29 passed, 0 failed**。
2. 修复测试自身的两个基础设施问题：
   - `start_level(..., [])` 向 `Array[StringName]` 参数传无类型数组会在运行时中断 `_initialize`，导致 `quit()` 永不执行、进程挂起（这是“测试卡死”的真实根因，不是引擎泄漏）。改为显式 `Array[StringName]`。
   - SceneTree `_initialize()` 执行早于 autoload `_ready`，关卡表尚未加载。测试主体改为 `call_deferred` 到首帧。
3. 修复结算页展示：
   - 多人战绩表原位置 `Vector2(24, 350)`、尺寸 `592x90`，完全在 640x360 画面外。
   - 现改为嵌入统计面板，`MultiplayerStats rect = (244,214) 364x76`，实测在画面内（截图 `05_result_panel.png`）。
   - 多人时顶部“击杀/爆头/特感/救助”原为 0；现在从 `player_stats` 聚合（本局示例：17 / 8 / 1 / 1）。
   - 面板不再依赖“结算时 NetworkManager 仍在线”，而是读取 `last_result.player_stats`，会话结束后仍能展示。

关键代码：

- `autoload/game_manager.gd:282` `record_player_kill()`
- `autoload/game_manager.gd:328` `get_all_player_stats()`
- `autoload/game_manager.gd:345` `_merge_player_stats_into_result()`
- `scripts/ui/result.gd:100` `_build_stats_panel()`（聚合 + 多人行压缩布局）
- `scripts/ui/result.gd:221` `_multiplayer_rows()`
- `scripts/ui/result.gd:226` `_build_multiplayer_stats_panel()`

### 1.2 联机同步：原实现是“能编译但不工作”的接线

逐项修复的真实缺陷：

| # | 缺陷 | 后果 | 修复 |
|---|---|---|---|
| 1 | `SceneTree.has_property("multiplayer")` 在 Godot 4.7 不存在 | `host_session()`/`join_session()` 在 `_get_mp()` 内报错返回，联机永远建不起来 | 改用 `get_tree().get_multiplayer()`；`_ready` 与 `_get_mp()` 统一路径（`autoload/network_manager.gd:23,32`） |
| 2 | `SceneTree.get("multiplayer")` 返回 null | 即使绕过上一条也拿不到 MultiplayerAPI | 同上 |
| 3 | `host_session()`/`join_session()` 用局部 `var peer` 遮蔽成员 `peer` | 成员 `peer` 永远为 null，外部读取网络 peer 失败 | 局部变量改名 `enet_peer`，成功后再赋给成员 |
| 4 | `_var_spawn_player()` 在 `Main` 下找名为 `LevelRunner` 的节点 | 实际关卡根节点名是 `L01`，RPC 生成玩家永远找不到关卡，联机玩家不会出现 | 新增 `_find_level()`，按 `spawn_network_player` 方法能力查找（`autoload/network_manager.gd:149,158`） |
| 5 | `PlayerNetworkSync` 在自己身上 `get("facing", 1)`（`Object.get()` 只接受一个参数）并读 `state` | 编译/运行错误；即使不报错，读到的也是 helper 自己的属性，不是玩家属性 | 重写为操作 `get_parent()` 的玩家节点；删除自持运动状态 |
| 6 | `is_local = true`、`peer_id = 本地 peer`、同步器 authority = 本地 peer 全部硬编码 | 每个远端玩家都被当成“本地/主机”，权威混乱 | authority 从玩家 body 读取；`is_local = authority == multiplayer.get_unique_id()`（`scripts/player/PlayerNetworkSync.gd:21`） |
| 7 | 同时跑 RPC 运动插值（20Hz）和 MultiplayerSynchronizer | 两套系统同时写 `position/facing/state`，会抖动、互相覆盖 | 单一数据源：MultiplayerSynchronizer；删除玩家运动 RPC 与 `_sync_loop` 的玩家广播 |
| 8 | `MultiplayerSpawner` 挂在每个玩家下，`spawn_path = ".."`，且从未使用 | 误配置、无效节点 | 移除；运行时玩家由 RPC/关卡生成，不依赖该 spawner |
| 9 | 玩家没有 `state` 属性 | 任务要求的“状态”无法同步 | 新增 `var state: String`，由 `_sync_visuals()` 与 `_emit_state()` 维护（`PlayerControllerV2.gd:106,1239,1273`） |
| 10 | 远程开火/换弹/切枪/倒地/复活 RPC 调用玩家上不存在的方法 | 运行时错误，且这些 RPC 没有实际调用点 | 删除死 RPC；离散状态由同步器覆盖，不保留空壳 |
| 11 | `spawn_network_player()` 先 `add_child` 再设 name/authority | 同步器构建时节点路径/权威未定，路径匹配和发送端可能错误 | name 与 authority 在 `add_child` 前设置（`scripts/levels/level_runner.gd:630`） |

同步器配置（运行时构建，因为玩家是运行时生成的，`.tscn` 里静态放节点无法匹配动态路径）：

- 位置：`position`
- 朝向/瞄准：`facing`、`aim_angle`
- 状态：`state`、`is_downed`、`is_dead`
- 生命：`hp`、`temp_hp`、`black_white`、`bleedout`、`downs`
- 物资：`medkits`、`pills`
- 所有属性 `property_set_sync(true)` + `REPLICATION_MODE_ALWAYS`
- 权威：玩家 body 的 `multiplayer_authority`；本地玩家由 `spawn_network_player(peer_id)` 在入树前设置

### 1.3 双进程 ENet 实测（真实网络回环，不是单进程 mock）

命令：

```bash
# 主机
Godot_v4.7.2-stable_win64_console.exe --headless --path . \
    res://tests/net_sync_probe.tscn -- --role=host
# 客户端（另一进程）
Godot_v4.7.2-stable_win64_console.exe --headless --path . \
    res://tests/net_sync_probe.tscn -- --role=client
```

实测断言（host 4 项 + client 12 项，均 0 failed）：

- 客户端连接成功，获得独立 peer id
- 客户端通过 `NetworkManager.rpc_player_spawn` 收到 `Player_1` 并生成真实 `PlayerControllerV2`
- 客户端确认节点存在后才让主机启动同步器（避免 `SceneCacheInterface` 对未知路径的永久丢包）
- 主机设置：`position=(900,240)`、`hp=77`、`temp_hp=5`、`facing=-1`、`state="walk"`、`aim_angle=1.25`
- 客户端收到：位置 `(900, 240)`、`hp=77`、`temp_hp=5`、`facing=-1`、`state="walk"`、`aim_angle=1.25`
- `PlayerNetworkSync.peer_id=1`，`is_local=false`
- 同一套配置下的静态控制节点 `Control.value=42` 也复制成功，证明不是玩家特有偶然

**重要集成约束**：Godot 4.7 的 `SceneCacheInterface` 对尚不存在的节点路径会缓存失效；主机不能在客户端节点存在前开始同步。未来接入正式联机会话时，必须按“客户端节点先存在 → 主机同步器后启动”的顺序，或改用 `MultiplayerSpawner`。本次测试已按此顺序设计。

### 1.4 任务一未完成/边界

- **没有 host/join 入口**：`host_session()` / `join_session()` 在全仓没有 UI 调用，多人模式目前只能从代码/测试进入。同步层已可用，但“玩家怎么在菜单里开始联机”仍未实现。
- **僵尸同步不完整**：`NetworkManager._process` 已按 20Hz 广播僵尸位置，但客户端没有僵尸生成路径（没有僵尸 spawner/生成 RPC），所以实际联机中客户端看不到僵尸。本次未实现僵尸 spawner。
- **远程开火表现未同步**：离散的枪口火光/弹道/换弹动作没有 RPC 实现（原空壳 RPC 已删除）；同步器只保证位置/状态/血量。
- **客户端击杀归属未端到端验证**：主机侧 `level_runner` 的 `record_player_kill` 已接线；客户端射击命中主机的完整链路没有 2 人真实射击测试。
- **未测 4 人、NAT、丢包/抖动**：只测了 2 个进程的本机回环。

---

## 2. 任务二：真实渲染证据（GUI 后端实测）

### 2.1 相机回归：本轮发现的最严重缺陷

**现象**：第一次真实渲染采集的五张玩法截图全部只有静态城市天际线，看不到玩家、僵尸和 Boss；HUD 正常、分数在涨。  
**根因**：

- `CinematicCamera._apply_camera()` 每帧执行 `camera_2d.global_position = combined`。
- `combined` 在 `_target_node == null` 时是 `Vector2.ZERO`。
- 全仓没有任何 `CinematicCamera.set_target(...)` 调用；`_bind_camera()` 也拿不到玩家相机，因为 `PlayerControllerV2` 没有 `camera` 属性。
- 结果：已绑定的玩家 Camera2D 被每帧钉在世界原点 `(0,0)`，玩家走到哪里镜头都不跟。

**修复**：

- `CinematicCamera` 新增 `_follow_offset`；无显式 target 时回退到 `_player_ref`（玩家）并加相机原始偏移。
- 没有玩家/目标时**不再写相机**，避免菜单/关卡切换时把镜头吸到原点。
- `PlayerControllerV2` 新增 `camera: Camera2D` 并在 `_build_camera()` 赋值，供 `CinematicCamera`、`ScreenShake` 读取。

**验证**：采集日志 `player start: (220.0, 288.0) camera: (220.0, 208.0)`，即相机 = 玩家 + `(0,-80)` 偏移；截图恢复显示玩家、僵尸、断肢血迹、油桶爆炸与 Tank。  
代码：`scripts/camera/cinematic_camera.gd:22,343,385`；`characters_rework/playable/PlayerControllerV2.gd:107,1133`。

### 2.2 五类截图（全部来自真实渲染，非 headless，非合成）

| 文件 | 内容 | 分辨率 |
|---|---|---|
| `docs/evidence/v2.5.0/01_main_menu.png` | 主菜单；页脚 V3.1.1 | 1280x720 |
| `docs/evidence/v2.5.0/02_combat_dismemberment.png` | 玩家射击、枪口火光/弹道、僵尸群、断肢血迹 | 1280x720 |
| `docs/evidence/v2.5.0/03_barrel_explosion.png` | 油桶爆炸、火焰、连杀提示 | 1280x720 |
| `docs/evidence/v2.5.0/04_boss_fight.png` | Tank 本体 + Boss 血条 | 1280x720 |
| `docs/evidence/v2.5.0/05_result_panel.png` | S 评级结算；顶部聚合 17 杀/8 爆头/1 特感；P1/P2 个人战绩表 | 1280x720 |
| `docs/evidence/v2.5.0/06_stress_50_enemies.png` | 压力场景，61 只存活/61 只在屏内 | 1280x720 |

补充：`movie_frame_02s.png` / `movie_frame_04s.png` 由 `--write-movie` 录制的 60fps AVI 抽帧，见 §2.4。

### 2.3 真实 FPS（GUI 渲染后端实测）

采集条件：1280x720 窗口，内部 640x360，VSync 关闭，`Engine.max_fps=0`，Intel UHD 630，OpenGL 3.3。  
最终采集（2026-10-30 15:25）数据：

| 场景 | 敌人数 | 样本 | min FPS | avg FPS | max FPS | 备注 |
|---|---|---|---|---|---|---|
| 基线（000 敌人） | 0 | 9 | 128.9 | 160.1 | 170.7 | 稳态(>1s) avg 153.4 |
| 50+ 敌人压力 | 61 存活 / 61 在屏 | 24 | 94.1 | 142.0 | 187.6 | 稳态(>1s) avg 143.0，min 94.1 |

官方性能门禁（`tests/performance.tscn`，120 普感 + 4 特感请求，实测 114 普感 + 3 特感存活，5 秒采样）：

```text
[PERF] frames=420 avg_fps=83.9 min_fps=15.0 commons=114 specials=3
[PERF] draw_calls=219 memory=92.3MB peak=92.5MB
[PERF] process=9.48ms physics=33.58ms objects=724 pairs=244
[PERF] RESULT: PASS
```

解释：

- 该门禁的判定条件是 `avg >= 60`、`commons <= 120`、`specials <= 4`、峰值内存 < 600MB，因此 **RESULT: PASS 是真实的门禁结论**。
- 但 `min_fps=15.0` 是真实单帧卡顿；`physics=33.58ms/tick` 已超过 60Hz 的 16.67ms 预算，说明 120 敌人场景在本机是**物理瓶颈**，不能宣称“稳定 60 FPS”。
- `docs/TESTING.md` 里的 813 FPS 是 Intel Arc 机器的旧数据，不适用于本机 UHD 630；本报告只使用本次实测。
- 压力场景的 avg FPS 在多次运行间有 142–180 的波动（机器负载/窗口焦点影响）；本报告采用最终一次 15:25 的完整记录，未挑选最高值。
- `--write-movie` 使用固定 60fps，不能作为 FPS 证据；FPS 全部来自不带 `--write-movie` 的实时运行。

### 2.4 `--write-movie` 录像与抽帧

- 录像：`E:/LastBastion-evidence/gold_audit.avi`（30.5 MB，1280x720 MJPEG，60fps，5.766667 秒）
- 抽帧：`docs/evidence/v2.5.0/movie_frame_02s.png`、`movie_frame_04s.png`
- Godot 报告：CPU 0.50s（1.44ms/帧）、GPU 2.90s（8.37ms/帧）、编码 4.36s（12.60ms/帧）
- 场景规模约 10 只普通僵尸 + 1 只 Hunter，**不是**压力场景；这些数字只说明该录像的渲染/编码成本。

### 2.5 任务二未验证项（如实标注）

以下项目**没有**被本次机器证据覆盖，不能写“已实装”：

- Light2D 明暗观感、色差、径向模糊、漫画网点、Trauma 震动的“手感”、侧链压缩后的 BGM 实际音量曲线、真实声卡输出。截图只能证明渲染管线整体有输出，不能证明这些后处理/音频在每个镜头都按设计生效。
- 120 敌人稳定 60 FPS：未达到（physics 33.58ms，min 15）。
- 其他 GPU、其他刷新率、长时间运行的对象数单调增长（泄漏）未测试。本次只做了短时对象计数与导出启动，不能宣称“无泄漏”。

---

## 3. 任务三：回归、清理、发布

### 3.1 测试结果（真实，不粉饰）

| 套件 | 结果 | 说明 |
|---|---|---|
| `smoke` | **PASS** | 32 checks / 0 failures；导出/数据加载修复后复跑仍 PASS |
| `verify_player_stats` | **PASS** | 29 passed / 0 failed |
| `net_sync_probe` | **PASS** | 双进程；host 0 failed，client 0 failed |
| `evidence_capture` | **PASS** | 0 failures；6 张截图 + FPS/对象遥测 |
| `campaign` | **FAIL（波动）** | 154 checks；首跑 3 个失败、复跑 7 个失败，全部是 `special spawned: ...`，随 RNG 变化 |
| `integration` | **FAIL** | 85 checks / 10 failures（确定性复现） |
| `narrative` | **FAIL** | 106 checks / 2 failures（确定性复现） |
| `integration_regression` | **FAIL** | 33 checks / 4 failures（确定性复现） |
| `performance` | **PASS（门禁）** | avg 83.9 ≥ 60、敌人上限/内存均达标；但 min 15、physics 33.58ms 见 §2.3 |

`docs/TESTING.md` 中写的 campaign 209 / integration 91 是旧数据；本次实际是 campaign 154 / integration 85。

### 3.2 既有失败清单（本次未修复）

**integration（10 项）**：

- gold pickup adds score
- gold pickup consumed
- checkpoint respawns player
- checkpoint respawn restores health
- checkpoint respawn returns player to checkpoint
- downed: revive grants 30 temp hp
- downed: second revive enters black-and-white
- downed: black-and-white caps max hp
- command: commander death fails run
- command: defeat reason recorded

**narrative（2 项）**：

- lin yuan passive attached
- frontal damage still lands

**integration_regression（4 项）**：

- 进入换弹状态
- 换弹进度 >= 70%，可取消窗口打开
- HealthComponent.damaged 信号发射（is_critical=true）
- 损伤数值传递正确

**campaign**：`special spawned: jockey/spitter/witch l02–l11`（首跑 3 项，复跑 7 项，位置随 RNG 变化）。

处理原则：这些失败集中在拾取、检查点、复活、换弹、HealthComponent、被动等本次未改动的旧系统。本次没有做 clean-HEAD bisect（会话开始时工作树已含上一轮未提交修改和未跟踪运行依赖，无法构成干净基线），因此**既不把它们归因于本次修复，也不宣称已修复**。它们应作为后续独立 QA 项处理。

### 3.3 导出包修复（本轮新发现的发布级缺陷）

首版导出验证：

- exe 能启动、退出码 0，但文件元数据是 `1.0.0.0`
- 启动打印 4 条 `Faction data missing`
- 根因：PCK 内资源变成 `name.tres.remap`，而 `GameManager` / `FactionManager` / `ArchiveManager` 的 `DirAccess.get_files()` 只过滤 `.tres`；因此编辑器里一切正常，exe 里关卡/派系/档案数据为空
- 同一模式还影响 `AudioManager._scan_sfx()`（`.ogg.remap`）

修复：

- 三个 `.tres` 加载器：`trim_suffix(".remap")`，同时接受 `.tres` / `.res`
- `AudioManager`：先去掉 `.import` / `.remap` 再匹配 `.ogg` / `.wav`
- 导出预设 `application/file_version`、`application/product_version` 改为 `3.1.1.0`
- 启动打印数据计数，便于今后导出验证

重导验证：

```text
[Data] levels=11 weapons=20 characters=14 zombies=19
[Audio] sfx streams=81 variants=77
[Data] factions=4
```

无 `Faction data missing` 警告；FileVersion/ProductVersion 均为 3.1.1.0；exe 128,403,880 字节；`--headless --quit-after 120` 退出码 0。  
限制：这是启动/数据加载验证，不是导出包内的完整通关脚本；`start_level` 使用的同一份 levels 字典已确认非空。

### 3.4 清理

已删除（上一轮测试残留）：

- 根目录：`gm_test.out`、`godot_edit.out`、`godot_init.out`、`godot_verbose*.out`、`godot_window.out`、`level_test.out`、`test_smoke.out`、`pns_test.txt`、`rmg_test.txt`、`zb_test.txt`、`zombie_test_result.txt`
- `out/probe*.png`、`out/probe.wav`、`out/frames/`
- `tests/probe_start_level.gd`、`tests/probe_min_quit.gd`（临时诊断）
- `.cache/`、`tools/scan.json`、`tools/scan_roots.py`
- 临时 baseline worktree `E:/LastBastion-baseline`

保留/新增：

- `.gitignore` 增加 `out/`、`.cache/`
- 30.5MB 录像移到 `E:/LastBastion-evidence/gold_audit.avi`（工程外，避免打进 PCK；仓内保留抽帧）
- `docs/evidence/v2.5.0/.gdignore`：防止证据目录里的 `fps_samples.csv` 被 Godot 当翻译表导入

### 3.5 发布

- **Tag**：`v3.1.1-GoldAudit`（用户确认）
- **版本**：`project.godot` 1.0.0 → 3.1.1；主菜单/制作名单页脚改为读取项目版本；Windows 导出元数据 3.1.1.0
- **构建**：`build/windows/LastBastion.exe`（123 MiB，gitignored，单文件嵌入 PCK）
- **说明**：证据目录仍叫 `docs/evidence/v2.5.0/`（尊重原任务路径），但 tag 按实际代码版本为 v3.1.1-GoldAudit。若需要把 exe 作为 GitHub Release 资产，需额外创建 Release 并上传（本次只做 commit + tag + push，未创建 Release）。

---

## 4. 变更文件概览

| 领域 | 文件 | 变更 |
|---|---|---|
| 击杀统计/结算 | `autoload/game_manager.gd`、`autoload/event_bus.gd`、`scripts/ui/result.gd` | per-peer 统计、合并进 last_result、多人表嵌入 + 聚合 |
| 联机同步 | `autoload/network_manager.gd`、`scripts/player/PlayerNetworkSync.gd`、`characters_rework/playable/PlayerControllerV2.gd`、`scripts/levels/level_runner.gd` | 修复 host/join、生成路径、权威、单一同步器、状态属性 |
| 相机 | `scripts/camera/cinematic_camera.gd`、`PlayerControllerV2.gd` | 跟随玩家、偏移、无目标不写相机；新增 `camera` 成员 |
| 上一轮 4 个修复 | `gamefeel/audio/AudioLayerManager.gd`、`shaders/post_process.gdshader`、`scripts/ui/hud.gd` | `unit_size`、shader hint/maxf、假延迟血条 |
| 导出/数据 | `autoload/game_manager.gd`、`scripts/faction/faction_manager.gd`、`scripts/archive/archive_manager.gd`、`autoload/audio_manager.gd`、`export_presets.cfg` | `.remap` 兼容、版本元数据、启动计数 |
| 版本 | `project.godot`、`scripts/ui/main_menu.gd`、`scripts/ui/credits.gd` | 3.1.1 版本号统一 |
| 测试/证据 | `tests/verify_player_stats.gd`、`tests/net_sync_probe.*`、`tests/evidence_capture.*`、`tests/movie_demo.*`、`docs/evidence/v2.5.0/` | 可复跑的统计/联机/截图/录像证据 |

上一轮的 4 个真实 Bug（`AudioLayerManager` 的 `unit_size`、shader 的 `vec2 hint_range`、shader 的 `maxf`、HUD 的假延迟血条）在会话开始时已存在于工作树；本轮复核后随本构建交付，**不是本轮新写**。其中 HUD 血条的“延迟感”属于视觉手感，本轮没有做逐帧人眼验收，只确认逻辑不再是“写目标值后对自己插值”。

---

## 5. 复现命令

```bash
GODOT="E:/DevTools/Godot/Godot_v4.7.2-stable_win64_console.exe"

# 击杀统计（29 项）
"$GODOT" --headless --path . --script res://tests/verify_player_stats.gd

# 联机双进程（两个终端/后台）
"$GODOT" --headless --path . res://tests/net_sync_probe.tscn -- --role=host
"$GODOT" --headless --path . res://tests/net_sync_probe.tscn -- --role=client

# 真实渲染五类截图 + FPS（必须非 headless）
"$GODOT" --path . --resolution 1280x720 res://tests/evidence_capture.tscn

# 官方性能门禁（必须非 headless）
"$GODOT" --path . --resolution 1280x720 res://tests/performance.tscn

# 60fps 录像 + 抽帧
"$GODOT" --path . --resolution 1280x720 \
    --write-movie out/gold_audit.avi --fixed-fps 60 res://tests/movie_demo.tscn
ffmpeg -y -ss 2 -i out/gold_audit.avi -frames:v 1 docs/evidence/v2.5.0/movie_frame_02s.png
ffmpeg -y -ss 4 -i out/gold_audit.avi -frames:v 1 docs/evidence/v2.5.0/movie_frame_04s.png

# 导出 + 启动验证
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/LastBastion.exe
./build/windows/LastBastion.exe --headless --quit-after 120
```

---

## 6. 证据索引

`docs/evidence/v2.5.0/`：

- `01_main_menu.png` — 主菜单（V3.1.1）
- `02_combat_dismemberment.png` — 战斗/断肢
- `03_barrel_explosion.png` — 油桶爆炸
- `04_boss_fight.png` — Tank Boss
- `05_result_panel.png` — 结算 + 多人战绩表
- `06_stress_50_enemies.png` — 61 敌人压力场景
- `movie_frame_02s.png` / `movie_frame_04s.png` — 录像抽帧
- `capture_log.txt` — 采集环境、FPS、每张图的像素统计
- `fps_samples.csv` — 逐样本 FPS/对象数/内存
- `performance_gate.txt` — 官方门禁原始输出与解释
- `build_verification.txt` — exe 启动/数据加载/版本验证

工程外：`E:/LastBastion-evidence/gold_audit.avi`（30.5MB 原始录像，未入仓）。

---

## 7. 仍需后续处理

1. 联机 host/join UI 与会话生命周期（客户端节点先于主机同步器存在）。
2. 僵尸生成/同步 spawner；远程射击/换弹表现。
3. 既有集成/叙事/回归测试失败（拾取、检查点、复活、换弹、HealthComponent、被动等）。
4. 120 敌人物理瓶颈（physics 33.58ms）与最低 15 FPS 的单帧卡顿。
5. 视觉手感/音频曲线/长时间泄漏的人眼与长跑验收。
6. 其他 GPU、4 人真实网络、NAT/丢包场景。
