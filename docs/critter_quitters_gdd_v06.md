# **Critter Quitters Pest Control — Game Design Document**

**Version:** Draft v0.6 **Status:** Concept / Pre-production **Platform:** Mobile (iOS / Android) / Web **Art Style:** ASCII / minimalist **Reference:** Desktop Tower Defense

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

---

## **Table of Contents**

1. Overview & Premise
2. Core Loop
3. Arena & Layout
4. Tower Roster
5. Enemy Roster
6. Mechanics
6a. Blocking Terrain
7. Progression & Economy
8. Aesthetic Direction
9. Mobile UX Considerations
10. Open Questions
11. Future Pass

---

## **1. Overview & Premise**

Critter Quitters Pest Control is a mobile tower defense game built on the open maze-building mechanic pioneered by Desktop Tower Defense (2007). The player controls no pre-defined path — instead, pest units enter an open space and pathfind in real time around whatever the player places. The maze is the strategy. The trap corridor is whatever you make it.

You are an exterminator. Pests are invading a property — a kitchen, a basement, a backyard — and they are heading for a food source, a nest site, or an exit point. Your job is to place traps, barriers, and deterrents to reroute and eliminate them before they get there. Pests naturally pathfind around obstacles — building maze-like trap corridors feels completely believable.

The tone is functional with a light comic edge: this is a local pest control company doing a job, and the job keeps getting worse.

| Attribute | Value |
| :---- | :---- |
| Genre | Tower defense / maze builder |
| Target audience | Males 35–55, TD veterans |
| Session length | 10–25 min per run |
| Platform | Mobile (iOS / Android) / Web |
| Monetization | Premium (pay upfront, all gameplay included) |

---

## **2. Core Loop**

1. Wave announced — player sees incoming pest type and count

2. Pre-wave countdown — a timer counts down before the wave begins. The player must start placing traps immediately; there is no separate idle build phase. The current pest path is visualised on the arena. The player may trigger the wave early to receive a bonus (amount TBD).

3. Wave — pests enter sequentially in groups; each group spawns from either the left or top entrance. Early levels use a single entrance; later levels introduce groups from both entrances within the same wave. Spacing between units is dynamic but consistent within a group. The player may continue to place, upgrade, or sell traps during the wave as Bounties are earned.

4. Pests that reach the exit deal a fixed amount of damage to the property's HP pool based on pest type, then disappear; Property HP reaching zero ends the run.

5. Eliminated pests pay out Bounties based on pest type, scaled by current level/wave; when the last pest of the wave is eliminated a wave clear bonus is awarded (amount TBD).

6. Between waves — the player visits the upgrade store and spends Bounties on available offers before the next wave countdown begins. Repeat from step 1.

Unlike lane-based TD games, the player's trap layout directly determines pest pathing. Longer, more convoluted corridors increase trap exposure time. At least one valid path from an entry point to an exit point must always exist. This is enforced proactively: if placing a trap or barrier would eliminate all valid paths, the placement is rejected and the player is not permitted to confirm it.

**Unit interaction rules:** Pests cannot affect player traps in any way. Each trap defines only its own trigger rate, damage, and range — traps do not buff or debuff other traps. Traps may apply fire or ice DoT effects directly to pests they hit.

**Targeting:** Each trap targets the pest within its range that is farthest along the current path toward an exit — prioritising the most immediate threat to the property.

**Projectiles:** Traps fire projectiles or release effects that travel visually across the arena toward their target. Damage is applied instantly on firing — the projectile travel is cosmetic. This keeps combat feel snappy without requiring collision-based hit detection.

**Placement during combat:** Trap placement is not locked to the build phase. The player may place, upgrade, or reposition traps at any point during a wave as Bounties become available. Path visualisation updates in real time as new traps are placed. All pests currently on the arena immediately recalculate their path when the layout changes — live rerouting applies to every active unit, not just newly spawned ones.

---

## **3. Arena & Layout**

The arena is a flat, open space representing a room or location within a property. Visually clean and grid-based to support touch placement on mobile. The grid resolves at a size that allows comfortable finger-tap accuracy on phones. Each level generates a fresh arena representing a different location — kitchen, basement, attic, backyard, restaurant, grocery store — each with its own layout and optional blocking terrain.

| Attribute | Value |
| :---- | :---- |
| Entry points | Left edge and top edge |
| Exit points | Right edge and bottom edge |
| Grid size | TBD |
| Pathfinding | A\* real-time |

---

## **4. Tower Roster (Initial)**

Each trap or deterrent is a tool in an exterminator's kit. Naming follows working titles for now — final names TBD.

