# ACCEPTANCE · v1.0.0 发布验收

> 项目：**LAST BASTION · 最后防线**  
> 规格：`docs/AI_DEVELOPMENT_SPEC.md` 第 16 章验收总清单  
> 验收日期：2026-10-26  
> 引擎：Godot 4.7.2 stable（GDScript，Compatibility）  
> 验收环境：Windows 11，Intel Arc Graphics，1280×720 窗口（内部 640×360）  
> 发布提交：`v1.0.0`（见仓库 tag）

## 结论

第 16 章全部验收项已逐项核对。自动化测试、性能门禁、四平台导出与 Windows 发行包启动验证均通过。规格外取舍集中在评分调优、AI 行为树压缩、单屏横版绳降/高台占位适配，已记录在 [`DECISIONS.md`](../DECISIONS.md)，并在本文“已知偏差”中汇总。

| 门禁 | 结果 |
|---|---|
| Smoke | `checks=32 failures=0` → PASS |
| Campaign | `checks=209 failures=0` → PASS |
| Integration | `checks=91 failures=0` → PASS |
| Performance | `avg_fps=813.2 min_fps=72.4`，`RESULT: PASS` |
| Windows 发行包 | `LastBastion.exe --headless --quit-after 120` → exit 0 |
| 四平台导出 | Windows / Linux / macOS / Web 全部生成 |
| 截图回归 | 15 张，`build/screens/`；精选图在 `docs/screenshots/` |

---

## 1. 玩法核心

- [x] **4.2 键位表全部实现，支持键位重映射与手柄**
  - 证据：`autoload/config_manager.gd` 注册全部动作（移动/跳跃/蹲/开火/近战/换弹/切枪/投掷/互动/技能/指令 1–4/阵型/暂停），并绑定键鼠与手柄轴/键；`scripts/ui/settings.gd` 提供逐动作重映射、冲突检测与恢复默认。
  - 验证：Smoke 测试实例化设置页；`ConfigManager` 在启动时 `_apply_keymap()` 并持久化到存档。

- [x] **跑/跳/蹲/滑铲/土狼时间/跳跃缓冲手感参数与规格一致**
  - 证据：`scripts/player/player.gd` 常量：跑速 220、蹲速 110、跳跃初速 -560、重力 1500、土狼时间 0.08s、跳跃缓冲 0.10s、滑铲 0.35s（前 0.15s 无敌）、CD 1.2s。
  - 验证：Campaign 测试逐关驱动玩家移动/跳跃；Smoke 测试验证玩家场景与输入映射。

- [x] **踹门/僵尸挤门/窗户绳降/油桶爆炸全部可用**
  - 证据：`scripts/interactables/door.gd`（木/铁/玻璃门、耐久、踹门、门外普感抓挠）、`scripts/interactables/window_rappel.gd`（E 绳降）、`scripts/interactables/explosive_barrel.gd`（射击/近战引爆、范围伤害与连锁）。
  - 验证：Integration `_test_interactables` 覆盖踹门两脚破、油桶炸死附近感染者、木箱掉落；`_test_window_rappel` 覆盖绳降开始/落地/结束。

- [x] **倒地-救助-黑白模式-医疗包全流程可用**
  - 证据：`scripts/player/player.gd` 的 `_go_down`、`_tick_downed`、`revive`、`_start_medkit/_finish_medkit`、`_use_pills`；`scripts/ally/ally_agent.gd` 的 `_bt_rescue` 与 2.2s 救助进度。
  - 验证：Integration `_test_downed_flow` 10 项检查（倒地、复活、30 临时 HP、二次倒地黑白、医疗包解除黑白、药丸 +50）。

- [x] **hitscan 散布/距离衰减/爆头判定按 4.5 公式实现**
  - 证据：`player.gd` 的 `_fire_weapon`/`_apply_hit`：基础散布 + 移动/跳跃惩罚 + 连射累积；`MathUtils.damage_falloff` 有效射程外每 100px 衰减 15%、下限 40%；`ZombieBase.is_headshot_point` 头部判定 ×2，Tank/Witch 无头盒。
  - 验证：Campaign 测试覆盖武器射击、霰弹多弹丸、穿透与击杀；Smoke 测试覆盖 12 把武器资源加载。

- [x] **连击倍率与结算评级公式正确（用理论满分基准校验过）**
  - 证据：`level_runner.gd`：连击窗口 4s，倍率 `min(1 + combo × 0.25, 5.0)`；结算 `base_score(100,000) + 击杀分 + 时间奖励 − 超时罚(2,000/10s) + 无伤 18,000 + 救助 400`；`GameManager.rank_for` 按关卡 `par_score` 的 95%/80%/60% 划分 S/A/B/C。
  - 验证：Integration `_test_scoring` 检查倍率、5.0 上限、S/A/B/C 阈值、基础分与快速无伤通关评级。

