# Critter Quitters Pest Control

A mobile tower defense game built on the open maze-building mechanic pioneered by Desktop Tower Defense. Pests pathfind in real time around whatever the player places — the maze is the strategy.

**Platform:** Mobile (iOS / Android) / Web  
**Engine:** Godot 4 · GDScript · Mobile renderer  
**Status:** Phase 2 complete (combat loop)

---

## Concept

You are an exterminator. Pests invade a property and pathfind toward a food source or exit. Place traps, barriers, and deterrents to reroute and eliminate them before they get there. There is no pre-defined path — pests recalculate their route in real time as the arena changes.

Damage output is a function of path engineering. A trap no enemy walks past is wasted. A barrier with no trap behind it still has value. The player's job is to force pests to take longer routes through more trap coverage.

---

## Gameplay Loop

1. **Run start** — 3 trap types are offered; player picks 2 to start with
2. **Pre-wave countdown** — place traps before pests arrive; trigger early for a Bug Bucks bonus
3. **Wave** — pests enter sequentially, pathfinding in real time; place and sell traps freely during combat
4. **Store** — spend Bug Bucks on trap upgrades, player upgrades, or trap unlocks
5. **Every 10 waves** — boss wave (The Rat leads); the following wave triggers Arena Evolution (random obstacles added)
6. **Run ends** — when the Infestation Level reaches its maximum threshold

---

## Traps

| Trap | Archetype | Notes |
|---|---|---|
| Snap Trap | Basic / single-target | Cheap, fast trigger, low damage |
| Zapper | Long range / high damage | Slow trigger; targets pest farthest along path |
| Fogger | AoE burst | Damages all pests in range circle simultaneously |
| Glue Board | Ice slow / passive | Slows any pest inside its range circle continuously |

All traps occupy a **2×2 cell footprint**. Each can be upgraded up to 5 stars; fully upgraded traps unlock a variation with DoT effects (fire or ice).

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
| Bug Bucks | Earned per kill; spent on traps, upgrades, repositioning, store rerolls |
| Service Fees | Meta currency earned at run end; spent on permanent upgrades in The Truck |

Sell value is 70% of buy price. Infestation Level fills as pests exit; run ends when it maxes out.

---

## Project Structure

```
game/
├── arena/          # Grid, Pathfinder, Arena controller
├── enemies/        # Enemy movement and behavior
├── traps/          # Trap logic (Phase 2+)
├── core/           # GameState autoload
├── ui/             # HUD and menus (Phase 2+)
├── assets/         # Icons and static assets
├── CLAUDE.md       # Code standards and AI collaboration notes
└── project.godot
```

---

## Development Phases

| Phase | Focus | Status |
|---|---|---|
| 1 | Core mechanic prototype — grid, A\*, pathfinding, placeholder enemies | **Complete** |
| 2 | Combat loop — HP, damage, Bug Bucks, Infestation Level, run-over state | **Complete** |
| 3 | ASCII aesthetic — 3D billboards, physical movement, palette | Upcoming |
| 4 | Full game loop — all traps/enemies, waves, store, Arena Evolution | Upcoming |
| 4b | Meta progression — Service Fees, The Truck, upgrade trees | Upcoming |
| 5 | Depth and polish — DoT, store tiers, audio, HUD | Upcoming |
| 6 | Platform — mobile export, web export, performance | Upcoming |

---

## GDD

Full design document: [`../docs/critter_quitters_gdd.md`](../docs/critter_quitters_gdd.md)
