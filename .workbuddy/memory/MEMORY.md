# LAST BASTION 项目约定

## 工作流（用户明确要求）
- **每次改动完成后必须导出独立的桌面版 EXE 供用户测试**，不要让用户自己找测试方法：
  `D:/DevTools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build/windows/LastBastion.exe`
  然后打包为 `build/LastBastion_vX.Y.Z_win64.zip`
- 改完要 push 到 GitHub（chenmoulaile/last-bastion，git 凭据管理器可用；gh CLI 的 keyring token 已失效，用 `git credential fill` 取 token 调 API）
- 发布 Release：打 tag vX.Y.Z + GitHub API 创建 release + 上传 zip 附件
- 版本号沿用旧方案递增（当前 v3.3.0），不要用 1.x

## 环境
- Godot 4.7.2: D:\DevTools\Godot\（导出模板已装）
- Pillow 的 Python: C:/Users/chenk/AppData/Local/Python/bin/python.exe（3.14）
- 截图测试: `--path . res://tests/screenshot.tscn` → build/screens/；冒烟: res://tests/smoke.tscn

## 美术管线要点
- AI 素材源图在 tools/ai_src/，管线：gen_ai_sprites.py（角色）、gen_ai_s2.py（僵尸/武器）、gen_ai_env.py（背景/地砖/道具）
- SpriteLibrary.zombie_frames 用 tex_width/sprite_size.x 推帧数 → 条带帧宽必须与 .tres sprite_size 严格一致
- 重跑管线前删 tools/__pycache__（曾因旧字节码产出坏帧）
- 角色表/僵尸表在 tools/gen_ai_sprites.py 的 SHEETS / gen_ai_s2.py 的 Z_SHEETS 里登记文件名
