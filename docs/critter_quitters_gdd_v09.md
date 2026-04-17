# **Critter Quitters Pest Control — Game Design Document**

**Version:** Draft v0.9 **Status:** Concept / Pre-production **Platform:** Mobile (iOS / Android) / Web **Art Style:** ASCII / minimalist **Reference:** Desktop Tower Defense

---

## **Changelog**

| Version | Changes |
| :---- | :---- |
| v0.1 | Initial draft |
| v0.2 | Title confirmed: Bullet Alley |
| v0.3 | Currency confirmed: Shells |
| v0.4 | Monetization confirmed: premium. Entry/exit corrected: left+top entry, right+bottom exit. Platform: mobile+web. Director's Cut removed. Levels: auto-generated incremental difficulty. Blocking terrain added. |
| v0.5 | Roster finalised: 4 towers, 5 enemies. Build phase replaced with pre-wave countdown. Between-wave upgrade store added. ASCII aesthetic confirmed. Game structure defined: endless levels, high score, per-level arena reset. DoT system: fire and ice. Unit interaction rules defined. |
| v0.6 | Full theme overhaul. Game renamed to Critter Quitters Pest Control. Theme changed from 80s action to pest exterminator. Currency renamed from Shells to Bounties. Tower roster rethemed (names TBD). Enemy roster replaced with pest archetypes. One-liner/kill streak system removed. Arena recontextualized as rooms and locations. Blocking terrain candidates updated. Property HP introduced as arena health framing. Future pass mechanics section added. |
| v0.7 | Game structure overhaul. Single persistent arena replaces multi-level structure. Currency renamed to Bug Bucks. Property HP replaced by Infestation Level. Arena Evolution introduced (every 10 waves). Wave complexity model defined. Boss wave structure defined. Single entrance / single exit on separate walls replaces dual entrance model. Starting trap selection added (3 offered, pick 2). Store fully redesigned: 3 tiered upgrade options, reroll mechanic, trap unlocks. Infestation healing added as store option and trap modifier. |
| v0.8 | Tech stack defined. Development path defined across 6 phases. Save file system added to Phase 4. |
| v0.9 | Boss wave frequency confirmed: every 10 waves. Arena Evolution timing updated: occurs in the wave immediately following each boss wave. Store reroll cost confirmed: progressive linear, resets each visit (e.g. 5, 10, 15, 20...); exact base amount and increment TBD via playtesting. |
| v0.10 | Meta-progression system added: Service Fees currency, The Truck hub, equipment and business upgrades, stats screen. Arena pool defined: 4 residential arenas (Kitchen, Backyard, Basement, Attic). All open design questions resolved or deferred. GDScript code standards documented in CLAUDE.md. |

---

## **Table of Contents**

1. Overview & Premise
2. Core Loop
3. Arena & Layout
4. Tower Roster
5. Enemy Roster
6. Mechanics
6a. Blocking Terrain & Arena Evolution
7. Progression & Economy
8. Meta Progression & The Truck
9. Aesthetic Direction
10. Mobile UX Considerations
11. Open Questions
12. Future Pass
13. Tech Stack
14. Development Path

---

## **1. Overview & Premise**

Critter Quitters Pest Control is a mobile tower defense game built on the open maze-building mechanic pioneered by Desktop Tower Defense (2007). The player controls no pre-defined path — instead, pest units enter an open arena and pathfind in real time around whatever the player places. The maze is the strategy.

You are an exterminator. Pests are invading a property and heading for a food source or exit point. Your job is to place traps, barriers, and deterrents to reroute and eliminate them before they get there. Pests naturally pathfind around obstacles — building maze-like trap corridors feels completely believable.

The core strategic insight: damage output is a function of path engineering. A trap that no enemy walks past is wasted. A barrier with no trap behind it still has value. The player's job is to force pests to take longer routes through more trap coverage zones.

The tone is functional with a light comic edge: a local pest control company doing a job, and the job keeps getting worse.

| Attribute | Value |
| :---- | :---- |
| Genre | Tower defense / maze builder |
| Target audience | Males 35–55, TD veterans |
| Session length | 10–25 min per run |
| Platform | Mobile (iOS / Android) / Web |
| Monetization | Premium (pay upfront, all gameplay included) |

