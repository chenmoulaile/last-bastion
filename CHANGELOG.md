# LAST BASTION 更新日志

## v3.4.6（v3.4.5 后施工轮 · wp1–wp12 修复/内容/验收合并版）

### 缺陷修复
- **wp1 门洞进入修复**：破门后进入内部房间一发性失效的双通道修复——`level_runner.gd` 新增 `_entry_areas` 登记表、`door_broken` 破门瞬间补查与 `_physics_process` 驻留轮询兜底，冷却移至传送成功路径；integration 新增「贴门破门不松键即入屋」「门外走入门洞传送」两场景断言（未修复代码反向验证恰好命中场景 A）。
- **暗关天空黑带修复**：`level_runner.gd` sky 视差层由单张不平铺改为 mirror 平铺（与 far/mid 层既有做法一致）——相机右移 x 后屏幕右侧留下宽 `x*0.03` 的无天空黑带（l10@50% cam=8000 → 240px 黑带），wp6 关卡延长后暗关亮度断言 near_black 0.247→0.343 越线暴露；实测 5 张 `bg_*_sky` 纹理左右边缘均值差 ≤1/255 平铺无缝，修复后 6 个暗关断言点 near_black 全部回落 0.034~0.053。
- **wp3 蹲下体型修复**：管线为 crouch 独立 `CROUCH_H=30` 重生成 6 角色（30/44=0.68 落入规格 55-75%，顺带修复呼吸帧脚底浮空 1-2px）；`player.gd` 蹲立切换同步碰撞体 12x28↔12x18 并带头顶净空检查，idle/run 等其余条带哈希字节级不变。
- **wp9 HUD 键位标签出屏**：武器面板 4 个键位标签改为 add_child 后再设 size（绕开 ThemeDB 默认字体 min size 钳制）；截图断言扩到 12 屏 ×（越界 + 7 类可交互性检查），并修复暗关对话横幅污染后续截图的套件隔离缺口。

### 动画与表现
- **wp2 run 条带重做**：6 角色 run 改为「AI run_a 上半身 2px 起伏 bob + 程序化交替腿循环」，弃用 v3.4.4 的 mirror_legs 镜像路线；逐帧验收（腿带 XOR 8-20px/方向交替/躯干起伏/wrap 连续）全 PASS。
- **wp10 杂点清零与角色描边**：7 张 PNG 残余杂点全部→0（新增 `tools/assert_no_stray_dots.py` 进 `ci_checks.bat` 第 6 步）；新增 1px 半透暖白描边 `shaders/player_outline.gdshader`，l10 实机 6 点位修前/修后截图目检轮廓全部可辨。

### 关卡与室内
- **wp4 多房间复杂室内**：5 主题剧情化室内链（suburb 客厅→卧室→厨房、subway 站厅→票房→检修通道等），房间间 4-tile 门洞非传送、one-way 台阶堆上下层、家具掩体战术走位、补给分布非出口房间、出口在最后房间远端。
- **wp6 关卡剧情扩充**：11 关 length 延长 42.1%-45.8%（time_target 等比联动保持得分曲线）、事件 128→188 且 maxgap 收敛 ≤0.14、新增 14 段对话（dialogues.json 13→27）+ lore 告示牌×10 + 广播×11 + 队伍提示×4。

### 敌人与节奏
- **wp5 僵尸节奏与数值加强**：导演新增 min_alive 涓流与 10-18s 主动休止、潮概率与重建速度上调；19 只僵尸数值加强（普通 HP +30%/伤害 +20%/速度 +12%/攻击间隔 0.45s，特感 HP +25%，Boss HP +20%）；5 分钟真实速率模拟场上僵尸时间占比 96.4%、开局初始空窗后最长空窗 0.9s。
- **wp7 11 关 Boss 重做**：每关一个有名字/独立机制的 Boss（BossEngine 配置驱动 + 既有 boss-kind 场景薄壳，`level_runner.gd` 零改动），HP 2400→4200 按关递增、每关 2-3 个带 telegraph 预警的招牌招式、≤50% 血阶段变化、死亡统一掉落战利品。

