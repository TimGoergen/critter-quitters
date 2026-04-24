# **Critter Quitters Pest Control — Game Design Document**

**Version:** Draft v0.16 **Status:** Concept / Pre-production **Platform:** Mobile (iOS / Android) / Web **Art Style:** ASCII / minimalist **Reference:** Desktop Tower Defense

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
| v0.11 | Grid size updated to 30×30. Trap footprint updated to 2×2. Cursor/grid highlight updated: radial glow always visible on hover, not just during placement. GDD updated to match Phase 1 prototype implementation. |
| v0.12 | Arena wall model clarified: border walls occupy the leftmost and rightmost columns of the arena floor as blocked cells; they are not a separate outer ring. The entrance and exit gaps are simply the unblocked rows in those columns. Entrance and exit gap width increased from 3 rows to 5 rows. Trap placement is permitted in gap cells subject to the pathfinding validity check (at least one gap row must remain passable). |
| v0.13 | (unchanged) |
| v0.14 | Aesthetic direction fully revised. ASCII character rendering removed. Enemies and traps are now illustrated 2D sprites (Sprite3D in 3D world space), art style targeting modern CGI children's shows (rounded shapes, soft shading, slightly saturated palette). Traps are playful and cartoonish with thematic detail. Projectiles and hit effects remain 3D shapes and particles. Background system redesigned: procedurally generated, animated, arena-themed, with repeated environmental shapes; evolves slowly with each wave. Enemy animation defined: thematically appropriate walk/waddle with side-to-side movement plus hit reaction. Engine stays 3D (Godot 4, Mobile renderer) to preserve existing particle effects. |
| v0.15 | Between-wave upgrade store removed entirely. Direct per-trap upgrade system introduced: each placed trap has a star level (0–5) and a tier (0+). Tapping a placed trap opens an upgrade panel offering three stat choices (Damage, Range, Fire Rate). Reaching star 5 enables a tier-up that resets the star and offers dramatic variation options. Upgrade and tier-up cost formulas defined. |
| v0.16 | GDD updated to reflect implemented code state. Upgrade system description corrected: code implements per-stat independent upgrades (3 levels each) with a full-upgrade bonus, not the star/tier system from v0.15 (star/tier remains the design goal for a future pass). Section 2 targeting and projectile damage timing corrected. Section 4 Fogger damage model corrected (staggered by distance, not simultaneous). Snap Trap procedural placeholder visual documented. Section 13 ASCII reference corrected. Phase 3 marked in-progress. |

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

**Targeting:** Each trap has its own targeting model — see Section 4 for per-trap details.

**Projectiles:** Traps fire projectiles or release effects that travel visually toward their target. Damage is applied when the projectile reaches its target — the enemy hit flash and impact effect coincide with arrival.

**Placement during combat:** Trap placement is not locked to the pre-wave phase. The player may place, upgrade, or sell traps at any point during a wave as Bug Bucks become available. Path visualisation updates in real time. All pests currently on the arena immediately recalculate their path when the layout changes.

---

## **3. Arena & Layout**

The arena is a single persistent space that endures for the entire run. It does not reset between waves. The player's trap layout accumulates over time — each wave is played on the same arena the player has been building.

The arena is flat, open, and grid-based to support touch placement on mobile. Grid cells resolve at a size that allows comfortable finger-tap accuracy on phones.

Each run has one entrance and one exit, assigned to separate walls at run start. They are not necessarily on opposite walls. Enemies always enter from the entrance and always target the exit.

The border walls are represented as blocked cells occupying the leftmost and rightmost columns of the 30×30 grid. The entrance and exit are gaps in those columns — 5 consecutive unblocked rows centered on the assigned entrance/exit row. The player may place traps in gap cells as long as at least one gap row remains passable and a valid path to the exit still exists.

| Attribute | Value |
| :---- | :---- |
| Entry points | One — assigned to a wall at run start |
| Exit points | One — assigned to a different wall at run start |
| Gap width | 5 rows (entrance and exit) |
| Grid size | 30×30 (fixed) |
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

Each trap is a tool in an exterminator's kit.