---

## **2. Core Loop**

**Run start — trap selection**

Before the first wave, the player is presented with 3 randomly selected trap types and must choose 2. The chosen traps are available for placement immediately. The remaining traps may be unlocked later through the store.

**Each wave follows this sequence:**

1. Wave announced — player sees incoming pest type, count, and complexity

2. Pre-wave countdown — a timer counts down before the wave begins. The player must start placing traps immediately. The current pest path is visualised on the arena. The player may trigger the wave early to receive a Bug Bucks bonus (amount TBD).

3. Wave — pests enter sequentially from the single entrance and pathfind toward the exit. Pests are grouped by type; group size and variety scale with wave complexity. The player may continue to place, upgrade, or sell traps during the wave as Bug Bucks are earned.

4. Each pest that is killed before reaching the exit awards Bug Bucks based on pest type, scaled by wave number. Each pest that reaches the exit increases the Infestation Level by an amount based on pest type.

5. Wave ends — the player visits the store before the next wave begins.

6. Every 10 waves is a boss wave. The wave immediately following each boss wave triggers Arena Evolution — see Section 6a.

**Infestation Level** fills as pests reach the exit. When it reaches its maximum threshold, the infestation is uncontrollable and the run ends. The Infestation Level can be reduced through store upgrades and certain trap modifiers — see Section 7.

**Run end** — the player's high score is recorded based on total pests eliminated and highest wave reached.

**Unit interaction rules:** Pests cannot affect player traps in any way. Each trap defines only its own trigger rate, damage, and range — traps do not buff or debuff other traps. Traps may apply fire or ice DoT effects directly to pests they hit.

**Range:** Each trap has a circular range field. A pest becomes exposed to a trap as soon as it enters that circle. The range circle is always displayed around a selected placed trap.

**Targeting:** Each trap targets the exposed pest (within its range circle) that is farthest along the current path toward the exit — prioritising the most immediate threat.

**Projectiles:** Traps fire projectiles or release effects that travel visually toward their target. Damage is applied instantly on firing — projectile travel is cosmetic.

**Placement during combat:** Trap placement is not locked to the pre-wave phase. The player may place, upgrade, or sell traps at any point during a wave as Bug Bucks become available. Path visualisation updates in real time. All pests currently on the arena immediately recalculate their path when the layout changes.

---

## **3. Arena & Layout**

The arena is a single persistent space that endures for the entire run. It does not reset between waves. The player's trap layout accumulates over time — each wave is played on the same arena the player has been building.

The arena is flat, open, and grid-based to support touch placement on mobile. Grid cells resolve at a size that allows comfortable finger-tap accuracy on phones.

Each run has one entrance and one exit, assigned to separate walls at run start. They are not necessarily on opposite walls. Enemies always enter from the entrance and always target the exit.

| Attribute | Value |
| :---- | :---- |
| Entry points | One — assigned to a wall at run start |
| Exit points | One — assigned to a different wall at run start |
| Grid size | 14×14 (fixed) |
| Pathfinding | A\* real-time |
| Arena selection | Random from pool at run start |
| Starting obstacles | None — arena is empty at run start |

**Arena pool**

The game includes a pool of arenas, each with a distinct location theme, color palette, and obstacle name. One arena is selected randomly at the start of each run. All arenas share the same grid size and rules; they differ only in aesthetics and obstacle naming.

Obstacles are never present at run start. They are introduced exclusively through Arena Evolution, beginning at wave 11. See Section 6a.

All v1 arenas are set within a single residential home. This grounds the pest control theme and provides a cohesive setting across runs.

**v1 Arena Pool**

| Arena | Pest Destination | Obstacle Name | Palette |
| :---- | :---- | :---- | :---- |
| Kitchen | Food source | Appliances | Warm cream / yellow |
| Backyard | Foraging / outdoor access | Yard Clutter | Greens / dirt brown |
| Basement | Shelter / nesting | Storage | Cool dark grey |
| Attic | Shelter / nesting | Clutter | Dusty warm brown |

The arena evolves over the course of the run. See Section 6a.

---

## **4. Tower Roster (Initial)**

Each trap is a tool in an exterminator's kit. Names below are working titles — final names TBD.

