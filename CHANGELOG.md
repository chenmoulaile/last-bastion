# LAST BASTION 更新日志

## v3.4.4（本轮 · 建筑覆盖/动画/AI 强化合并版）

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