**Availability:** Not all traps are available at run start. The player selects 2 of 3 randomly offered traps before wave 1. Remaining traps may be unlocked through the store.

**Upgrade system (implemented):** Traps are upgraded directly through the trap context panel. Each placed trap tracks three independent upgrade levels — one per stat (Damage, Range, Fire Rate). Each stat can be upgraded up to 3 times. Two traps of the same type can be independently upgraded.

The upgrade panel shows current stat values with per-stat star indicators (e.g. ★★☆) and three upgrade buttons. Each button shows the current value and the value after that upgrade so the choice is informed.

**Stat increments per upgrade level:**
- Damage: +25% of base value per level
- Range: +10% of base value per level
- Fire Rate: −8% of base cooldown per level (faster shots); minimum cooldown 0.1 s

**Upgrade costs** are defined per trap type and per level (values are tuning placeholders):

| Trap | Level 1 | Level 2 | Level 3 |
| :---- | :---- | :---- | :---- |
| Snap Trap | 20 | 30 | 50 |
| Zapper | 50 | 75 | 120 |
| Fogger | 40 | 60 | 100 |
| Glue Board | 30 | 45 | 70 |

**Full upgrade bonus:** When all upgradeable stats on a trap reach level 3, all stats receive a one-time +10% boost as a reward for full investment. Fire rate boost reduces cooldown by 10% (shots per second increases by ~11%).

**Fire Rate** is not upgradeable on passive traps (Glue Board).

*Note: a star/tier system (star level 0–5, tier 0+, dramatic tier-up variations) is the intended long-term design but is not yet implemented. The per-stat independent system above is the current implementation.*

**Infestation modifier:** Certain traps or trap upgrades carry an infestation-reducing modifier. Kills made by these traps reduce the Infestation Level by a small amount per kill — a lifesteal-style mechanic that rewards strategic placement and active killing. *(Planned — not yet implemented.)*

**DoT effects** (Planned — not yet implemented in the current build):

| DoT Type | Behavior |
| :---- | :---- |
| Fire | Deals repeated damage ticks for a duration after the hit |
| Ice | Reduces pest movement speed for a duration after the hit |

DoT rules: effects do not stack (a subsequent hit refreshes duration); effects do not spread; Fire and Ice can coexist on the same pest simultaneously.

**Footprint:** Traps occupy a 2×2 cell footprint. Placement is anchored to the top-left cell of the footprint. Footprints are fixed and do not rotate — all traps operate in a full 360-degree arc.

### **The Snap Trap**

**Archetype:** Basic / single-target

Cheap, reliable. Small range circle, fast trigger rate, low damage. Fires at the nearest exposed pest. The expendable backbone of any build.

**Targeting:** Nearest enemy in range.