**Availability:** Not all traps are available at run start. The player selects 2 of 3 randomly offered traps before wave 1. Remaining traps may be unlocked through the store.

**Upgrade system:** Each trap can be upgraded up to 5 times, tracked by a star rating (1–5). Each upgrade improves a core metric (damage, trigger rate, range, or other stats). After 5 upgrades, a variation becomes available — evolving the trap into a more advanced unit with expanded abilities.

Fully evolved units can inflict damage-over-time (DoT) effects:

| DoT Type | Behavior |
| :---- | :---- |
| Fire | Deals repeated damage ticks for a duration after the hit |
| Ice | Reduces pest movement speed for a duration after the hit |

**DoT rules:**
- Effects do not stack — a subsequent hit of the same type refreshes the duration
- Effects do not spread; they apply only to the pest directly hit
- Fire and Ice can coexist on the same pest simultaneously

**Infestation modifier:** Certain traps or trap upgrades carry an infestation-reducing modifier. Kills made by these traps reduce the Infestation Level by a small amount per kill — a lifesteal-style mechanic that rewards strategic placement and active killing.

**Evolved unit visuals:** As a trap evolves, its ASCII character representation grows more prominent — shifting from lowercase to uppercase, increasing in visual weight, or using a bolder character variant.

**Footprint:** Most traps occupy a single 1×1 cell. Some traps occupy 3 or more contiguous cells in irregular shapes (L-shapes, T-shapes, etc.). Footprints are fixed and do not rotate — all traps operate in a full 360-degree arc.

### **The Snap Trap**

**Archetype:** Basic / single-target

Cheap, reliable. Small range circle, fast trigger rate, low damage. Fires at the nearest exposed pest. The expendable backbone of any build.

### **The Zapper**

**Archetype:** Long range / high damage

Large range circle, very slow trigger rate, high damage. Fires an electrical bolt at the exposed pest farthest along the path. Its wide range circle allows it to reach pests deep in corridors without being placed near them. Eliminates standard pests outright late in upgrade path.

### **The Fogger**

**Archetype:** Area of effect / high damage

Medium range circle, slow trigger rate, high damage per burst. When it fires, the fog cloud fills its entire range circle — damaging all exposed pests simultaneously. The range circle defines both targeting and AoE coverage. Ideal for chokepoints and tightly packed groups.

### **The Glue Board**

**Archetype:** Ice / area slow

Medium range circle, passive and continuous. Any pest inside the circle has the ice slow applied for as long as it remains in range. Low cost, low footprint.

---

## **5. Enemy Roster (Initial)**

| Name | Archetype | Behavior | Tier |
| :---- | :---- | :---- | :---- |
| The Ant | Standard | Low HP, fast, appears in large numbers. No special mechanics. The most common pest. | 1 |
| The Cricket | Fast / erratic | Low HP, very fast. Punishes gaps in coverage. | 2 |
| The Beetle | Mid-tier tank | High HP, slow movement, moderate infestation damage on exit. Uncommon within waves. | 3 |
| The Cockroach | High-tier resilient | Very high HP, very slow movement, high infestation damage on exit. Rare. | 4 |
| The Rat | Boss | Massive HP, slowest movement, highest infestation damage on exit. Leads boss waves. One per wave maximum. | Boss |

**Exit damage** increases each wave. Wave 1 is balanced so that if all pests reached the exit uncontested, they would fill the Infestation Level to twice its threshold — the player must stop at least half to survive.

---

## **6. Mechanics**

**Repositioning cost** — Moving a placed trap costs a small Bug Bucks fee, adding weight to placement decisions without fully locking the player in.

**Selling** — Traps may be sold at any time, including during combat. Selling returns 70% of the trap's buy price. Pests on the arena reroute immediately when a trap is removed.

**Blocking terrain** — Environmental obstacles that act as physical barriers. Cannot be placed on by traps; cannot be crossed by pests. Purely physical — no damage effects. See Section 6a.

**Pathfinding validity** — At least one valid path from entrance to exit must always exist. If placing a trap or barrier would eliminate all valid paths, the placement is rejected. This applies to both player-placed traps and arena evolution obstacles.

---

## **6a. Blocking Terrain & Arena Evolution**