**Upgrade system:** Each trap has branching upgrade paths. Within each branch, the player purchases incremental upgrades that improve a core metric (damage, trigger rate, range, or other stats). When a branch is fully upgraded, a new upgrade path unlocks — evolving the trap into a more advanced unit type with expanded abilities. Fully evolved units can inflict damage-over-time (DoT) effects that persist on a pest for a set duration:

| DoT Type | Behavior |
| :---- | :---- |
| Fire | Deals repeated damage ticks for a duration after the hit |
| Ice | Reduces pest movement speed for a duration after the hit |

**DoT rules:**
- Effects do not stack — a subsequent hit of the same type refreshes the duration rather than adding a second instance
- Effects do not spread or travel; they apply only to the pest directly hit
- Fire and Ice can coexist on the same pest simultaneously

**Evolved unit visuals:** As a trap evolves through its upgrade tree, its ASCII character representation grows more prominent — shifting from lowercase to uppercase, increasing in visual weight, or using a bolder character variant. More advanced units look more imposing at a glance.

**Footprint:** Most traps occupy a single 1×1 cell. Some traps occupy 3 or more contiguous cells in irregular shapes (L-shapes, T-shapes, etc.). The full footprint must fit on empty, unoccupied cells for placement to be valid. Footprints are fixed and do not rotate — all traps operate in a full 360-degree arc and have no facing direction.

### **The Snap Trap**

**Archetype:** Basic / single-target

Cheap, reliable. Fast trigger rate, low damage. The expendable backbone of any build. Upgrade path: faster trigger rate or wider detection range.

### **The Zapper**

**Archetype:** Long range / high damage

Extreme range, very slow trigger rate. Prioritizes highest-HP target. Eliminates standard pests outright late in upgrade path.

### **The Fogger**

**Archetype:** Area of effect / high damage

Slow trigger rate, high damage per burst. Attacks deal AoE damage to all pests in a radius around the target. Ideal for chokepoints and tightly packed groups. AoE radius TBD.

### **The Glue Board**

**Archetype:** Ice / area slow

Applies ice DoT to pests in a radius — reducing their movement speed for a duration. Low cost, low footprint.

---

## **5. Enemy Roster (Initial)**

| Name | Archetype | Behavior | Tier |
| :---- | :---- | :---- | :---- |
| The Ant | Standard | Low HP, fast, appears in large numbers. No special mechanics. The most common pest on the property. | 1 |
| The Cricket | Fast / erratic | Low HP, very fast. Punishes gaps in coverage. | 2 |
| The Beetle | Mid-tier tank | High HP, slow movement, moderate exit damage. Uncommon — appears occasionally within standard waves. | 3 |
| The Cockroach | High-tier resilient | Very high HP, very slow movement, high exit damage. Rare — less common than The Beetle. Hard to kill. | 4 |
| The Rat | Boss | Massive HP, slowest movement, highest exit damage. One per wave maximum. Designated boss unit. | Boss |

---

## **6. Mechanics**

**Repositioning cost** — Moving a placed trap costs a small Bounty fee, adding weight to placement decisions without fully locking the player in.

**Selling** — Traps may be sold at any time, including during combat. Selling returns 70% of the trap's buy price. Pests on the arena reroute immediately when a trap is removed, consistent with live rerouting on placement.

**Blocking terrain** — Each level has a chance of spawning a small number of pre-placed terrain objects at round start. These cells cannot have traps placed on them and cannot be crossed by pests. They reshape the open arena into something irregular, forcing the player to adapt their trap layout. See Section 6a for details.

---

## **6a. Blocking Terrain**

Each level has a random chance of placing a small number of terrain objects in the arena before the first wave. These are permanent for the duration of the run and cannot be removed. No trap may be placed on them; no pest may cross them.

**Name: TBD** — candidates listed below. Blocking terrain is currently inert: no secondary effects on pests or traps. Thematically and aesthetically appropriate for the current room or location, present as environmental obstacles only. Secondary effects may be considered in a future pass.

| Candidate Name | Theme Fit |
| :---- | :---- |
| Furniture | Strong — sofas, tables, chairs block movement naturally |
| Appliances | Strong — fridges, washing machines, large fixed objects |
| Boxes / Clutter | Strong — storage rooms, attics, basements |
| Pipes | Good — utility rooms, basements |
| Pallets | Good — warehouse, grocery store, restaurant back-of-house |

**Spawn rules (TBD):** Probability of terrain spawning per level, min/max count, placement constraints (must not block all paths, must not spawn on entry/exit edges).

---

## **7. Progression & Economy**

Bounties are earned per kill and per wave cleared. Tower costs follow a DTD-style tiered pricing model — cheap units available early, specialist units gated by cost. A starting budget of Bounties is granted at run start.

**Structure:** The game is endless — there is no final level. The player reaches for a high score determined by total pests eliminated and the highest level reached.

