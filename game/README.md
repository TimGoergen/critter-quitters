# Critter Quitters Pest Control

A mobile tower defense game built on the open maze-building mechanic pioneered by Desktop Tower Defense. Pests pathfind in real time around whatever the player places — the maze is the strategy.

**Platform:** Mobile (iOS / Android) / Web  
**Engine:** Godot 4 · GDScript · Mobile renderer  
**Status:** Phase 5 complete (Mobile UI Rework) · Phase 6 (Sound) in progress

---

## Concept

You are an exterminator. Pests invade a property and pathfind toward a food source or exit. Place traps, barriers, and deterrents to reroute and eliminate them before they get there. There is no pre-defined path — pests recalculate their route in real time as the arena changes.

Damage output is a function of path engineering. A trap no enemy walks past is wasted. A barrier with no trap behind it still has value. The player's job is to force pests to take longer routes through more trap coverage.

---

## Gameplay Loop

1. **Run start** — 3 trap types are offered; player picks 2 to start with
2. **Pre-wave countdown** — place traps before pests arrive; trigger early for a Bug Bucks bonus
3. **Wave** — pests enter sequentially, pathfinding in real time; place, upgrade, and sell traps freely at any time
4. **Direct trap upgrades** — tap any placed trap to open its upgrade panel; spend Bug Bucks to upgrade Damage, Range, or Fire Rate independently
5. **Every 10 waves** — boss wave (The Rat leads); the following wave triggers Arena Evolution (random obstacles added)
6. **Run ends** — when the Infestation Level reaches its maximum threshold

---

## Traps

| Trap | Archetype | Notes |
|---|---|---|
| Snap Trap | Basic / single-target | Cheap, fast trigger, low damage; targets nearest pest |
| Zapper | Long range / high damage | Slow trigger; targets pest farthest along path |
| Fogger | AoE burst | Damages pests outward from centre — closer pests hit first |
| Glue Board | Ice slow / passive | Continuously slows any pest inside its range circle |

All traps occupy a **2×2 cell footprint**. Each has three independently upgradeable stats (Damage, Range, Fire Rate), each up to 3 levels, displayed as ★★★ stars. Fire Rate is not upgradeable on the Glue Board (passive). A full 3/3/3 upgrade awards a one-time +10% bonus to all stats.

---

## Enemies

| Pest | Archetype | Tier |
|---|---|---|
| Ant | Standard — fast, numerous | 1 |
| Cricket | Fast / erratic | 2 |
| Beetle | Mid-tier tank | 3 |
| Cockroach | High-tier resilient | 4 |
| Rat | Boss — massive HP, leads boss waves | Boss |

---

## Arena

- **30×30 grid**, single persistent arena per run (no resets between waves)
- One entrance and one exit, assigned to separate walls at run start
- At least one valid path must always exist — placements that block all routes are rejected
- **Arena Evolution** introduces environmental obstacles over the course of a run

**v1 Arena Pool:** Kitchen · Backyard · Basement · Attic

---

## Economy

| Resource | Description |
|---|---|
| Bug Bucks | Earned per kill; spent on trap placement, upgrades, repositioning |
| Service Fees | Meta currency earned at run end; spent on permanent upgrades in The Truck |

Sell value is 70% of buy price. Infestation Level fills as pests exit; run ends when it maxes out.

---

## Project Structure

```
game/
├── arena/          # Grid, Pathfinder, Arena controller
├── enemies/        # Enemy movement and behavior
├── traps/          # Trap logic
├── core/           # GameState and AudioManager autoloads
├── ui/             # HUD, start screen, upgrade panels
├── assets/         # Icons, audio, and static assets
├── CLAUDE.md       # Code standards and AI collaboration notes
└── project.godot
```

---

## Development Phases

| Phase | Focus | Status |
|---|---|---|
| 1 | Core mechanic — grid, A\*, pathfinding, placeholder enemies | **Complete** |
| 2 | Combat loop — HP, damage, Bug Bucks, Infestation Level, run-over state | **Complete** |
| 3 | Visual style — Sprite3D illustrated enemies, hit/death reactions, Snap Trap procedural mesh | **Complete** |
| 4 | Build & deploy pipeline — GitHub Actions CI, Windows installer, signed Android APK, Firebase distribution | **Complete** |
| 5 | Mobile UI rework — landscape layout, touch input, two-level zoom, enemy follow, upgrade panel | **Complete** |
| 6 | Sound — AudioManager, audio buses, trap fire SFX; enemy/UI/music audio pending | **In Progress** |
| 7 | Sprite art migration — illustrated Sprite3D for all 5 enemies and 4 traps; procedural background | Upcoming |
| 8 | Full game loop — all trap/enemy types, wave composition, starting selection, Arena Evolution, save files | Upcoming |
| 8b | Meta progression — Service Fees, The Truck hub, equipment and business upgrade trees | Upcoming |
| 9 | Depth & polish — DoT system, store tiers, full upgrade trees, HUD polish | Upcoming |
| 10 | Platform — final mobile/web export, performance optimisation, Play Store submission | Upcoming |

---

## GDD

Full design document: [`../docs/critter_quitters_gdd.md`](../docs/critter_quitters_gdd.md)