**Blocking terrain** consists of environmental obstacles appropriate to the run's location. They are inert: no secondary effects on pests or traps. They act purely as physical barriers that reshape the maze. Obstacle names are location-specific — see the arena pool in Section 3.

**Arena Evolution** is triggered by boss waves — it occurs at the start of the wave immediately following each boss wave (waves 11, 21, 31, ...). At each evolution, two independent checks are made:

**Obstacle spawn check:**

| Outcome | Probability |
| :---- | :---- |
| 3 obstacles added | 5% |
| 2 obstacles added | 10% |
| 1 obstacle added | 15% |
| No obstacles added | 70% |

**Obstacle removal check** (independent of spawn check):

| Outcome | Probability |
| :---- | :---- |
| 1 random existing obstacle removed | 3% |
| No removal | 97% |

Obstacles are placed on a randomly selected cell anywhere in the arena. The only restrictions are pathfinding validity (the placement cannot eliminate all valid paths) and that entrance and exit cells are excluded. Cells occupied by player traps are not excluded — if an obstacle spawns on a trap, the trap is destroyed with no refund. The obstacle occupies that cell in its place.

Arena Evolution creates a sense of progression and forces the player to adapt their maze strategy as the environment slowly changes around them.

---

## **7. Progression & Economy**

**Currency: Bug Bucks**

Bug Bucks are earned by eliminating pests and spent on trap placement, upgrades, repositioning, and store rerolls. Bug Bucks are the player's sole resource.

| Source | Amount |
| :---- | :---- |
| Pest eliminated | Varies by pest type; scales with wave number |
| Wave clear bonus | Awarded when last pest of a wave is eliminated; amount TBD |
| Early wave trigger bonus | Small bonus for triggering a wave before the countdown expires; amount TBD |

**Infestation Level**

The Infestation Level fills as pests reach the exit. Each pest type deals a fixed infestation amount on exit, scaling upward with each wave. When the Infestation Level reaches its maximum threshold, the run ends.

The Infestation Level can be reduced through:
- **Store upgrades** — one-time reductions available as store options; reduction amount tied to upgrade tier
- **Trap modifier** — certain traps carry an infestation-reducing modifier; kills made by these traps reduce the Infestation Level by a small amount per kill (lifesteal-style)

**Wave structure**

Waves increase in complexity along a smooth curve across the entire run. Complexity governs:

- **Enemy count** — early waves: 5–10 enemies; scales toward ~20–30 at high complexity
- **Enemy type variety** — low complexity: 1–2 types; high complexity: more types
- **Group composition** — pests of the same type spawn in consecutive groups. At low complexity, groups are long (5+ units of a single type). As complexity increases, groups shorten and interleave more frequently. A group size of 1 is valid but uncommon.

Example spawn sequences by complexity:

| Complexity | Example sequence |
| :---- | :---- |
| Low | `AAAAA CCCCC` |
| Medium | `AAA CC AA BBB CC` |
| High | `AA C AA B CC A BB C A` |

**Boss waves**

Boss waves occur every 10 waves (waves 10, 20, 30, ...). The wave immediately following each boss wave triggers Arena Evolution.

- The Rat spawns first, leading the wave
- Escort enemies follow, composed using the same complexity-based group rules as standard waves
- Total escort count is half what a standard wave would contain at the same complexity
- The Rat's HP equals 60% of the total combined HP of all enemies in an equivalent standard wave — it scales automatically with difficulty

**The Store**

After each wave, the player visits the store. There is no timer — the player may take as long as needed.

The store presents 3 randomly selected upgrade options. Each option belongs to one of three categories:

| Category | Effect |
| :---- | :---- |
| Trap upgrade | Permanent stat improvement for a specific trap type (damage, range, trigger rate, etc.) |
| Player upgrade | Permanent stat improvement across all trap types, or other global benefit |
| Trap unlock | Makes a previously unavailable trap type purchasable for the rest of the run |

Upgrades have tiers. Higher-tier upgrades are more powerful, cost more Bug Bucks, and have a lower probability of appearing. The player may:

- **Purchase** any of the 3 options by spending Bug Bucks — applies immediately
- **Reroll** — spend Bug Bucks to replace all 3 options with a new random selection. Reroll cost is progressive and linear, resetting each store visit — the first reroll costs a base amount, each subsequent reroll within the same visit costs one increment more (e.g. 5, 10, 15, 20...). Exact base amount and increment TBD via playtesting.
- **Skip** — proceed to the next wave countdown without purchasing