**Levels** are auto-generated and increase incrementally in difficulty. Each level begins with a freshly generated arena representing a new location, including any blocking terrain for that level (see Section 6a). The arena layout remains fixed for the entire level. Each level contains a dynamic number of waves that increases as levels progress — early levels have fewer waves, later levels have more.

**Waves** escalate in difficulty within each level: pest count, type mix, and exit damage increase across waves. Entry point variety also expands as levels progress.

**Trap persistence:** Each level starts fresh. The arena is empty and the player is given the opening Bounty budget at the start of every level. No traps carry over between levels.

**Property HP:** Each level has its own unique HP value, scaled to the difficulty of that level. Property HP does not carry between levels — it resets fully at the start of each new arena. Within a level, all damage is permanent. Certain consumables can restore Property HP during a level.

**Between-wave upgrade store:** After each wave, the player visits the upgrade store. There is no timer — the player may take as long as needed. The store presents 3 or 4 randomly selected items. The player may:

- **Purchase** one or more items by spending Bounties — applies immediately
- **Reroll** the item list by spending Bounties — replaces all current offers with a new random selection. Reroll cost starts at a fixed base amount each store visit and increases by a fixed increment with each use (e.g. 5 → 10 → 15 → ...). The cost resets at the start of every between-wave store visit. Exact base cost and increment TBD via playtesting.
- **Skip** — proceed to the next wave countdown without buying anything

All purchases apply immediately. There is no inventory. Upgrade types include:

| Type | Effect |
| :---- | :---- |
| Stat upgrade | Permanent boost for the remainder of the run (e.g. increased trap damage, improved Bounty income) |
| Immediate payout | One-time grant of Bounties, Property HP, or other resource |

The store creates a meaningful Bounty-spending decision each wave — the player must weigh trap investment vs. upgrades vs. saving Bounties for a reroll.

| Attribute | Value |
| :---- | :---- |
| Currency | Bounties |
| Starting budget | Small — enough to introduce the economy and allow a meaningful initial placement choice; exact amount TBD via playtesting |
| Sell value | 70% of buy price |
| Property HP | Starting value is low enough that a small number of pests reaching the exit is threatening; exact value TBD via playtesting |
| Exit damage | Per pest type, scales upward each wave. Wave 1 is balanced so that if all pests reached the exit uncontested, they would deal twice the property's starting HP in total damage — the player must stop at least half to survive |
| Bounty reward | Per kill, varies by pest type; scales with level/wave |
| Wave clear bonus | Awarded on last pest eliminated per wave; amount TBD (to be tuned) |
| High score | Composite of total pests eliminated and highest level reached; exact formula TBD |

---

## **8. Aesthetic Direction**

The game is intentionally graphically minimal. Game elements — traps, pests, terrain, projectiles — are represented by ASCII characters rendered as physical 3D objects. Characters are not flat sprites; they exist in three-dimensional space and move with physical weight and smoothness. A pest crossing the arena tilts into turns, bobs as it moves, and reacts physically when hit. Projectiles and trap effects travel through 3D space. Traps have presence and idle animation.

ASCII characters are rendered as flat planes (billboards) that always face the camera. They move smoothly through 3D space — tilting, rotating, and reacting physically — while remaining fully readable as characters from the top-down view. This gives the game a demoscene / experimental quality that is visually distinctive without requiring conventional artwork.

**Death animation:** On death, a unit flashes briefly and disappears. No ragdoll or debris.

**Idle animation:** Player-placed traps may rotate slowly or pulse while idle — reinforcing their physical presence between trigger events. Exact behavior defined per trap type during implementation.

**Color:** Colored ASCII — a simple, constrained palette where each element category (pest type, trap type, terrain, projectile) has a consistent color identity. Background is dark. Grid lines are not rendered. Each level uses its own muted complementary palette tied to the room or location — a kitchen level reads differently from a basement level — colors shift as the player progresses, giving each level a distinct mood without loud or saturated hues.

**Cursor:** During placement, the cursor highlights the full grid cell under the player's finger/pointer as a single highlighted block. No visible grid otherwise.

**HUD:** Simple geometric shapes — not ASCII. Clean, readable UI panels for Bounty count, Property HP, wave info, and speed controls.

**Camera:** Fixed top-down orthographic. Grid aligns cleanly to screen space; touch targeting is unambiguous.

**Font:** JetBrains Mono.

**Key aesthetic tags:** ASCII-as-physical-objects, colored, dark background, 3D smooth movement, minimal HUD.

---

## **9. Mobile UX Considerations**

* Grid cells must meet minimum touch target size (44×44pt iOS guideline)

* Trap placement uses tap-to-select, tap-grid-cell-to-place flow — no drag and drop

