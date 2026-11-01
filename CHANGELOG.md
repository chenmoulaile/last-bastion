# LAST BASTION 更新日志

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