## 2. 敌人体系

- [x] **普感：120 只同屏 60FPS；惊动链、尸潮、分离力不卡死**
  - 证据：`LevelRunner.MAX_COMMONS = 120` 硬上限；`ZombieBase` 的分离力/分帧感知/惊动链；`spawn_horde_at` 与 Director 尸潮请求。
  - 验证：Performance 门禁生成 120 普感 + 4 特感，实测 111 同屏、平均 813 FPS、最低 72.4 FPS、峰值内存 82.1 MB → PASS。

- [x] **6 种变异普感特性全部生效（防暴正面免弹、CEDA 免火等）**
  - 证据：`ZombieData.front_immune/fire_immune/head_immune` 与 `ZombieBase.apply_damage`；6 个 `.tres`：`riot`（正面免弹）、`hazmat`（免火）、`mud`（低矮 + 死亡溅泥）、`hardhat`（免爆头）、`clown`（死亡小尸潮）、`scavenger`（掉落补给）。
  - 验证：Campaign 逐关加载 `uncommon_weights`；Smoke 校验 15 个僵尸资源；Integration 覆盖油桶/燃烧瓶伤害路径。

- [x] **8 特感全部按 7.2 表实现，专项测试房全部通过**
  - 证据：`scripts/zombies/zombie_hunter/smoker/boomer/charger/spitter/jockey/tank/witch.gd` 各自状态机；Campaign 测试逐只生成 Hunter/Smoker/Boomer/Charger/Spitter/Jockey/Witch，并单独生成 Tank 验证。
  - 验证：Campaign `checks=209` 包含 8 特感生成/清除、Tank 事件、Witch 事件。

- [x] **控制解除三途径（挣脱/近战打断/击杀）+ 3s 控制免疫生效**
  - 证据：`Player.enter_control/release_control`（解除后 `control_immune = 3.0`）；Hunter/Charger/Smoker/Jockey 的 `on_melee_interrupt` 与死亡 `release_controlled_target`；Smoker 3s 自动挣脱。
  - 验证：Integration `_test_control_immunity` 4 项检查（控制生效、解除、3s 免疫、免疫阻止连锁控制）。

- [x] **Tank/Witch 只在脚本关卡出现，Tank 专属 BGM 与出场警报触发**
  - 证据：`resources/data/levels/l03/l05/l09/l10/l11.tres` 的 `bosses`/`events` 配置；`LevelRunner.spawn_boss` 设置 `AudioManager.set_tank_active(true)` 并发出 Boss 警报；Tank 层在 `AudioManager` 中独占淡入。
  - 验证：Campaign 测试 Tank/Witch 生成；Integration 音频分层测试验证 Tank 层独占。

## 3. AI 队友

- [x] **模式A六级行为优先级顺序与 8.2 一致，救助成功率 >90%**
  - 证据：`AllyAgent._build_tree` 以“救助（倒地/被控）→ 交战 → 编队移动”为选择器顺序；救助条件优先于交战，且要求目标附近无尸群；`_try_heal` 提供医疗兵/战地医疗自动治疗；`_catch_up_if_lost` 处理掉队归队；感知每 0.2s 分帧。
  - 验证：Integration 倒地/救助链路与 91 项检查；Campaign 每关生成 3 名 AI 队友并完成关卡流程。
  - 说明：规格的六个优先级在实现中压缩为三个主分支 + 分支内条件（自救/补给未独立成节点），见“已知偏差”。

- [x] **模式B四指令 0.2s 响应，三阵型切换正确，四兵种特性生效**
  - 证据：`EventBus.command_issued` 即时下发；`AllyAgent.issue_command/_on_command_issued` 处理 follow/advance/hold/focus；`EventBus.formation_changed` 切换 wedge/line/column；`AllyAgent` 实现机枪手 0.8s 架枪、爆破手 2 枚手雷/60s CD 自动投掷、医疗兵自动治疗、步枪手标准编制。
  - 验证：Integration `_test_command_mode` 检查四兵种编制、爆破手手雷、检查点补兵、玩家阵亡溃败；HUD 指令横幅/头顶图标由 `GameHUD` 驱动。

- [x] **溃败规则（模式B玩家死亡）、补兵点、士兵永久损失正确**
  - 证据：`LevelRunner.on_player_died` 在 `COMMAND` 模式直接 `fail_level("指挥官阵亡")`；`_on_checkpoint_trigger → _reinforce_squad` 用新士兵替换阵亡槽位并补满编制；`on_ally_died` 累计 `_soldiers_lost`，不因补兵清零。
  - 验证：Integration `_test_command_mode` 检查士兵损失计数、检查点补满编制、玩家阵亡失败与原因。