* Pre-wave countdown is timer-limited — player should begin placing traps immediately when the countdown starts

* Speed controls (1×, 2×, pause) always visible during combat phase

* Portrait orientation primary; landscape optional

* Bounty count always visible in HUD — trap picker never more than one tap away

* No internet required for core gameplay

**Arena scrolling / camera**

Arena size grows as levels progress and will exceed the visible screen area at higher levels. The viewport must support panning across the arena. Primary input is touch-screen, which creates a gesture conflict: a pan gesture and a trap-placement tap occur on the same surface.

Proposed resolution:

* **Short tap** — place/select trap on the tapped cell
* **Press-and-drag** — pan the viewport
* A threshold (e.g. 8–10px movement) distinguishes a tap from a drag before committing the action

Additional considerations:

* Off-screen pest indicators — directional arrows pinned to the viewport edges point toward pests outside the current view. No minimap. Arrows carry no explicit text (no count or type label) but scale in size/intensity with the threat level of off-screen pests. Indicators are visible during combat phase only — not during build phase.
* HUD elements (trap picker, Bounty count, wave info, speed controls) must remain fixed on screen and outside the scrollable arena viewport — never scroll away
* Pinch-to-zoom (optional) — allows the player to zoom out for a strategic overview; minimum zoom level must keep cells tappable

**Trap shop UX — open**

How the player views trap stats before purchasing. Candidates:

* **Tap to preview** — tapping a trap in the shop opens a stat card before entering placement mode
* **Always visible** — stats shown inline in the shop without needing to tap
* **Placement preview** — stats only visible once the player enters placement mode with the trap ghosted on the grid

**Placed trap interaction — open**

When the player taps an already-placed trap, a context panel appears. Contents to be defined — candidates include: upgrade tree, sell option, stats/info panel. Layout and interaction flow TBD.

---

## **10. Open Questions**

| Status | Question |
| :---- | :---- |
| Resolved | Title confirmed: Critter Quitters Pest Control |
| Resolved | Currency confirmed: Bounties |
| Resolved | Monetization: premium (pay upfront, all gameplay included) |
| Resolved | Director's Cut mode: removed from scope |
| Resolved | Levels: auto-generated, incrementally difficult, no hand-crafted sets |
| Resolved | Starting Bounty budget: small; introduces economy and allows initial placement choice; exact value TBD via playtesting |
| Open | Grid dimensions — constrained to fully fit mobile screen; exact cell count TBD via playtesting |
| Resolved | Blocking terrain: inert (no secondary effects); name TBD from Section 6a candidates |
| Resolved | Pathfinding: minimum one valid path always enforced; placement rejected if it would block all paths |
| Open | Trap shop UX — stat preview method (tap-to-preview, always visible, or placement preview) |
| Open | Placed trap interaction — context panel contents and layout |
| Resolved | Trap footprint: mostly 1×1; some traps use 3+ contiguous cells in irregular shapes |
| Resolved | Win/loss: pests deal fixed Property HP damage on exit by type; Property HP carries over between waves within a level, resets each new level; run ends when Property HP hits 0 |
| Resolved | Entry points: per-wave groups can spawn from left or top; early levels single entrance, later levels both |
| Resolved | Bounty rewards: per kill, varies by pest type, scales with level/wave |
| Resolved | Wave clear bonus: awarded on last pest eliminated; amount TBD/tunable |
| Open | Blocking terrain spawn rules — probability, min/max count per level |
| Open | Blocking terrain name — see Section 6a candidates |
| Open | Trap names — current names (Snap Trap, Zapper, Fogger, Glue Board) are working titles; final names TBD |
| Open | Audio — licensed tracks vs. original score; tone TBD |
| Open | Fogger AoE radius |

---

## **11. Future Pass**

The following mechanics were identified during design but deferred to a later pass. They should not block v1 development.

**Flying units** — Pests that travel through the air and ignore ground traps entirely. Requires a dedicated anti-air trap type (e.g. a bug zapper variant with aerial targeting). Candidate pest: Mosquito.

**Pest split / survival mechanic** — A pest that survives certain traps or splits into multiple smaller units on death. Candidate pest: Cockroach.

**Barrier-breaking** — A pest capable of destroying or damaging blocking terrain. Candidate pest: Mouse / Rat variant.

**Placeable ally unit** — A neutral or friendly creature the player can deploy that acts as a trap or deterrent. Candidate unit: Spider.

**Additional pests** — Slug (extremely slow, possibly damages traps), Cricket (erratic movement, hard to predict) considered for later roster expansion.

**Blocking terrain secondary effects** — Terrain objects that have passive effects on adjacent pests or traps (e.g. a leaking pipe slows pests that cross near it). Currently inert — secondary effects deferred.
