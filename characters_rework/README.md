# characters_rework — 角色系统重构包

数据驱动的可玩角色与指挥士兵系统。所有角色差异来自 `.tres` 资源，控制器和渲染器内部没有角色分支。

- 6 名可玩角色（`data/playable/*.tres`）
- 4 个指挥兵种（`data/soldiers/*.tres`）
- 全部美术由 `CodeRenderer` 程序化绘制，无外部贴图依赖
- 通过 `EventBusBridge` 只读转发到现有 `EventBus`，不修改总线信号签名
- 与现有 `scripts/` 系统**共存**，可随时回滚（见 `INTEGRATION_GUIDE.md`）

## 目录结构

```
characters_rework/
├── data/
│   ├── CharacterData.gd          ReworkCharacterData：角色属性/配色/被动/叙事映射
│   ├── SoldierData.gd            ReworkSoldierData：兵种属性/武器/策略 ID
│   ├── palettes.gd               调色板辅助
│   ├── playable/*.tres           6 名可玩角色
│   └── soldiers/*.tres           4 个指挥兵种
├── playable/
│   ├── PlayerControllerV2.gd     CharacterBody2D 控制器
│   └── passives/                 7 个被动组件
├── rendering/
│   ├── CodeRenderer.gd           程序化绘制基类（动画时钟/姿态/零分配 _draw）
│   ├── PlayerRenderer.gd         角色绘制
│   ├── SoldierRenderer.gd        兵种绘制
│   └── shapes.gd                 多边形图元库
├── soldiers/
│   ├── SoldierBase.gd            指挥士兵基类
│   ├── components/               移动/战斗/阵型/指令组件
│   └── strategies/               4 个兵种策略 + 工厂基类
├── ui/
│   ├── CharacterSelectV2.gd       角色选择界面（离屏预览）
│   └── CharacterSelectV2.tscn
└── integration/
    ├── EventBusBridge.gd          新系统 → 旧 EventBus 单向桥
    ├── smoke_tests.gd             94 条冒烟测试
    └── smoke_tests.tscn
```

## 可玩角色

| ID | 名称 | 被动 | 主武器 | 叙事映射 |
|---|---|---|---|---|
| `assault` | 突击兵 | 突击冲锋 | AR-15 | 通用 |
| `heavy` | 重装兵 | 盾墙 | LMG | 马库斯 |
| `medic` | 医疗兵 | 战地医疗 | SMG | 维克多 |
| `scout` | 侦察兵 | 战术翻滚 | SMG | 露西亚 |
| `operative` | 特勤 | 影袭 | 武士刀 | 林远 |
| `officer` | 军官 | 激励 | AR-15 | 通用 |

`narrative_id` 字段是新增的**可选**字段，空值表示通用角色。映射只影响档案/叙事解锁，不改变战斗数值。

## 指挥士兵

`SoldierBase` 通过四个组件工作：

- `ReworkMovementComponent`：重力、槽位寻路、卡住跳跃脱困、朝向
- `ReworkCombatComponent`：索敌、视线检测、点射/换弹、命中判定
- `ReworkFormationComponent`：跟随/推进/防守/集火四种指令下的槽位偏移
- `ReworkOrderComponent`：指令状态机与锚点

兵种差异全部在 `RoleStrategy` 子类中：`RiflemanStrategy`、`MGStrategy`、`DemolitionStrategy`、`FieldMedicStrategy`。

## 运行冒烟测试

```bash
Godot --headless --path . --quit-after 600 res://characters_rework/integration/smoke_tests.tscn
```

预期输出：

```
[CHARREWORK] checks=94 failures=0
[CHARREWORK] RESULT: PASS
```

测试覆盖：数据完整性、6 个叙事映射、4 个兵种策略、角色/士兵实例化、组注册、桥接转发、被动脚本与渲染脚本可加载性。

## 设计约束

- Godot 4.7.2 / GDScript，静态类型注解，`.connect(callable)`
- 全部继承 `CharacterBody2D`，不使用 `KinematicBody2D`
- `_draw()` 只读预分配数组，不在绘制期创建节点/数组/闭包
- 不修改现有 `EventBus` 信号签名
- 战斗数值来自 `.tres`，与旧系统保持一致

## 已知限制

- 角色选择界面 `CharacterSelectV2` 需要真实渲染帧才能生成预览；headless 下自动回退为色块占位，不崩溃。
- `PlayerControllerV2` 的 `character` 别名是 `ReworkCharacterData`，旧 HUD 按 `CharacterData` 读取，因此默认关卡仍使用旧玩家场景。切换步骤与兼容层建议见 `INTEGRATION_GUIDE.md`。
- 士兵 AI 的寻路是水平槽位跟随 + 跳跃脱困，不含导航网格；复杂多层地形需要外部导航或手工放置。