### 窗口与设置
- **wp8 默认最大化与窗口模式**：无档默认最大化启动；settings 画面页「窗口化/最大化/全屏」三态循环即时生效并持久化（旧 fullscreen 布尔字段双向同步）；主菜单 F11 改走 ConfigManager 落盘，修复切换不保存重启回退。

### 测试与发布
- **wp11 验收扩容进 CI**：integration 214→431 断言（boss 套件整体并入 + 节奏单元级断言）、narrative 157→276（11 关剧情逐关精确值 + 僵尸数值表）；`ci_checks.bat` 6 步串联；根修 run_seed 按时间随机导致的 flaky（测试固定 LAYOUT_SEED=20261111 + 门口 ±40px 地面筛选）。
- **wp12 真实实操验证**：真实窗口 + 真实键鼠（SendInput 扫描码驱动）完整实操 l01：主菜单→街道推进 91%→室内全流程→Boss「诱蚀屠夫」9 轮交战，全程 0 SCRIPT ERROR；Boss 卡 91% 未达成撤离/结算，如实记录。
- **版本号递增 v3.4.6**：`project.godot` `config/version`，Windows 导出元数据 `file_version/product_version`，macOS `short_version/version`，共 5 行（均为实际存在字段）。
- **发布准备轮**：本轮不 push、不打 tag、不发 GitHub Release、不自行导出 EXE/ZIP，导出由流程统一执行。

## v3.4.5（v3.4.6 前一轮 · 发布准备收尾版）

- **版本号递增 v3.4.5**：`project.godot` `config/version`，Windows 导出元数据 `file_version/product_version`，macOS `short_version/version`，共 5 行（均为实际存在字段，无其他版本字段需要改动）。
- **发布准备轮**：本轮不 push、不打 tag、不发 GitHub Release、不自行导出 EXE/ZIP，导出由流程统一执行。
- **v3.4.4 条目保留**：v3.4.4 从未发布过 GitHub Release，其条目原样保留、不合并压缩。

## v3.4.4（v3.4.5 前一轮 · 建筑覆盖/动画/AI 强化合并版）

### 建筑与关卡
- **wp1 全主题建筑覆盖**：`building_builder.gd` 放开主题门槛，subway/military 新增矮楼/营房立面变体并修复开窗死代码；11 关全部 `_buildings=4 enterable=2 cells>0`（l05/l06/l08/l10/l11 不再为 0），门与绳降点随建筑自动出现。
- **wp2 程序化立面**：新增 `tools/gen_facade_tiles.py` 生成 5 主题立面图集 `facade_{theme}.png`（砖墙/抹灰/檐口/门楣立柱/地板），窗芯叠窗框并加 1/3 亮窗变体、门旁挂门牌，摆脱「立面=路面砖」观感。
- **wp5 内部房间加固**：传送制内部房间链路验证+断言固化+真实窗口截图；过程中修复相机右界把远端房间挡在画外的缺陷（仅改 `level_runner.gd` 8 行）。

### 角色与动画
- **wp3 手臂随枪旋转**：`player.gd` 的 `_draw()` 改为肩点→握把的随 `aim_angle` 连续旋转手臂线（primary 前后手 / secondary 单臂 / melee 不画）；`ally_agent.gd` 新增 `_update_arm_visual` 保人枪同角。
- **wp4 僵尸攻击 4 真姿势条带**：生成端 `tools/gen_ai_s2.py` 新增 `pose_attack()`（预备→前挥→接触+爪痕→收回），重生成 18 张 `*_attack.png` 与 2 张 `*_punch.png`；普攻伤害经 `_defer_contact_hit` 延迟到接触帧结算。
- **wp7 步态 8 姿势**：`tools/gen_ai_sprites.py` 新增 `mirror_legs()`（仅水平翻转髋线以下腿带、镜像轴取腿带不透明像素重心），run 条带改为前半程原腿+后半程镜像腿，6 角色 `{char}_run.png` 重生成。

### 敌人 AI
- **wp6 信号局特工战术化**：受击瞬移换位（5s 冷却+残影+微屏震）、周期诱导尸群（玩家 500px 内每 18s 召 1-2 只）、死亡反制爆发（4s 大范围干扰+屏震）；干扰消费端 `hud.gd` 准星抖动+全屏静电噪点层。