**Projectile:** A tumbling cheese wedge (the trap's bait, flung at the target). Impact produces a cheese-splat particle burst; kills add an enemy-color burst on top.

**Placeholder visual (current):** A portrait-oriented procedural mesh — narrow wooden base, coil spring at the hinge end, U-shaped wire kill bar (two thin arms and a front crossbar) that slams down on fire and resets after half the cooldown, and a small yellow triangular cheese wedge on the trigger platform that disappears during the snap. To be replaced by an illustrated Sprite3D.

### **The Zapper**

**Archetype:** Long range / high damage

Large range circle, very slow trigger rate, high damage. Fires an electrical bolt at the exposed pest farthest along the path. Its wide range circle allows it to reach pests deep in corridors without being placed near them. Eliminates standard pests outright late in upgrade path.

### **The Fogger**

**Archetype:** Area of effect / high damage

Medium range circle, slow trigger rate, high damage per burst. When it fires, a fog cloud expands outward from the trap and damages exposed pests as the expanding wave reaches each one — pests closer to the trap are hit first. The range circle defines both triggering and AoE coverage. Ideal for chokepoints and tightly packed groups.

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

**Pathfinding validity** — At least one valid path from entrance to exit must always exist, and at least one row in each gap must remain unblocked. If placing a trap or barrier would violate either constraint, the placement is rejected. This applies to both player-placed traps and arena evolution obstacles.

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

**Direct Trap Upgrades**

There is no between-wave store. Traps are upgraded directly by tapping a placed trap at any time — during a wave or between waves — as Bug Bucks become available from kills.

Tapping a placed trap opens the upgrade panel for that specific trap instance. The panel displays the trap name, current values for Damage, Range, and Fire Rate with per-stat star indicators (★★☆ style), and three upgrade buttons — one per stat. Each button shows the current value and the post-upgrade value. The player selects one stat to upgrade; the cost is deducted from Bug Bucks. A button is disabled when that stat is fully upgraded (shows MAX) or when the player cannot afford it. Tapping outside the panel or the close button dismisses it.

See Section 4 for upgrade costs, stat increments, and the full upgrade bonus.

**Starting trap selection**

At run start, before wave 1, 3 trap types are randomly selected and presented to the player. The player chooses 2. The chosen traps are immediately available for purchase and placement. Trap unlock mechanic TBD.

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

The game targets a modern CGI children's show aesthetic — clean rounded shapes, soft shading implying volume, slightly saturated but not garish colors, and exaggerated but immediately readable silhouettes. Reference points: Bluey, Paw Patrol, early Pixar shorts.

**Enemies and traps** are illustrated 2D images generated using AI image generation tools, then imported as `Sprite3D` nodes in the 3D scene. They exist in 3D world space and move through it, but remain flat planes that always face the camera. The player reads the game as top-down 2D; the 3D engine handles depth, particles, and lighting.

**Trap visuals** are playful and cartoonish with enough detail to read thematically. Each trap should visually resemble what it does: a Snap Trap looks like an oversized spring-loaded mousetrap; a Zapper looks like a chunky cartoon bug zapper; a Fogger looks like a chunky spray canister. Trap style contrasts with enemies — mechanical and equipment-like vs. organic and creature-like.

**Enemy animation:** Each enemy type has a thematically appropriate walk or waddle cycle with visible side-to-side movement. Enemies also play a hit reaction animation when struck. Animation is sprite-based (frame sequences or shader-driven on the Sprite3D).

**Death animation:** On death, a unit flashes briefly and disappears. No ragdoll or debris.

**Trap idle animation:** Traps may rotate slowly or pulse while idle. Exact behavior defined per trap type during implementation.

**Projectiles and effects:** Retained as 3D geometric shapes and GPU particles. These are not replaced with sprites — keeping them 3D preserves flexibility for future visual complexity.

**Background:** The background is a procedurally generated animated environment that suggests the arena's setting (Kitchen, Backyard, Basement, Attic). It uses repeated themed shapes and designs to imply objects in the environment without being a hand-authored illustration. The background evolves slowly with each new wave — shifting, adding, or changing elements to reinforce a sense of progression. Background position relative to the play grid (beneath, surrounding, or both) is TBD during implementation.

**Cursor:** A radial grid glow is always visible, centered on the hovered cell. The glow extends 3 cells in each direction from the cursor, with alpha falling off quadratically so cells farther away appear dimmer. No static grid lines are rendered — the glow is the only grid indicator.

**HUD:** Simple geometric shapes. Clean, readable UI panels for Bug Bucks count, Infestation Level, wave info, and speed controls.

**Camera:** Fixed top-down orthographic. Grid aligns cleanly to screen space; touch targeting is unambiguous.

**Color:** A constrained palette where each element category (pest type, trap type, terrain, projectile) has a consistent color identity. The palette shifts subtly as waves progress, giving the run a sense of escalation without loud or saturated hues.

**Audio:** Understated and quirky. Light enough to stay out of the way of gameplay, but with enough personality to reinforce the pest control theme. Tone sits between ambient/minimal and playfully odd. Licensed vs. original score TBD.

**Key aesthetic tags:** CGI-cartoon illustrated sprites, soft shading, slightly saturated palette, 3D particle effects, procedural animated background, minimal HUD.

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

**Placed trap interaction**

When the player taps an already-placed trap, an upgrade panel appears showing:

- Trap type name and current tier
- Star level (0–5, displayed as filled/empty stars)
- Current damage, range, and fire rate
- Upgrade cost in Bug Bucks
- Three upgrade buttons (Damage, Range, Fire Rate) — each shows the current value and the value after that upgrade, so the choice is informed

At star 5, the three buttons are replaced by three tier-up variation options. These offer dramatic stat changes and advance the trap to the next tier with the star resetting to 0.

The panel is dismissed by tapping the close button or tapping an empty arena cell.

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
| Resolved | Upgrade system: direct per-trap upgrades via tap; star level 0–5, tier 0+; cost formula defined; tier-up at star 5 |
| Resolved | Infestation healing: store option (one-time reduction) and trap modifier (lifesteal-style per kill) |
| Resolved | Pathfinding: minimum one valid path always enforced |
| Resolved | Trap footprint: 2×2, anchored at top-left cell |
| Resolved | Sell value: 70% of buy price |
| Resolved | Grid dimensions — 30×30 (fixed; subject to change via playtesting) |
| Resolved | Boss wave frequency — every 10 waves (waves 10, 20, 30, ...) |
| Resolved | Store reroll cost — progressive linear per visit, resets each visit; base amount and increment TBD via playtesting |
| Resolved | Trap shop UX — long-press on trap in selection screen shows a modal stat card; dismisses on release |
| Resolved | Placed trap interaction — upgrade panel shows trap type, tier, star level (0–5), damage, range, fire rate, upgrade cost, and three upgrade buttons; tier-up options appear at star 5 |
| Resolved | Blocking terrain name — location-specific per arena (Appliances, Yard Clutter, Storage, Clutter) |
| Resolved | Blocking terrain spawn rules — 15% chance 1 spawns, 10% chance 2, 5% chance 3; independent 3% chance 1 existing obstacle removed |
| Resolved | Trap names — Snap Trap, Zapper, Fogger, Glue Board (final) |
| Resolved | Audio — tone is understated and quirky; light enough to not distract, with enough personality to reinforce the pest control theme |
| Resolved | Fogger AoE radius — equals the Fogger's range circle; no separate value needed |
| Deferred | All numeric values (Infestation Level threshold, Bug Bucks rewards per pest type, wave clear bonus, early wave trigger bonus, upgrade stat increment amounts, high score formula) — to be determined via playtesting |

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
| Project type | 3D — fixed orthographic camera reads as 2D to the player; enemies and traps are Sprite3D nodes in 3D world space; projectiles and effects are 3D geometry and particles |
| Source control | Git + GitHub |
| Branching strategy | `main` + feature branches |

---

## **14. Development Path**

Development is phased to front-load the highest technical risk. The pathfinding system is the core mechanic and must be proven before other systems are built on top of it.

### **Phase 1 — Core Mechanic Prototype** ✓ Complete
- Godot project setup and GitHub repository
- Grid system
- A\* pathfinding with real-time recalculation on trap placement and removal
- Pathfinding validity check — reject placements that would block all paths
- Placeholder traps as physical obstacles
- Basic enemy movement along the calculated path

*Goal: prove the maze-building mechanic works and feels right*

### **Phase 2 — Combat Loop** ✓ Complete
- Trap targeting and projectile visuals
- Enemy HP, damage, and death
- Bug Bucks earned on kill
- Infestation Level fills when pests reach the exit
- Run-over state — "INFESTED!" overlay with Restart on Infestation Level reaching 100%
- Single wave type, single enemy type

*Goal: first playable loop*

### **Phase 3 — Visual Style** *(In progress)*
- ✓ Enemy walk/waddle animation — Ant has a 4-frame SVG sprite walk cycle with directional facing and side-to-side waddle
- ✓ Enemy hit reaction — brief white flash on hit; white flash then queue_free on death
- ✓ Snap Trap procedural placeholder visual — portrait mousetrap shape with animated kill bar and cheese wedge; to be replaced by illustrated Sprite3D
- ✓ Snap Trap projectile — tumbling cheese wedge with cheese-splat impact particles
- ✗ Sprite3D art for all enemies (Ant SVG placeholder only; Cricket, Beetle, Cockroach, Rat still use colored cylinders)
- ✗ Sprite3D art for all traps (Snap Trap uses procedural mesh; Zapper, Fogger, Glue Board use colored boxes)
- ✗ Procedural animated background system
- ✗ Basic per-element color palette

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