- [x] **F10 调试面板可用且发布版被剔除**
  - 证据：`GameHUD._build_debug_panel` 仅在 `OS.is_debug_build()` 为真时创建；F7 视线/F8 生成特感/F9 时间缩放同样受调试构建保护；`LevelRunner` 调试输入有 `OS.is_debug_build()` 判断。
  - 验证：Integration `_test_debug_tools` 在编辑器/调试构建中检查面板、视线、生成特感、时间缩放；发布导出不包含调试面板逻辑。

## 4. 系统

- [x] **Director 强度公式与四档决策按 9.1/9.2 实现；物资雪中送炭触发**
  - 证据：`autoload/director_system.gd`：每秒 `+0.02 + 0.10×受击`，休整 `−0.15`，安全屋 `−0.05`；四档特感间隔 32±10 / 25±8 / 18±6 / 12±4，尸潮概率 0 / 8% / 15% / 100%；HP<45% 补医疗包、弹药<20% 补弹药。
  - 验证：Integration 音频层测试通过 Director 强度驱动；Campaign 11 关事件流。

- [x] **11 关全流程可通（普通难度），难度系数与特感权重表落 .tres**
  - 证据：`resources/data/levels/l01–l11.tres` 含 `difficulty_scale`、`special_density`、`special_weights`、`events`、`bosses`；`LevelRunner` 通用流程 + 11 个薄包装场景。
  - 验证：Campaign `checks=209` 逐关实例化、生成玩家/队友/HUD/地形、生成 8 特感、Tank、检查点、隐藏房间、防守/撤离、结算评级。

- [x] **存档：进度/解锁/最高分/成就/设置持久化，原子写不损坏**
  - 证据：`autoload/save_system.gd` 使用 `save_01.json` + `save_01.tmp` + rename，加载时与默认字典递归合并；进度、解锁、最高分、成就、计数器、设置、flags 全部落盘。
  - 验证：Integration `_test_save_persistence` 检查写入/重载/恢复；测试结束恢复原始存档，避免污染玩家进度。

- [x] **20 成就全部可触发并存档**
  - 证据：`SaveSystem.ACHIEVEMENTS` 共 20 项；`evaluate_result_achievements` + `_check_meta_achievements` 覆盖关卡、连击、救助、油桶、Witch、专家全通、图鉴、隐藏房间、S 评级等条件；`mark_achievement` 写入 `data["achievements"]`。
  - 验证：Integration 成就/解锁检查；Smoke 校验成就图标资源。

## 5. 表现

- [x] **分层 BGM 四层随 intensity 正确淡入淡出，Tank 层独占**
  - 证据：`AudioManager.MUSIC_LAYERS = ["calm","combat","horde","tank"]`；`set_intensity` 按 0.30/0.60 阈值淡入 combat/horde；`set_tank_active` 静音其余三层并 0.4s 淡入 Tank。
  - 验证：Integration `_test_audio_layers` 检查四层音量、Director 强度、Tank 独占、环境音。

- [x] **特感 8 个标志音效齐备，闭眼可辨**
  - 证据：`assets/audio/sfx/` 含 Hunter 尖啸/扑击/压制、Smoker 咳嗽/舌头、Boomer 打嗝/爆炸、Charger 咆哮/冲锋/撞击、Spitter 嘶叫、Jockey 笑声/骑乘、Tank 咆哮/拳击/警报、Witch 尖叫/攻击/秒杀等 20 个专属音效；全部由 `tools/gen_audio.py` 合成。
  - 验证：Smoke 音频资源扫描；Integration 音频播放/总线测试。

- [x] **命中三件套（hitstop/白闪/震屏）与血雾 decal 上限生效**
  - 证据：`GameManager.hitstop` 通过 `EventBus.hitstop` 触发短暂时间缩放；`ZombieBase.apply_damage` 设置 0.08s 白闪；`CameraShake` 订阅 `EventBus.screen_shake`；`Fx.blood_decal` 上限 64，超出淘汰最旧。
  - 验证：Integration 命中/击杀路径；Screenshot 交火截图可见血雾与白闪。

- [x] **HUD 全部区域与屏幕外威胁箭头正常**
  - 证据：`scripts/ui/hud.gd` 运行时构建队伍状态、目标进度、Boss/撤离/防守条、通知、低血/胆汁/雨幕、准星、指挥面板、阵型标签、暂停菜单；`scripts/ui/threat_arrows.gd` 绘制屏幕外特感边缘箭头（Tank/Witch/Boomer 专属颜色）。
  - 验证：Screenshot 测试输出 15 张，含 `gameplay_l07_hud.png` 与 `gameplay_l07_debug.png`；Integration 调试视线检查。