### 测试与发布（wp8）
- 全量验收门：smoke `33/0`、campaign `209/0`、narrative `149/0`、integration `96/0`（连跑 3 轮）、performance PASS（avg 196.7 FPS / min 39.1 / commons 117 / peak 85.9MB）。
- narrative 特工召喚断言由「等 0.6s 后计数」改为「0.6s 逐帧峰值采样」（召出僵尸可能被小队火力在窗口内击杀导致稳定漏计）；integration 绳降测试改为取第一个脚下有真实地面的窗（随机地形下 `windows[0]` 可能悬在坑洞上方的偶发加固）。
- 版本号递增 v3.4.4：`project.godot` `config/version`，Windows 导出元数据 `file_version/product_version`，macOS `short_version/version`。

## v3.4.3（本轮 · 缺陷修复与体验升级合并版）

### P0
- **P0-1 角色帧去除烤入枪械**：6 角色 × 9 动画全部用 4×3 无枪姿势表重生成（12 格：idle + 4 步态 + aim + melee + hurt + crouch + collapse + dead + jump）。武器由 `WeaponSprite` 叠加，手臂姿态按武器类别程序化切换（primary=双手端枪 / secondary=单手持枪 / melee=徒手）。`tools/assert_no_baked_weapons.py` 断言 0 违例。
- **P0-2 武器贴图清理**：`tools/clean_weapon_sprites.py` 连通域分析，共清除 368 个杂点像素（m9 32、ar15 部分、chainsaw 46、lmg 97、smg 39、sniper 39、shotgun 21 等），残留组件 = 0；武器亮度/对比度提升一档。
- **P0-3 主菜单底部裁切**：提示条与版本号上移至 y≤338 并用 fit_width；UI 越界断言扩展到全部 10 屏（含 main_menu/level_select/settings/archive_menu/result），档案库列表补滚动。
- **P0-4 脚本错误清零**：`fx.gd` 血渍静态数组改 WeakRef + 无类型接收校验 + `_prune_decals()`；`Fx.reset()` 挂到 `GameManager.change_state`；pickup/hazard_zone 的 monitoring 切换改 `set_deferred`。10 分钟自动试玩 0 SCRIPT ERROR。

### P1
- **P1-5 建筑真实化**：`BuildingBuilder` 在街道主题（suburb/city/bridge）生成带外墙/门框/窗洞的 2 层建筑体；门嵌在门框里（禁止悬空门）；前 2 幢可踢门进入真实内部房间（地板/墙/二层平台/掩体/补给/出口区），绳降窗挂在真实窗洞；隐藏房间改为有墙顶 + 遮蔽板滑开揭露反馈的真实房间。
- **P1-6 动画重做**：run 6→8 帧（触地→蹬伸→腾空→落地完整步态 + 躯干起伏）、idle 4 帧呼吸、crouch 3 帧、jump 起跳/下落分离；动画播放速率随移速缩放；新增脚步声与触地帧（0/4）同步。
- **P1-7 僵尸多样化**：跳跃去同步（0.1-0.5s 随机延迟 + 初速 ±15% + 水平 ±10%，25% 攀爬型坑边绕行）；三种攻击（抓挠 / 0.3s 前摇冲刺扑击带击退 / 双手挥打位移）；速度三档 ±20%；0.2-0.6s 嗅探停顿；20% 侧向包抄。

### P2
- **P2-8** 蹲下默认绑定 Ctrl + S 双键，教程提示同步「Ctrl/S 蹲下·滑铲」。
- **P2-9** 准星打磨：刻线 4→6px + 外端 1px 暗色收边；开火瞬间中心 2×2 十字亮点；最大扩散外圈 4 角标警示；击杀/爆头命中标记首帧白色 flash。

### 测试
- smoke / narrative(145) / integration 全绿；UI 越界断言覆盖 10 屏；武器杂点断言 + 无烤入枪械断言新增；10 分钟自动试玩 0 SCRIPT ERROR。
