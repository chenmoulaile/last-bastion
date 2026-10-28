# LAST BASTION — Game Feel Layer

Presentation-only feedback layered on top of the existing combat, character and
narrative systems. Nothing in this folder writes damage, health, RPM, spread,
ammunition or any other gameplay value. Every effect is local, toggleable and
safe to disable at runtime.

## Layout

```
res://gamefeel/
├── GameFeelConfig.gd            Autoload: master switch, scales, persistence
├── core/
│   ├── HitStop.gd               Autoload: real-time-scaled hit freeze + input sync
│   ├── ScreenShake.gd           Autoload: trauma² directional camera shake
│   ├── CameraPunch.gd           Autoload: offset kick + zoom pulse
│   ├── FeedbackRouter.gd        event → feedback mapping
│   └── DamageNumbers.gd         pooled floating combat text (40 labels)
├── feedback/
│   ├── HitFlash.gd              additive sprite overlay (never clobbers tint)
│   ├── Knockback.gd             visual sprite displacement only
│   ├── MuzzleFlash.gd           procedural star polygon (12 slots, _draw alloc-free)
│   ├── ImpactParticles.gd       pooled CPUParticles2D (20 emitters)
│   ├── ShellEject.gd            pooled brass shells (30, _draw alloc-free)
│   └── DeathRagdoll.gd          pooled pixel limbs (12, _draw alloc-free)
├── audio/
│   ├── AudioLayerManager.gd     Autoload: low/tail/impact/reload/streak foley
│   ├── PitchRandomizer.gd       ±3 % pitch jitter
│   └── sfx_manifest.gd          declarative event → layer map
├── input/
│   ├── InputBuffer.gd           Autoload: real-time press capture during hitstop
│   └── RecoilController.gd      Autoload: visual muzzle climb + spread
├── ui/
│   ├── HitDirectionIndicator.gd directional damage arcs (4, CanvasLayer 67)
│   ├── LowHealthVignette.gd     <30 % vignette, <15 % heartbeat (layer 64)
│   └── KillStreakPopup.gd       3/5/10 streak popups + chromatic pulse (layer 69)
└── integration/
    ├── GameFeelBridge.gd        Autoload: EventBus subscriptions + polling
    └── feel_smoke_tests.gd/.tscn  headless self-test (72 checks)
```

## Autoload order

`project.godot` loads the layer after the legacy singletons, in this exact order:

1. `GameFeelConfig`
2. `InputBuffer`
3. `CameraPunch`
4. `ScreenShake`
5. `HitStop`
6. `AudioLayerManager`
7. `RecoilController`
8. `GameFeelBridge`

`GameFeelBridge` is last because it instantiates every world/UI module and needs
`GameFeelConfig` and the camera singletons to exist. Compile-time references are
resolved in this order.

## Configuration

`GameFeelConfig` is the single source of truth:

| Property | Range | Default | Meaning |
|---|---|---|---|
| `enabled` | bool | `true` | Master switch. Disabling restores legacy camera/hitstop. |
| `reduced_motion` | bool | `false` | 30 % shake/zoom, no ragdoll throw, no chromatic pulse. |
| `hitstop_scale` | 0–1 | `1.0` | 0 disables freeze completely. |
| `screenshake_scale` | 0–2 | `1.0` | Per-player shake strength. |
| `camera_punch_scale` | 0–1 | `1.0` | Offset/zoom kick strength. |
| `flash_intensity` | 0–1 | `1.0` | Hit/muzzle flash opacity. |
| `particle_density` | 0–1 | `1.0` | 0.5 = half the particles. |
| `damage_number_enabled` | bool | `true` | Independent from the module switch. |
| `audio_scale` | 0–1 | `1.0` | Extra audio-layer fader. |

Per-module switches live in `GameFeelConfig.modules`:
`hitstop`, `screenshake`, `camera_punch`, `hit_flash`, `knockback`,
`muzzle_flash`, `impact_particles`, `shell_eject`, `death_ragdoll`,
`damage_numbers`, `recoil`, `audio_layers`, `hit_direction`, `low_health`,
`kill_streak`.

The settings menu exposes a fourth **手感** tab with the master and
reduced-motion switches, the damage-number / hit-flash switches, four sliders and
a “reset to defaults” button. Settings are persisted through `SaveSystem` under
the `gamefeel` key and mirrored to the project settings
`gamefeel/enabled` and `gamefeel/reduced_motion`.