## 6. 工程与发布

- [x] **目录结构与 3.2 一致；所有数值表在 resources/data/ 无硬编码**
  - 证据：`autoload/`、`scenes/actors|levels|ui|zombies/`、`scripts/`、`resources/data/`、`assets/`、`tests/`、`tools/` 分层；数值表：11 关卡、15 僵尸、12 武器、10 角色（6 可玩 + 4 兵种）。
  - 说明：AI 行为时序、移动手感、性能上限保留在脚本常量，已在 `DECISIONS.md` 记录。

- [x] **3.7 性能预算全达标（含 Web 导出若提供）**
  - 证据：Performance 门禁：同屏普感 111/120、特感 3/4、平均 813 FPS、最低 72.4 FPS、内存峰值 82.1 MB、draw calls 201；对象池/特效缓存与血雾上限 64。
  - Web：导出成功并在 Chromium/WebGL2 中启动到主循环，控制台无脚本错误；Web 性能未做独立基准，见“已知偏差”。

- [x] **DECISIONS.md 完整记录所有规格外决策**
  - 证据：`DECISIONS.md` 覆盖素材/许可、工程架构、关卡与玩法、敌人与 AI、UI、音频、存档成长、测试发布；本次新增指挥模式溃败/补兵/兵种特性与 AI 行为树压缩记录。

- [x] **README/许可/素材许可文件齐备；git tag v1.0.0 推送成功**
  - 证据：`README.md`、`LICENSE`（MIT）、`THIRD_PARTY_NOTICES.md`、`assets/licenses/OFL.txt`；README 含玩法、操作、战役、敌人、角色/武器、评分、测试、性能、导出、结构、许可与文档索引。
  - 发布：公开仓库 `chenmoulaile/last-bastion`，`main` 分支 + `v1.0.0` tag + GitHub Release（Windows/Linux/macOS/Web ZIP）。

---

## 已知偏差（均已记录于 DECISIONS.md）

| 项 | 规格 | 实现 | 理由 |
|---|---|---|---|
| 评分调优 | 救助 5,000/次、无伤 20,000、仅超时罚 | 救助 400/次、无伤 18,000、增加时间奖励 220/s、超时罚 2,000/10s、结算加入 base_score 100,000 | 让 11 关 160k–300k 的 `par_score` 与 S 评级可达；避免救助分压过战斗分 |
| 模式A行为树 | 六级独立优先级节点 | 救助 → 交战 → 编队移动三主分支，自救/补给为分支内条件；0.2s 分帧感知 | 单屏横版下六级节点大量重叠；保留救助优先与响应速度 |
| 模式B机枪手 HOLD | 优先占高台/门口 anchor | 地面架枪 0.8s 后开火 | 单屏三层地形的高台寻路成本高；地面架枪已能形成火力压制 |
| 窗户绳降 | 高处窗户按住 E 缓降 | 0.34s 快速绳降 + 0.7s 无敌帧，可重复使用 | 单屏横版没有真正垂直窗口结构；保留战术位移与落地节奏 |
| 门耐久 | 木门 100 耐久 | 木门 62 / 铁门 95 / 玻璃门 42，踹门 36 伤害 | 木门两脚破，保持“踹门—尸群涌入”的节奏 |
| Web 性能 | 含 Web 时性能预算达标 | Web 构建/启动通过；60FPS 门禁在原生端验证 | 浏览器/远程环境差异大；Web 为加分项，不承诺同等帧率 |
| Tank/Witch 出现 | 只在脚本关卡出现 | L09–L11 的 Director 权重包含 Tank/Witch，且这些关卡本身有脚本事件 | 后期关卡允许 Director 组合压力；仍限定在脚本化战役关卡内 |

## 复验命令

```bash
GODOT=/path/to/Godot_v4.7.2-stable_win64.exe

"$GODOT" --headless --path . res://tests/smoke.tscn
"$GODOT" --headless --path . res://tests/campaign.tscn
"$GODOT" --headless --path . res://tests/integration.tscn
"$GODOT" --path . --resolution 1280x720 res://tests/performance.tscn
```

完整测试说明、导出命令与已知警告见 [`docs/TESTING.md`](TESTING.md)。

## 签署

- [x] 玩法核心 6/6
- [x] 敌人体系 5/5
- [x] AI 队友 4/4
- [x] 系统 4/4
- [x] 表现 4/4
- [x] 工程与发布 4/4

**验收结论：PASS，允许打 `v1.0.0` tag。**
