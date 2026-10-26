"""Generate every data-driven .tres table for LAST BASTION.

All balance values from the design spec live here, never in gameplay scripts.
Run: py -3 tools/gen_data.py
"""
from __future__ import annotations

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "resources", "data")

SPECIAL_KEYS = ["hunter", "smoker", "boomer", "charger", "spitter", "jockey", "tank", "witch"]


def q(text: str) -> str:
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def sn(text: str) -> str:
    return "&" + q(text)


def val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return q(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if v == int(v):
            return f"{v:.1f}"
        return f"{v:.4f}".rstrip("0").rstrip(".")
    if isinstance(v, list):
        return "[" + ", ".join(val(x) for x in v) + "]"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            parts.append(q(str(k)) + ": " + val(x))
        return "{" + ", ".join(parts) + "}"
    raise TypeError(type(v))


def write_res(path: str, script: str, class_name: str, fields: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = [
        f'[gd_resource type="Resource" script_class="{class_name}" load_steps=2 format=3]',
        "",
        f'[ext_resource type="Script" path="res://scripts/data/{script}" id="1_data"]',
        "",
        "[resource]",
        'script = ExtResource("1_data")',
    ]
    for key, value in fields.items():
        if isinstance(value, str) and value.startswith("__COLOR__"):
            nums = [float(x) for x in value[len("__COLOR__"):].split(",")]
            lines.append(f"{key} = Color({nums[0]:.3f}, {nums[1]:.3f}, {nums[2]:.3f}, {nums[3]:.3f})")
        elif key == "sprite_size":
            lines.append(f"{key} = Vector2i({int(value[0])}, {int(value[1])})")
        elif key == "collision_size":
            lines.append(f"{key} = Vector2({float(value[0]):.1f}, {float(value[1]):.1f})")
        elif isinstance(value, str) and key in ("id", "behavior_id", "category", "fire_mode",
                                              "skill_id", "primary_weapon", "secondary_weapon",
                                              "melee_weapon", "control_kind", "voice_id",
                                              "theme", "default_mode", "music_theme", "soldier_role"):
            lines.append(f"{key} = {sn(value)}")
        else:
            lines.append(f"{key} = {val(value)}")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


# ------------------------------------------------------------------ weapons
WEAPONS = [
    dict(id="m9", display_name="M9 手枪", category="secondary", damage=18, pellets=1,
         rpm=400, mag_size=15, reserve_ammo=-1, reload_time=1.2, spread=1.5,
         effective_range=400, score_mult=1.0, automatic=False, knockback=30,
         sprite="m9", description="永远可靠的副武器，备弹无限。"),
    dict(id="ar15", display_name="AR-15 突击步枪", category="primary", damage=22, pellets=1,
         rpm=600, mag_size=30, reserve_ammo=180, reload_time=1.8, spread=2.0,
         effective_range=550, score_mult=1.2, automatic=True, knockback=45,
         sprite="ar15", description="全能步枪，中距离点射与扫射皆可。"),
    dict(id="smg", display_name="SMG 冲锋枪", category="primary", damage=14, pellets=1,
         rpm=900, mag_size=40, reserve_ammo=240, reload_time=1.5, spread=3.5,
         effective_range=380, score_mult=1.1, automatic=True, knockback=25,
         sprite="smg", description="高射速，适合清理贴脸的普通感染者。"),
    dict(id="shotgun", display_name="泵动霰弹枪", category="primary", damage=6, pellets=12,
         rpm=70, mag_size=8, reserve_ammo=64, reload_time=2.6, spread=8.0,
         effective_range=260, score_mult=1.3, automatic=False, knockback=140,
         sprite="shotgun", description="近距离一枪清场，打断 Hunter 与 Charger 的关键。"),
    dict(id="sniper", display_name="狙击步枪", category="primary", damage=90, pellets=1,
         rpm=90, mag_size=10, reserve_ammo=60, reload_time=2.4, spread=5.0,
         effective_range=900, score_mult=1.5, automatic=False, pierce=2,
         knockback=80, scoped_spread=0.3, sprite="sniper",
         description="开镜 0.3° 散布，贯穿 2 个目标。累计 50 万分解锁。"),
    dict(id="lmg", display_name="LMG 轻机枪", category="primary", damage=18, pellets=1,
         rpm=700, mag_size=100, reserve_ammo=300, reload_time=3.8, spread=4.5,
         effective_range=500, score_mult=1.2, automatic=True, knockback=35,
         sprite="lmg", description="百发弹匣的压制火力。累计 30 万分解锁。"),
    dict(id="axe", display_name="消防斧", category="melee", damage=60, pellets=1,
         rpm=75, mag_size=0, reserve_ammo=0, reload_time=0.0, spread=0.0,
         effective_range=60, score_mult=1.0, automatic=False, knockback=160,
         melee_arc=120, melee_range=60, fire_mode="melee",
         sprite="axe", description="大硬直重击，破门与斩首都靠它。"),
    dict(id="katana", display_name="武士刀", category="melee", damage=45, pellets=1,
         rpm=120, mag_size=0, reserve_ammo=0, reload_time=0.0, spread=0.0,
         effective_range=65, score_mult=1.0, automatic=False, knockback=100,
         melee_arc=100, melee_range=65, fire_mode="melee",
         sprite="katana", description="特勤 Ninja 专属，可快速连斩。"),
    dict(id="chainsaw", display_name="电锯", category="melee", damage=25, pellets=1,
         rpm=600, mag_size=0, reserve_ammo=0, reload_time=0.0, spread=0.0,
         effective_range=55, score_mult=1.4, automatic=True, knockback=70,
         melee_arc=90, melee_range=55, fuel=25.0, fire_mode="chainsaw",
         sprite="chainsaw", description="持续切割，油量 25 秒。L8 隐藏房。"),
    dict(id="grenade", display_name="手雷", category="throwable", damage=150, pellets=1,
         rpm=60, mag_size=0, reserve_ammo=0, reload_time=0.0, spread=0.0,
         effective_range=140, score_mult=1.0, fire_mode="throwable",
         throw_radius=140, fuse_time=3.0, effect_duration=0.0, effect_dps=0.0,
         sprite="grenade", description="3 秒引信，140px 范围 150 伤害。"),
    dict(id="molotov", display_name="燃烧瓶", category="throwable", damage=0, pellets=1,
         rpm=60, mag_size=0, reserve_ammo=0, reload_time=0.0, spread=0.0,
         effective_range=90, score_mult=1.0, fire_mode="throwable",
         throw_radius=90, fuse_time=0.2, effect_duration=8.0, effect_dps=12.0,
         sprite="molotov", description="落点 90px 火区 8 秒，对 CEDA 防护服无效。"),
    dict(id="bile", display_name="胆汁瓶", category="throwable", damage=0, pellets=1,
         rpm=60, mag_size=0, reserve_ammo=0, reload_time=0.0, spread=0.0,
         effective_range=150, score_mult=1.0, fire_mode="throwable",
         throw_radius=150, fuse_time=0.0, effect_duration=15.0, effect_dps=0.0,
         sprite="bile", description="命中点吸引普通感染者 15 秒。"),
]

# --------------------------------------------------------------- characters
CHARACTERS = [
    dict(id="assault", display_name="突击兵", callsign="ASSAULT", max_hp=100, speed=220,
         skill_id="assault_rush", skill_name="突击冲锋", skill_desc="4 秒内换弹速度 ×2、移速 +20%",
         skill_cd=25, primary_weapon="ar15", secondary_weapon="m9", melee_weapon="axe",
         unlock_score=0, portrait="assault", accent=[0.55, 0.78, 0.45, 1],
         description="全能 frontline，AR-15 适配所有距离。"),
    dict(id="medic", display_name="医疗兵", callsign="MEDIC", max_hp=90, speed=215,
         skill_id="field_medic", skill_name="战地医疗", skill_desc="半径 150px 内队友回 35HP、自己回 20",
         skill_cd=30, primary_weapon="smg", secondary_weapon="m9", melee_weapon="axe",
         unlock_score=0, portrait="medic", accent=[0.92, 0.55, 0.55, 1],
         description="团队续航核心，倒地救援速度更快。"),
    dict(id="heavy", display_name="重装兵", callsign="HEAVY", max_hp=150, speed=170,
         skill_id="shield_wall", skill_name="盾墙", skill_desc="正面减伤 70% 持续 5s，近战伤害 ×2",
         skill_cd=28, primary_weapon="lmg", secondary_weapon="m9", melee_weapon="axe",
         unlock_score=0, portrait="heavy", accent=[0.95, 0.75, 0.38, 1],
         description="150 HP 的移动堡垒，慢但站得住。"),
    dict(id="scout", display_name="侦察兵", callsign="SCOUT", max_hp=85, speed=260,
         skill_id="tactical_roll", skill_name="战术翻滚", skill_desc="0.25s 无敌位移 200px",
         skill_cd=12, primary_weapon="shotgun", secondary_weapon="m9", melee_weapon="axe",
         unlock_score=0, portrait="scout", accent=[0.45, 0.82, 0.9, 1],
         description="最快的双腿，滑铲与翻滚让 Hunter 摸不到。"),
    dict(id="ninja", display_name="特勤", callsign="NINJA", max_hp=90, speed=250,
         skill_id="shadow_strike", skill_name="影袭", skill_desc="瞬步至 250px 内最近普感背后并处决",
         skill_cd=18, primary_weapon="katana", secondary_weapon="m9", melee_weapon="katana",
         unlock_score=100000, portrait="ninja", accent=[0.72, 0.55, 0.9, 1],
         description="累计 10 万分解锁。刀比子弹更安静。"),
    dict(id="officer", display_name="军官", callsign="OFFICER", max_hp=100, speed=210,
         skill_id="inspire", skill_name="鼓舞", skill_desc="8 秒内全队射速 +30%、恐惧免疫",
         skill_cd=35, primary_weapon="shotgun", secondary_weapon="m9", melee_weapon="axe",
         unlock_score=500000, portrait="officer", accent=[0.8, 0.8, 0.55, 1],
         description="任意 3 关 S 评价解锁。让全队打得更快。"),
    dict(id="rifleman", display_name="步枪手", callsign="RIFLEMAN", max_hp=80, speed=215,
         skill_id="", skill_name="", skill_desc="", skill_cd=0,
         primary_weapon="ar15", secondary_weapon="m9", melee_weapon="axe",
         unlock_score=0, portrait="assault", accent=[0.55, 0.78, 0.45, 1],
         description="均衡的指挥模式基础兵种。", soldier_role="rifleman"),
    dict(id="gunner", display_name="机枪手", callsign="GUNNER", max_hp=110, speed=150,
         skill_id="", skill_name="", skill_desc="", skill_cd=0,
         primary_weapon="lmg", secondary_weapon="m9", melee_weapon="axe",
         unlock_score=0, portrait="heavy", accent=[0.95, 0.75, 0.38, 1],
         description="HOLD 时优先占据高台与门口。", soldier_role="gunner"),
    dict(id="medic_soldier", display_name="战地医疗兵", callsign="MEDIC", max_hp=80, speed=210,
         skill_id="", skill_name="", skill_desc="", skill_cd=0,
         primary_weapon="smg", secondary_weapon="m9", melee_weapon="axe",
         unlock_score=0, portrait="medic", accent=[0.92, 0.55, 0.55, 1],
         description="自动治疗 80px 内 HP<50 的伤兵。", soldier_role="medic"),
    dict(id="demolisher", display_name="爆破手", callsign="DEMO", max_hp=90, speed=195,
         skill_id="", skill_name="", skill_desc="", skill_cd=0,
         primary_weapon="shotgun", secondary_weapon="m9", melee_weapon="axe",
         unlock_score=0, portrait="officer", accent=[0.85, 0.5, 0.35, 1],
         description="携带 2 枚手雷，尸潮密集点自动投掷。", soldier_role="demolisher"),
]

# ------------------------------------------------------------------ zombies
COMMON = dict(id="common", display_name="普通感染者", max_hp=30, walk_speed_min=120,
              walk_speed_max=180, attack_damage=5, attack_interval=0.5,
              score_value=100, behavior_id="common", sprite_prefix="common_a",
              sprite_size=[24, 32], collision_size=[14, 26], sight_range=260,
              codex_category="common", voice_id="zombie_growl",
              description="15% 个体为奔跑型。会被尖叫、枪声和胆汁吸引。")

UNCOMMONS = [
    dict(id="riot", display_name="防暴僵尸", max_hp=40, walk_speed_min=110, walk_speed_max=150,
         attack_damage=6, score_value=220, front_immune=True, codex_category="uncommon",
         sprite_prefix="riot", tint=[0.85, 0.9, 1.0, 1], voice_id="zombie_growl",
         description="正面免疫枪弹，绕背或近战破防。"),
    dict(id="hazmat", display_name="防护服僵尸", max_hp=45, walk_speed_min=100, walk_speed_max=140,
         attack_damage=6, score_value=220, fire_immune=True, codex_category="uncommon",
         sprite_prefix="hazmat", tint=[1.0, 0.95, 0.65, 1], voice_id="zombie_growl",
         description="CEDA 员工，免疫燃烧瓶与地面火。"),
    dict(id="mud", display_name="泥人", max_hp=25, walk_speed_min=130, walk_speed_max=190,
         attack_damage=5, score_value=240, low_profile=True, codex_category="uncommon",
         sprite_prefix="mud", tint=[0.8, 0.75, 0.65, 1], voice_id="zombie_growl",
         description="低矮轮廓难命中，死亡溅泥遮挡视野。"),
    dict(id="hardhat", display_name="安全帽工", max_hp=50, walk_speed_min=105, walk_speed_max=145,
         attack_damage=7, score_value=240, head_immune=True, codex_category="uncommon",
         sprite_prefix="hardhat", tint=[1.0, 0.9, 0.55, 1], voice_id="zombie_growl",
         description="头盔免疫爆头，打身体。"),
    dict(id="clown", display_name="小丑", max_hp=35, walk_speed_min=120, walk_speed_max=180,
         attack_damage=6, score_value=260, codex_category="uncommon",
         sprite_prefix="clown", tint=[1.0, 0.9, 0.95, 1], voice_id="zombie_growl",
         description="哨音吸引周围普感，死亡触发小尸潮。"),
    dict(id="scavenger", display_name="拾荒者", max_hp=35, walk_speed_min=120, walk_speed_max=180,
         attack_damage=5, score_value=300, codex_category="uncommon",
         sprite_prefix="scavenger", tint=[0.9, 0.85, 0.7, 1], voice_id="zombie_growl",
         description="背包里有补给，击杀掉落。"),
]

SPECIALS = [
    dict(id="hunter", display_name="猎手", max_hp=250, walk_speed_min=200, walk_speed_max=200,
         attack_damage=5, attack_interval=0.5, score_value=800, behavior_id="hunter",
         is_special=True, control_kind="pin", sprite_prefix="hunter", sprite_size=[32, 32],
         collision_size=[18, 28], sight_range=420, pounce_range=380, voice_id="hunter_scream",
         special_weight=1.0, description="蓄力尖啸后抛物线扑击，被扑倒必须由队友打断。"),
    dict(id="smoker", display_name="烟鬼", max_hp=250, walk_speed_min=120, walk_speed_max=120,
         attack_damage=4, attack_interval=0.6, score_value=800, behavior_id="smoker",
         is_special=True, control_kind="tongue", sprite_prefix="smoker", sprite_size=[32, 32],
         collision_size=[18, 28], sight_range=460, voice_id="smoker_cough",
         special_weight=1.0, description="400px 长舌缠绕拖拽，死亡留下遮挡视野的烟雾。"),
    dict(id="boomer", display_name="胖子", max_hp=50, walk_speed_min=100, walk_speed_max=130,
         attack_damage=0, attack_interval=1.0, score_value=600, behavior_id="boomer",
         is_special=True, sprite_prefix="boomer", sprite_size=[36, 36],
         collision_size=[22, 30], sight_range=320, voice_id="boomer_burp",
         special_weight=1.0, description="胆汁会引来尸潮。打爆它也可能泼你一身。"),
    dict(id="charger", display_name="冲锋者", max_hp=500, walk_speed_min=180, walk_speed_max=180,
         attack_damage=10, attack_interval=0.5, score_value=1000, behavior_id="charger",
         is_special=True, control_kind="pound", sprite_prefix="charger", sprite_size=[40, 40],
         collision_size=[24, 34], sight_range=420, voice_id="charger_roar",
         special_weight=1.0, description="火车头式直线冲锋，抓住玩家撞墙锤击。"),
    dict(id="spitter", display_name="呕吐者", max_hp=100, walk_speed_min=150, walk_speed_max=150,
         attack_damage=0, attack_interval=1.0, score_value=600, behavior_id="spitter",
         is_special=True, sprite_prefix="spitter", sprite_size=[32, 32],
         collision_size=[16, 28], sight_range=380, voice_id="spitter_hiss",
         special_weight=1.0, description="酸液池封锁路线，死亡也会留下小酸池。"),
    dict(id="jockey", display_name="骑手", max_hp=300, walk_speed_min=220, walk_speed_max=220,
         attack_damage=4, attack_interval=0.6, score_value=800, behavior_id="jockey",
         is_special=True, control_kind="ride", sprite_prefix="jockey", sprite_size=[32, 32],
         collision_size=[16, 26], sight_range=340, voice_id="jockey_giggle",
         special_weight=1.0, description="跳上玩家头部操控移动方向，笑声是最阴森的预警。"),
    dict(id="tank", display_name="坦克", max_hp=3000, walk_speed_min=180, walk_speed_max=220,
         attack_damage=24, attack_interval=1.4, score_value=30000, behavior_id="tank",
         is_special=True, is_boss=True, head_immune=True, sprite_prefix="tank", sprite_size=[64, 64],
         collision_size=[40, 56], sight_range=900, voice_id="tank_bell",
         special_weight=0.0, description="Boss 级。子弹不击退，必须全队集火或用火。"),
    dict(id="witch", display_name="女巫", max_hp=1000, walk_speed_min=300, walk_speed_max=300,
         attack_damage=150, attack_interval=1.0, score_value=10000, behavior_id="witch",
         is_special=True, is_boss=True, head_immune=True, sprite_prefix="witch", sprite_size=[32, 48],
         collision_size=[16, 36], sight_range=140, voice_id="witch_cry",
         special_weight=0.0, description="坐地哭泣的地雷。惊动后一击倒地，Crowning 可秒杀。"),
]

TINTS = {
    "common_a": [1.0, 1.0, 1.0, 1.0],
    "common_b": [0.92, 0.95, 1.0, 1.0],
    "common_c": [1.0, 0.92, 0.86, 1.0],
    "common_d": [0.9, 1.0, 0.92, 1.0],
}


def color(arr):
    return f"Color({arr[0]:.3f}, {arr[1]:.3f}, {arr[2]:.3f}, {arr[3]:.3f})"


def zombie_fields(z):
    base = dict(
        id=z["id"], display_name=z["display_name"], max_hp=z.get("max_hp", 30),
        walk_speed_min=z.get("walk_speed_min", 120), walk_speed_max=z.get("walk_speed_max", 180),
        attack_damage=z.get("attack_damage", 5), attack_interval=z.get("attack_interval", 0.5),
        score_value=z.get("score_value", 100), behavior_id=z.get("behavior_id", "common"),
        tint="__COLOR__" + ",".join(str(c) for c in z.get("tint", [1, 1, 1, 1])),
        size_scale=1.0, anim_map={}, is_special=z.get("is_special", False),
        is_uncommon=z.get("codex_category") == "uncommon", is_boss=z.get("is_boss", False),
        head_hittable=not z.get("head_immune", False), head_immune=z.get("head_immune", False),
        fire_immune=z.get("fire_immune", False), front_immune=z.get("front_immune", False),
        low_profile=z.get("low_profile", False), control_kind=z.get("control_kind", ""),
        special_weight=z.get("special_weight", 0.0), sprite_prefix=z.get("sprite_prefix", z["id"]),
        sprite_size=z.get("sprite_size", [24, 32]),
        collision_size=z.get("collision_size", [14, 26]),
        death_animation="die", codex_category=z.get("codex_category", "special"),
        description=z.get("description", ""), pounce_range=z.get("pounce_range", 380),
        attack_range=z.get("attack_range", 40), sight_range=z.get("sight_range", 260),
        voice_id=z.get("voice_id", "zombie_growl"),
    )
    return base


# ------------------------------------------------------------------- levels
def ev(at, type_, **kw):
    d = {"at": at, "type": type_}
    d.update(kw)
    return d


def level_fields(l):
    return dict(
        id=l["id"], chapter=l["chapter"], chapter_name=l["chapter_name"], title=l["title"],
        subtitle=l["subtitle"], theme=l["theme"], length=l["length"],
        default_mode=l["default_mode"], difficulty_scale=l.get("difficulty_scale", 1.0),
        base_score=100000, par_score=l["par_score"], time_target=l["time_target"],
        special_density=l["special_density"], special_weights=l["special_weights"],
        uncommon_weights=l.get("uncommon_weights", {}), bosses=l.get("bosses", []),
        events=l.get("events", []), checkpoint_at=l.get("checkpoint_at", 0.5),
        hidden_room_at=l.get("hidden_room_at", 0.35), dark=l.get("dark", False),
        rain=l.get("rain", False), extraction=l.get("extraction", "safehouse"),
        extraction_defense=l.get("extraction_defense", 0.0),
        tutorial_tips=l.get("tutorial_tips", []), briefing=l.get("briefing", ""),
        new_threat=l.get("new_threat", ""), player_weapons=l.get("player_weapons", []),
        commander_squad=l.get("commander_squad", []), ammo_crates=l.get("ammo_crates", 3),
        medkits=l.get("medkits", 2), unlocks_weapon=l.get("unlocks_weapon", ""),
        music_theme=l.get("music_theme", l["theme"]), escort_vehicle=l.get("escort_vehicle", False),
    )


ALL_SPECIALS = {k: 0.125 for k in SPECIAL_KEYS}

LEVELS = [
    dict(id="l01", chapter=1, chapter_name="郊区突围", title="街道突破口",
         subtitle="天亮之前，穿过街区。", theme="suburb", length=9000, default_mode="SQUAD",
         par_score=160000, time_target=240, special_density=0.0, special_weights={},
         bosses=[], extraction="safehouse",
         briefing="小队从郊区安全屋出发。穿过街道，抵达下一个撤离点。",
         new_threat="普通感染者 · 尸潮 · 惊动链",
         tutorial_tips=["A/D 移动，空格跳跃，S 蹲下。跑动中按 S 滑铲。",
                        "鼠标瞄准，左键/J 开火，F 近战推开贴脸的感染者。",
                        "面对门按 E 踹开。门后的感染者会短暂硬直。",
                        "W/S + 开火可以朝斜上/斜下射击。"],
         events=[ev(0.18, "tip", text="一只感染者发现了你。枪声会引来更多。"),
                 ev(0.36, "horde", count=14, alarm=False),
                 ev(0.58, "horde", count=18, alarm=False),
                 ev(0.78, "special", kind="hunter", optional=True)],
         hidden_room_at=0.42, ammo_crates=3, medkits=2, rain=True),
    dict(id="l02", chapter=1, chapter_name="郊区突围", title="补给超市",
         subtitle="货架之间，没有安全通道。", theme="suburb", length=9500, default_mode="SQUAD",
         par_score=175000, time_target=260, special_density=0.85,
         special_weights={"hunter": 0.45, "boomer": 0.55},
         uncommon_weights={"riot": 0.15}, bosses=[], extraction="safehouse",
         briefing="收集三处补给，在结账区顶住双波尸潮。消防斧在仓库。",
         new_threat="Boomer 胖子 · Hunter 猎手 · 消防斧",
         tutorial_tips=["Boomer 被击杀也会爆炸泼胆汁，远距离解决。",
                        "听到尖啸立刻面向声源；Hunter 扑空会撞墙硬直。",
                        "拾取消防斧后按 Q 切换到近战。"],
         events=[ev(0.2, "supply", kind="medkit"), ev(0.3, "horde", count=16),
                 ev(0.45, "special", kind="boomer"), ev(0.55, "supply", kind="ammo"),
                 ev(0.62, "defense", seconds=45, waves=2, count=16),
                 ev(0.7, "special", kind="hunter")],
         player_weapons=["axe"], hidden_room_at=0.35, ammo_crates=4, medkits=3),
    dict(id="l03", chapter=1, chapter_name="郊区突围", title="加油站",
         subtitle="别让油桶在你身边爆炸。", theme="suburb", length=10000, default_mode="SQUAD",
         par_score=190000, time_target=280, special_density=1.0,
         special_weights={"smoker": 0.35, "hunter": 0.35, "boomer": 0.3},
         uncommon_weights={"riot": 0.35}, bosses=["tank"], extraction="safehouse",
         briefing="穿过加油站，利用油桶清场。断桥处有 Tank 挡路。",
         new_threat="Smoker 烟鬼 · 防暴僵尸 · TANK",
         tutorial_tips=["烟鬼的舌头会把你拖走。队友必须打断或击杀它。",
                        "防暴僵尸正面免疫子弹，绕背或近战。",
                        "Tank 子弹打不退。用燃烧瓶、油桶和全队火力。"],
         events=[ev(0.2, "special", kind="smoker"), ev(0.38, "horde", count=20, alarm=True),
                 ev(0.5, "supply", kind="ammo"), ev(0.62, "boss", kind="tank"),
                 ev(0.72, "special", kind="hunter")],
         hidden_room_at=0.55, ammo_crates=4, medkits=3, rain=True),
    dict(id="l04", chapter=2, chapter_name="城市废墟", title="写字楼",
         subtitle="向上，再向上。电梯井里全是回声。", theme="city", length=10000,
         default_mode="SQUAD", par_score=205000, time_target=290, special_density=1.15,
         special_weights={"spitter": 0.3, "hunter": 0.3, "smoker": 0.4},
         uncommon_weights={"hazmat": 0.4}, bosses=[], extraction="safehouse",
         briefing="穿过写字楼大厅，启动电梯，在警报尸潮中抵达楼顶。",
         new_threat="Spitter 呕吐者 · CEDA 防护服 · 楼层警报",
         tutorial_tips=["酸液池会封锁路线，别站在里面换弹。",
                        "CEDA 防护服免疫火焰，用子弹解决。",
                        "电梯开关会触发警报尸潮。提前占据门口。"],
         events=[ev(0.18, "elevator"), ev(0.28, "horde", count=18, alarm=True),
                 ev(0.42, "special", kind="spitter"), ev(0.55, "defense", seconds=40, waves=2, count=18),
                 ev(0.66, "horde", count=20, alarm=True), ev(0.8, "special", kind="smoker")],
         hidden_room_at=0.45, ammo_crates=4, medkits=3),
    dict(id="l05", chapter=2, chapter_name="城市废墟", title="地铁隧道",
         subtitle="关掉手电，听她的哭声。", theme="subway", length=10500,
         default_mode="SQUAD", par_score=215000, time_target=310, special_density=1.2,
         special_weights={"hunter": 0.4, "smoker": 0.35, "spitter": 0.25},
         uncommon_weights={"mud": 0.5, "hazmat": 0.15}, bosses=["witch", "witch"],
         extraction="safehouse", dark=True,
         briefing="地铁隧道停电。两只 Witch 坐在路线上。不要惊动她们。",
         new_threat="WITCH ×2 · 泥人 · 黑暗与手电",
         tutorial_tips=["蹲行并关闭手电可以安全绕过 Witch。",
                        "惊动 Witch 后她会一击将你击倒。跑，或者 Crowning。",
                        "泥人轮廓低矮，瞄准身体中线。"],
         events=[ev(0.22, "witch", x_offset=300), ev(0.5, "witch", x_offset=600),
                 ev(0.35, "special", kind="hunter"), ev(0.65, "horde", count=18),
                 ev(0.78, "special", kind="spitter")],
         player_weapons=["sniper"], hidden_room_at=0.58, ammo_crates=4, medkits=3),
    dict(id="l06", chapter=2, chapter_name="城市废墟", title="天台撤离",
         subtitle="直升机不会等太久。", theme="city", length=9500, default_mode="SQUAD",
         par_score=220000, time_target=300, special_density=1.25,
         special_weights={"jockey": 0.3, "boomer": 0.3, "hunter": 0.4},
         uncommon_weights={"clown": 0.4, "hazmat": 0.2}, bosses=[], extraction="helicopter",
         extraction_defense=90.0, rain=True,
         briefing="抵达天台，守住直升机坪 90 秒。不要留下任何人。",
         new_threat="Jockey 骑手 · 小丑 · 90 秒撤离防守",
         tutorial_tips=["Jockey 会骑上你的头操控方向。队友射击时小心误伤。",
                        "小丑的哨音会吸引周围感染者，死亡时还会触发小尸潮。",
                        "撤离倒计时开始后，任意存活成员进入撤离区即可结算。"],
         events=[ev(0.25, "special", kind="jockey"), ev(0.4, "horde", count=20),
                 ev(0.55, "defense", seconds=35, waves=2, count=18),
                 ev(0.7, "special", kind="boomer")],
         hidden_room_at=0.6, ammo_crates=5, medkits=4),
    dict(id="l07", chapter=3, chapter_name="军事基地", title="检查站",
         subtitle="收拢残部。兵是消耗品。", theme="military", length=9000,
         default_mode="COMMAND", par_score=230000, time_target=300, special_density=1.3,
         special_weights={"hunter": 0.25, "smoker": 0.25, "boomer": 0.25, "spitter": 0.25},
         uncommon_weights={"hardhat": 0.3, "riot": 0.2}, bosses=[], extraction="safehouse",
         briefing="指挥 6 名士兵穿过检查站。用 1-4 下达命令，守住两波进攻。",
         new_threat="指挥模式 · 四道指令 · 援军房",
         tutorial_tips=["1 跟随 / 2 推进 / 3 防守 / 4 集火。",
                        "HOLD 会让机枪手寻找高台与门口。",
                        "士兵阵亡不会复活；检查站的援军房可以补兵。"],
         commander_squad=["rifleman", "rifleman", "rifleman", "gunner", "medic", "demolisher"],
         events=[ev(0.2, "tip", text="指挥模式：按 1-4 下达命令。"),
                 ev(0.32, "defense", seconds=45, waves=2, count=20),
                 ev(0.55, "horde", count=22), ev(0.68, "defense", seconds=45, waves=2, count=20),
                 ev(0.82, "special", kind="smoker")],
         hidden_room_at=0.44, ammo_crates=5, medkits=3),
    dict(id="l08", chapter=3, chapter_name="军事基地", title="仓库清剿",
         subtitle="找到电锯。然后让它们进来。", theme="military", length=10500,
         default_mode="COMMAND", par_score=240000, time_target=320, special_density=1.35,
         special_weights={"charger": 0.4, "hunter": 0.2, "smoker": 0.2, "spitter": 0.2},
         uncommon_weights={"hardhat": 0.5, "riot": 0.2}, bosses=["charger", "charger"],
         extraction="safehouse", escort_vehicle=False,
         briefing="仓库里有两名 Charger。隐藏房里有电锯，值得冒险。",
         new_threat="Charger ×2 · 安全帽工 · 隐藏电锯",
         tutorial_tips=["Charger 冲锋时侧向滑铲可以躲过。",
                        "冲锋中单次受到 30+ 伤害会踉跄。",
                        "电锯持续切割，但油量只有 25 秒。"],
         commander_squad=["rifleman", "rifleman", "rifleman", "gunner", "gunner", "medic", "demolisher"],
         events=[ev(0.25, "horde", count=22), ev(0.42, "boss", kind="charger"),
                 ev(0.58, "defense", seconds=40, waves=2, count=22),
                 ev(0.72, "boss", kind="charger"), ev(0.85, "horde", count=24)],
         player_weapons=["chainsaw"], hidden_room_at=0.52, ammo_crates=6, medkits=4),
    dict(id="l09", chapter=3, chapter_name="军事基地", title="装甲突围",
         subtitle="跟着装甲车走。别掉队。", theme="military", length=11000,
         default_mode="COMMAND", par_score=250000, time_target=340, special_density=1.4,
         special_weights=ALL_SPECIALS,
         uncommon_weights={"scavenger": 0.2, "hardhat": 0.25, "riot": 0.25},
         bosses=[], extraction="apc", escort_vehicle=True,
         briefing="护送装甲车穿过基地。士兵死亡后只能在检查站补兵。",
         new_threat="全特感 · 装甲车移动掩体 · 沿途补兵",
         tutorial_tips=["装甲车会为你挡住正面火力，但它不会等你。",
                        "按 3 让士兵就地防守，按 1 让他们跟上。",
                        "检查站援军房补满编制，但数量有限。"],
         commander_squad=["rifleman", "rifleman", "rifleman", "rifleman", "gunner", "gunner", "medic", "demolisher"],
         events=[ev(0.2, "horde", count=20), ev(0.35, "special", kind="charger"),
                 ev(0.5, "horde", count=24, alarm=True), ev(0.62, "special", kind="jockey"),
                 ev(0.75, "horde", count=26), ev(0.86, "special", kind="tank", optional=True)],
         hidden_room_at=0.47, ammo_crates=6, medkits=4, rain=True),
    dict(id="l10", chapter=4, chapter_name="最后防线", title="大桥决战",
         subtitle="桥的两端都是死路。", theme="bridge", length=11000,
         default_mode="FREE", par_score=270000, time_target=360, special_density=1.5,
         special_weights=ALL_SPECIALS,
         uncommon_weights={"riot": 0.2, "hazmat": 0.2, "mud": 0.15, "hardhat": 0.15,
                           "clown": 0.15, "scavenger": 0.15},
         bosses=["tank", "tank"], extraction="safehouse", rain=True,
         briefing="大桥上出现两只 Tank。利用车辆与油桶，别被逼到桥边。",
         new_threat="双 TANK · 全图鉴 · 自由模式",
         tutorial_tips=["两只 Tank 会分别锁定不同目标。",
                        "燃烧瓶对 Tank 造成 1.5 倍伤害。",
                        "桥面掩体可以挡住投石。"],
         events=[ev(0.2, "horde", count=22), ev(0.38, "special", kind="smoker"),
                 ev(0.52, "boss", kind="tank", count=2), ev(0.7, "horde", count=26, alarm=True),
                 ev(0.84, "special", kind="jockey")],
         hidden_room_at=0.6, ammo_crates=6, medkits=5),
    dict(id="l11", chapter=4, chapter_name="最后防线", title="最后防线",
         subtitle="守住这里。直升机是最后的答案。", theme="bridge", length=12000,
         default_mode="FREE", par_score=300000, time_target=420, special_density=1.6,
         special_weights=ALL_SPECIALS,
         uncommon_weights={"riot": 0.2, "hazmat": 0.2, "mud": 0.15, "hardhat": 0.15,
                           "clown": 0.15, "scavenger": 0.15},
         bosses=["tank", "tank"], extraction="helicopter", extraction_defense=120.0,
         rain=True,
         briefing="三道尸潮，两只 Tank，然后登机。最后防线不允许后退。",
         new_threat="3 波尸潮 · 双 TANK · 直升机终战",
         tutorial_tips=["撤离倒计时开始后，任何存活成员进入撤离区即可结算。",
                        "优先击杀 Boomer 与 Smoker，别让尸潮叠加。",
                        "保留燃烧瓶给 Tank。"],
         events=[ev(0.2, "defense", seconds=40, waves=2, count=22),
                 ev(0.42, "horde", count=28, alarm=True),
                 ev(0.58, "boss", kind="tank"),
                 ev(0.7, "defense", seconds=45, waves=2, count=24),
                 ev(0.82, "boss", kind="tank", count=2)],
         hidden_room_at=0.5, ammo_crates=7, medkits=5),
]


def main():
    for w in WEAPONS:
        write_res(os.path.join(OUT, "weapons", f"weapon_{w['id']}.tres"),
                  "weapon_data.gd", "WeaponData", dict(w))

    for c in CHARACTERS:
        fields = dict(c)
        fields["accent"] = "__COLOR__" + ",".join(str(x) for x in c["accent"])
        fields.setdefault("soldier_role", "")
        write_res(os.path.join(OUT, "characters", f"character_{c['id']}.tres"),
                  "character_data.gd", "CharacterData", fields)

    write_res(os.path.join(OUT, "zombies", "zombie_common.tres"),
              "zombie_data.gd", "ZombieData", zombie_fields(COMMON))
    for z in UNCOMMONS + SPECIALS:
        fields = zombie_fields(z)
        write_res(os.path.join(OUT, "zombies", f"zombie_{z['id']}.tres"),
                  "zombie_data.gd", "ZombieData", fields)

    for l in LEVELS:
        write_res(os.path.join(OUT, "levels", f"{l['id']}.tres"),
                  "level_data.gd", "LevelData", level_fields(l))

    print(f"generated {len(WEAPONS)} weapons, {len(CHARACTERS)} characters, "
          f"{1 + len(UNCOMMONS) + len(SPECIALS)} zombies, {len(LEVELS)} levels")


if __name__ == "__main__":
    main()