## Integration contract

* `GameFeelBridge` only **reads** the public `health`, `max_health`, `data`,
  `sprite`, `last_source` and `last_damage_type` fields of enemies. It never
  calls a combat method.
* `EventBus` subscriptions are read-only. `EventBus.hitstop` is temporarily
  rerouted from `GameManager.hitstop` to `HitStop` while the layer is enabled;
  the original connection is restored when the layer is disabled or the bridge
  leaves the tree.
* Enemy damage and deaths are inferred by polling the `zombies` group every
  ~12 ms. This is deliberate: the legacy combat scripts have no damage signal,
  and polling keeps the merge non-invasive. The poll keeps references to nodes
  after they leave the group so a lethal hit is still seen.
* `ScreenShake` disables the legacy `ShakeCamera` processing while enabled and
  restores it verbatim when disabled.
* `RecoilController` writes only `player.weapon_sprite.offset`. Aim, spread and
  bullet direction are untouched.
* The legacy weapon sample is still played by `AudioManager`; `AudioLayerManager`
  adds only the low/tail/impact/reload/streak layers and plays them on
  `SFX_Combat`, `SFX_UI`, `SFX_Ambient`, all routed through the existing `SFX`
  and `Ambience` buses.

## Hitstop and input

`HitStop` changes `Engine.time_scale` for a very short real-time window and
restores it from `Time.get_ticks_usec()`. While frozen, `InputBuffer` records
every press; `consume_after_hitstop()` lets a future controller execute it
immediately after the freeze. Existing player coyote/jump buffering is untouched,
so the layer can never eat an input.

Profiles: normal 0.04 s @ 0.10×, crit 0.08 s @ 0.05×, execution 0.12 s @ 0.0×,
kill 0.06 s @ 0.10×, boss 0.03 s @ 0.30×. A 150 ms per-target cooldown prevents
automatic fire from stuttering.

## Pools and allocation

| System | Pool |
|---|---|
| `MuzzleFlash` | 12 procedural flashes |
| `ImpactParticles` | 20 `CPUParticles2D` |
| `ShellEject` | 30 shells |
| `DeathRagdoll` | 12 limbs |
| `DamageNumbers` | 40 `Label` |
| `HitFlash` | 32 additive overlays |
| `HitDirectionIndicator` | 4 arcs |
| `AudioLayerManager` | 24 voices (12 combat / 6 UI / 6 ambient) |

`MuzzleFlash._draw()`, `ShellEject._draw()` and `DeathRagdoll._draw()` only read
pre-sized packed arrays. No node or array is allocated while drawing.

## Accessibility

`reduced_motion` keeps flashes, damage numbers and audio feedback but scales
screen motion to 30 %, cancels the chromatic-aberration pulse, throws no ragdoll
limbs and reduces the vignette heartbeat. The master switch restores the exact
v1.0 camera and hitstop behaviour. The settings tab and the project settings
mirror both values.

## Tests

```bash
Godot --headless --path . res://gamefeel/integration/feel_smoke_tests.tscn
```

72 checks cover autoload presence, config switches, hitstop time-scale restore,
target freeze release, trauma/peak scaling, camera punch, every pool, reduced
motion, audio buses/streams, input buffering during hitstop, recoil, UI modules,
the settings tab and the bridge diagnostics. The test restores all defaults and
quits with `RESULT: PASS` or `RESULT: FAIL`.

Run the legacy integration suite as well:

```bash
Godot --headless --path . res://tests/smoke.tscn
```

## Rollback

1. Set `gamefeel/enabled=false` in project settings or the settings menu; the
   legacy camera shake and `GameManager.hitstop` resume immediately.
2. To remove the layer completely, delete the eight autoload entries from
   `project.godot`, restore the settings menu from version control and delete
   `res://gamefeel/`. No combat file, scene or resource was modified by this
   layer.

## Performance

The bridge's work per frame is the 12 ms enemy poll plus O(active effects)
updates. With 4 players and 30 enemies the measured bridge poll cost is well
below the 2 ms/frame budget (see the final report for the measured value). All
particles are CPU-based and capped, so the layer behaves predictably on
integrated GPUs; `particle_density` gives an instant low-end fallback.