**Starting trap selection**

At run start, before wave 1, 3 trap types are randomly selected and presented to the player. The player chooses 2. The chosen traps are immediately available for purchase and placement. The unchosen trap types may be unlocked later through the store.

**High score**

Composite of total pests eliminated and highest wave reached. Exact formula TBD.

| Attribute | Value |
| :---- | :---- |
| Currency | Bug Bucks |
| Sell value | 70% of buy price |
| Infestation Level | Starts at zero; fills as pests exit; run ends at maximum threshold |
| Exit infestation | Per pest type; scales each wave; wave 1 balanced so uncontested exit fills threshold to 2× |
| Bug Bucks reward | Per kill, varies by pest type; scales with wave number |
| Wave clear bonus | Awarded on last pest eliminated per wave; amount TBD |
| High score | Composite of total pests eliminated and highest wave reached; formula TBD |

---

## **8. Meta Progression & The Truck**

Between runs, the player returns to **The Truck** — their vehicle, home base, and equipment storage. The Truck is the hub screen between jobs. It reinforces the one-man pest control business framing: everything the player owns is in that truck.

**Hub options:**

| Option | Description |
| :---- | :---- |
| Start New Job | Begins a new run — randomly selects an arena and starts wave 1 |
| Upgrades | Opens the meta-upgrade screen; spend Service Fees on equipment and business improvements |
| Stats | View lifetime performance — total pests killed, highest wave reached, runs completed, and other tracked metrics |

---

**Meta Currency: Service Fees**

Service Fees are the player's profit across runs. While Bug Bucks represent gross earnings on the job — much of which goes to overhead and in-run expenses — Service Fees are what's left over: clean profit that goes back into the business.

Service Fees are earned at the end of each run based on performance:

- Pests eliminated during the run
- Highest wave reached

Better performance earns more Service Fees. Service Fees persist across runs and are never lost.

---

**Meta Upgrades**

Meta upgrades are permanent improvements purchased with Service Fees. They persist across all future runs. Two categories are available:

**Equipment upgrades** — improvements to the player's tools and traps:
- Starting stats for specific trap types (damage, range, trigger rate)
- Unlocking traps as permanent starting options
- DoT effectiveness, duration, or other trap modifiers

**Business upgrades** — improvements to the operation itself:
- Starting Bug Bucks amount at the beginning of each run
- Store options (more choices, reduced reroll costs)
- Starting Infestation Level threshold improvements
- Other run-start advantages

Specific upgrade trees and costs are TBD via playtesting.

---

## **9. Aesthetic Direction**

The game is intentionally graphically minimal. Game elements — traps, pests, terrain, projectiles — are represented by ASCII characters rendered as physical 3D objects. Characters are not flat sprites; they exist in three-dimensional space and move with physical weight and smoothness. A pest crossing the arena tilts into turns, bobs as it moves, and reacts physically when hit.

ASCII characters are rendered as flat planes (billboards) that always face the camera. They move smoothly through 3D space — tilting, rotating, and reacting physically — while remaining fully readable as characters from the top-down view.

**Death animation:** On death, a unit flashes briefly and disappears. No ragdoll or debris.

**Idle animation:** Player-placed traps may rotate slowly or pulse while idle. Exact behavior defined per trap type during implementation.

**Color:** Colored ASCII — a constrained palette where each element category (pest type, trap type, terrain, projectile) has a consistent color identity. Background is dark. Grid lines are not rendered. The palette shifts subtly as waves progress, giving the run a sense of escalation without loud or saturated hues.

**Cursor:** During placement, the cursor highlights the full grid cell under the player's finger/pointer as a single highlighted block. No visible grid otherwise.

**HUD:** Simple geometric shapes — not ASCII. Clean, readable UI panels for Bug Bucks count, Infestation Level, wave info, and speed controls.

**Camera:** Fixed top-down orthographic. Grid aligns cleanly to screen space; touch targeting is unambiguous.

**Font:** JetBrains Mono.

**Key aesthetic tags:** ASCII-as-physical-objects, colored, dark background, 3D smooth movement, minimal HUD.

