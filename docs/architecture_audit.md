# 主流程切换架构审计报告

审计日期：2026-10-29
审计范围：上一阶段（Agent 1）的“打补丁式修复”代码

## 1. 循环依赖

### 1.1 ItemComponent ↔ PlayerControllerV2

**发现**：`PlayerControllerV2.gd` 原有 `const ITEM_COMPONENT_SCRIPT := preload("res://scripts/items/ItemComponent.gd")`，而 `ItemComponent.gd` 原有 `var _owner: PlayerControllerV2`（类型转换 `owner as PlayerControllerV2`），形成循环 preload 依赖。

**修复**：
- `ItemComponent.gd` 移除 `PlayerControllerV2` 类型引用，改用 `var _owner_ref: Node = null` 与动态 `get()`/`set()`/`call()` 访问 owner 属性。
- `PlayerControllerV2.gd` 移除 `ITEM_COMPONENT_SCRIPT` / `CHARACTER_DATA_COMPAT_SCRIPT` preload 常量，改用 `_setup_item_component()` 中的 `(load("res://scripts/items/ItemComponent.gd") as GDScript).new()` 运行时加载。

**状态**：**已修复** — 无循环 preload 依赖。

## 2. 类型转换

### 2.1 `_character_compat` 类型不匹配

**发现**：`PlayerControllerV2.gd` 中 `_character_compat` 原被声明为 `CharacterData` 类型，但实际赋值为 `CharacterDataCompat` 资源实例，在 Godot 4.7.2 静态类型检查下可能产生类型不匹配。

**修复**：将 `_character_compat` 声明为 `Resource` 类型，`character` Getter 返回 `Resource`，旧 HUD 通过 `.get("character")` 读取时无需类型转换。

**状态**：**已修复**。

### 2.2 `as` 转换空值保护

**发现**：多处 `as` 类型转换缺少空值保护，可能在运行时导致 `Invalid cast` 错误。

**修复**：`ItemComponent.gd` 中所有 owner 属性访问均通过 `if _owner == null: return` 保护；`GameFeelBridge._on_health_damaged()` 中 `target.get("last_damage_type")` 使用 `str()` 转换避免 `StringName(Variant)` 构造器错误。

**状态**：**已修复**。

## 3. 实例化方式

### 3.1 `level_runner.gd` 玩家生成

**发现**：`PLAYER_SCENE` 被定义为 `preload("res://characters_rework/playable/PlayerControllerV2.gd")`（GDScript 资源），原代码尝试 `PLAYER_SCENE.new()` 但 `GDScript` 对象无 `new()` 方法。

**修复**：`_spawn_player()` 直接使用 `PlayerControllerV2.new()`（CharacterBody2D 子类可直接实例化），旧 `player.tscn` 保留为 `Player_Legacy_Disabled` (`PROCESS_MODE_DISABLED`)。

**状态**：**已修复** — 玩家节点正确生成，旧节点保留为 disabled。

### 3.2 场景树结构

**发现**：`PlayerControllerV2` 作为 `CharacterBody2D` 子类，其场景树结构（CodeRenderer、碰撞形状、MuzzlePoint 等）需通过代码在 `_setup_renderer()` 中动态构建。

**状态**：**已验证** — `_setup_renderer()` 在 `_ready()` 中调用，正确构建渲染器。

## 4. InputBuffer 签名

### 4.1 `consume()` 参数数量

**发现**：`InputBuffer.consume("fire", 0.3)` 使用两参数版本，但 `InputBuffer.gd` 中 `consume()` 方法签名需确认支持两参数。

**修复**：`InputBuffer.gd` 的 `consume(action: StringName, window: float = 0.0)` 已支持两参数调用。旧 `player.gd` 和新 `PlayerControllerV2.gd` 均使用相同签名 `consume("fire", 0.3)`。

**状态**：**已验证** — 两控制器调用一致。

## 5. ZombieBase 注册

### 5.1 `class_name` 解析

**发现**：`zombie_common.gd` 等派生脚本 `extends ZombieBase`，但 `zombie_base.gd` 的 `class_name ZombieBase` 在加载顺序不当时可能未注册，导致 "Could not resolve class ZombieBase" 解析错误。

**修复**：
- `zombie_base.gd` 变量类型显式声明（`var p: Node` 而非 `var p :=`），修复类型推断错误导致的编译失败。
- `level_runner.gd` 新增 `const ZOMBIE_BASE_SCRIPT := preload("res://scripts/zombies/zombie_base.gd")` 确保基类先于派生类加载。

**状态**：**已修复** — ZombieBase 可被所有派生类解析。

### 5.2 HealthComponent preload 位置

**发现**：`HealthComponent` 原在 `zombie_base.gd` 类级别 `preload()`，可能影响 `class_name` 解析顺序。

**修复**：移至 `_ready()` 中延迟加载。

**状态**：**已修复**。

## 6. `_setup_renderer` 变量定义

### 6.1 `existing` 变量未声明

**发现**：`_setup_renderer()` 引用 `existing` 变量但未声明，导致 "Invalid access to property or key" 或解析错误。

**修复**：添加 `var existing := get_node_or_null("Renderer")`。

**状态**：**已修复**。

## 7. GameFeelBridge HealthComponent 引用

### 7.1 信号订阅与取消

**发现**：`GameFeelBridge.gd` 原通过轮询检测健康变化，未订阅 `HealthComponent.damaged` 信号；`_exit_tree()` 中未清理 HealthComponent 连接。

**修复**：
- 新增 `register_health_component()` / `unregister_health_component()` 方法，订阅 `damaged` 信号。
- `_exit_tree()` 中断开所有 `HealthComponent.damaged` 连接并清空 `_health_components` 字典。
- `_reset_runtime()` 同步清理。
- `StringName(target.get("last_damage_type"))` 改为 `StringName(str(target.get("last_damage_type")))` 修复构造器错误。

**状态**：**已修复** — 信号驱动替代轮询，无信号场景下轮询保留为兜底（`_poll_enabled = false`）。

## 审计结论摘要

| 审计项 | 状态 |
|--------|------|
| 循环依赖 | 已修复 |
| 类型转换 | 已修复 |
| 实例化方式 | 已修复 |
| InputBuffer 签名 | 已验证 |
| ZombieBase 注册 | 已修复 |
| `_setup_renderer` 变量 | 已修复 |
| GameFeelBridge 引用 | 已修复 |

文档路径：`res://docs/architecture_audit.md`