**Audio:** Understated and quirky. Light enough to stay out of the way of gameplay, but with enough personality to reinforce the pest control theme. Tone sits between ambient/minimal and playfully odd. Licensed vs. original score TBD.

---

## **10. Mobile UX Considerations**

* Grid cells must meet minimum touch target size (44×44pt iOS guideline)

* Trap placement uses tap-to-select, tap-grid-cell-to-place flow — no drag and drop

* Pre-wave countdown is timer-limited — player should begin placing traps immediately

* Speed controls (1×, 2×, pause) always visible during combat phase

* Portrait orientation primary; landscape optional

* Bug Bucks count and Infestation Level always visible in HUD — trap picker never more than one tap away

* No internet required for core gameplay

**Arena scrolling / camera**

Arena size may grow as waves progress and could exceed the visible screen area. The viewport must support panning. Primary input is touch-screen, creating a gesture conflict between pan and placement tap.

Proposed resolution:

* **Short tap** — place/select trap on the tapped cell
* **Press-and-drag** — pan the viewport
* A threshold (e.g. 8–10px movement) distinguishes a tap from a drag before committing the action

Additional considerations:

* Off-screen pest indicators — directional arrows pinned to viewport edges point toward pests outside the current view. No minimap. Arrows scale in size/intensity with threat level. Visible during combat only.
* HUD elements must remain fixed on screen outside the scrollable arena viewport
* Pinch-to-zoom (optional) — allows strategic overview; minimum zoom must keep cells tappable

**Trap shop UX**

Long-pressing a trap in the selection screen opens a modal stat card. The card is visible for the duration of the press and dismisses automatically on release. This does not enter placement mode.

**Placed trap interaction**

When the player taps an already-placed trap, a context panel appears showing:

- Trap type name
- Trap type description
- Damage
- Damage type
- Range
- Upgrade star rating (1–5 stars) — tracks how many times this trap has been upgraded

Additionally, the trap's range circle is always rendered on the arena when the trap is selected, overlaid on the grid.

A trap must be upgraded 5 times (reaching 5 stars) before a variation becomes available.

---

## **11. Open Questions**

| Status | Question |
| :---- | :---- |
| Resolved | Title confirmed: Critter Quitters Pest Control |
| Resolved | Currency confirmed: Bug Bucks |
| Resolved | Monetization: premium (pay upfront, all gameplay included) |
| Resolved | Game structure: single persistent arena, continuous waves, no level resets |
| Resolved | Fail condition: Infestation Level reaching maximum threshold |
| Resolved | Entrance/exit: single entrance, single exit, on separate walls, not necessarily opposite |
| Resolved | Wave complexity: smooth curve across all waves |
| Resolved | Wave composition: group-based, group size shrinks with complexity, minimum group size 1 (uncommon) |
| Resolved | Boss wave structure: Rat leads, escorts follow; escort count = half standard wave; Rat HP = 60% of standard wave total HP |
| Resolved | Arena Evolution: every 10 waves, small chance of 1–few obstacles added; overwrites traps with no refund |
| Resolved | Starting trap selection: 3 offered, player picks 2; remaining unlockable in store |
| Resolved | Store: 3 tiered options per visit (trap upgrade, player upgrade, trap unlock); reroll for Bug Bucks |
| Resolved | Infestation healing: store option (one-time reduction) and trap modifier (lifesteal-style per kill) |
| Resolved | Pathfinding: minimum one valid path always enforced |
| Resolved | Trap footprint: mostly 1×1; some use 3+ contiguous cells in irregular shapes |
| Resolved | Sell value: 70% of buy price |
| Resolved | Grid dimensions — 14×14 (fixed; subject to change via playtesting) |
| Resolved | Boss wave frequency — every 10 waves (waves 10, 20, 30, ...) |
| Resolved | Store reroll cost — progressive linear per visit, resets each visit; base amount and increment TBD via playtesting |
| Resolved | Trap shop UX — long-press on trap in selection screen shows a modal stat card; dismisses on release |
| Resolved | Placed trap interaction — context panel shows trap type, description, damage, damage type, range, and upgrade star rating (1–5); variation unlocks after 5 upgrades |
| Resolved | Blocking terrain name — location-specific per arena (Appliances, Yard Clutter, Storage, Clutter) |
| Resolved | Blocking terrain spawn rules — 15% chance 1 spawns, 10% chance 2, 5% chance 3; independent 3% chance 1 existing obstacle removed |
| Resolved | Trap names — Snap Trap, Zapper, Fogger, Glue Board (final) |
| Resolved | Audio — tone is understated and quirky; light enough to not distract, with enough personality to reinforce the pest control theme |
| Resolved | Fogger AoE radius — equals the Fogger's range circle; no separate value needed |
| Deferred | All numeric values (Infestation Level threshold, Bug Bucks rewards per pest type, wave clear bonus, early wave trigger bonus, reroll cost base and increment, high score formula) — to be determined via playtesting |

---

## **12. Future Pass**

The following mechanics were identified during design but deferred to a later pass. They should not block v1 development.

**Flying units** — Pests that travel through the air and ignore ground traps entirely. Requires a dedicated anti-air trap type (e.g. a bug zapper variant with aerial targeting). Candidate pest: Mosquito.

**Pest split / survival mechanic** — A pest that survives certain traps or splits into multiple smaller units on death. Candidate pest: Cockroach.

**Barrier-breaking** — A pest capable of destroying or damaging blocking terrain. Candidate pest: Mouse / Rat variant.

**Placeable ally unit** — A neutral or friendly creature the player can deploy that acts as a trap or deterrent. Candidate unit: Spider.

**Additional pests** — Slug (extremely slow, possibly damages traps), Cricket (erratic movement, hard to predict) considered for later roster expansion.

**Blocking terrain secondary effects** — Terrain objects with passive effects on adjacent pests or traps. Currently inert — secondary effects deferred.

---

## **13. Tech Stack**

| Decision | Choice |
| :---- | :---- |
| Engine | Godot 4 (latest stable at project start) |
| Language | GDScript |
| Renderer | Mobile |
| Project type | 3D — fixed orthographic camera reads as 2D to the player; 3D world required for ASCII billboard aesthetic |
| Source control | Git + GitHub |
| Branching strategy | `main` + feature branches |

---

## **14. Development Path**

Development is phased to front-load the highest technical risk. The pathfinding system is the core mechanic and must be proven before other systems are built on top of it.

### **Phase 1 — Core Mechanic Prototype**
- Godot project setup and GitHub repository
- Grid system
- A\* pathfinding with real-time recalculation on trap placement and removal
- Pathfinding validity check — reject placements that would block all paths
- Placeholder traps as physical obstacles
- Basic enemy movement along the calculated path

*Goal: prove the maze-building mechanic works and feels right*

### **Phase 2 — Combat Loop**
- Trap targeting and projectile visuals
- Enemy HP, damage, and death
- Bug Bucks earned on kill
- Infestation Level fills when pests reach the exit
- Single wave type, single enemy type

*Goal: first playable loop*

### **Phase 3 — ASCII Aesthetic**
- 3D billboard rendering for ASCII characters
- Physical movement — tilt, bob, hit reaction
- Fixed orthographic camera
- Death animation
- Basic per-element color palette

*Goal: looks and feels like the game*

### **Phase 4 — Full Game Loop**
- Wave composition system — complexity curve, group-based spawning, boss waves
- All 4 trap types
- All 5 enemy types
- Starting trap selection — 3 offered, player picks 2
- Between-wave store — basic version (trap upgrades, player upgrades, trap unlocks)
- Arena Evolution — obstacle spawning every 10 waves
- Save file system — multiple independent run slots

*Goal: complete playable game from start to run-end*

### **Phase 4b — Meta Progression**
- Service Fees earned at run end based on performance
- The Truck hub screen — Start New Job, Upgrades, Stats
- Equipment upgrade tree
- Business upgrade tree
- Stats tracking — pests killed, highest wave, runs completed

*Goal: long-term progression loop across runs*

### **Phase 5 — Depth & Polish**
- Full upgrade trees and DoT system (fire, ice)
- Trap unlock progression
- Store tiers, reroll mechanic
- Infestation healing — store options and trap modifier
- HUD polish
- Audio

*Goal: full-featured game*

### **Phase 6 — Platform**
- Mobile export and touch controls
- Web export
- Performance optimisation

*Goal: shippable on target platforms*
