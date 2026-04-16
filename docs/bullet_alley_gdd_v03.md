# **Bullet Alley — Game Design Document**

**Version:** Draft v0.5 **Status:** Concept / Pre-production **Platform:** Mobile (iOS / Android) / Web **Art Style:** ASCII / minimalist **Reference:** Desktop Tower Defense

---

## **Changelog**

| Version | Changes |
| :---- | :---- |
| v0.1 | Initial draft |
| v0.2 | Title confirmed: Bullet Alley |
| v0.3 | Currency confirmed: Shells |
| v0.4 | Monetization confirmed: premium. Entry/exit corrected: left+top entry, right+bottom exit. Platform: mobile+web. Director's Cut removed. Levels: auto-generated incremental difficulty. Blocking terrain added. |
| v0.5 | Roster finalised: 4 towers, 5 enemies. Build phase replaced with pre-wave countdown. Between-wave upgrade store added. ASCII aesthetic confirmed. Game structure defined: endless levels, high score, per-level arena reset. DoT system: fire and ice. Unit interaction rules defined. |

---

## **Table of Contents**

1. Overview & Premise

2. Core Loop

3. Arena & Layout

4. Tower Roster

5. Enemy Roster

6. New Mechanics

6a. Blocking Terrain

7. Progression & Economy

8. Aesthetic Direction

9. Mobile UX Considerations

10. Open Questions

---

## **1\. Overview & Premise**

Bullet Alley is a mobile tower defense game built on the open maze-building mechanic pioneered by Desktop Tower Defense (2007). The player controls no pre-defined path — instead, enemy units enter an open arena and pathfind in real time around whatever the player places. The maze is the strategy. The alley is whatever you make it.

The theme is unabashedly 80s action cinema: endless waves of thugs, runners, and B-movie heavies crossing an open killzone toward the player’s base. The player’s defensive units are action hero archetypes — each with a distinct ability set, visual identity, and signature one-liner. The tone is self-aware without being a parody.

The title works on two levels: Bullet Alley is the name of the arena the player builds and defends, and a deadpan description of what that arena becomes once the shooting starts.

| Attribute | Value |
| :---- | :---- |
| Genre | Tower defense / maze builder |
| Target audience | Males 35–55, TD veterans |
| Session length | 10–25 min per run |
| Platform | Mobile (iOS / Android) / Web |
| Monetization | Premium (pay upfront, all gameplay included) |

---

## **2\. Core Loop**

1. Wave announced — player sees incoming enemy type and count

2. Pre-wave countdown — a timer counts down before the wave begins. The player must start placing towers immediately; there is no separate idle build phase. The current enemy path is visualised on the arena. The player may trigger the wave early to receive a bonus (amount TBD).

3. Wave — enemies enter sequentially in groups; each group spawns from either the left or top entrance. Early levels use a single entrance; later levels introduce groups from both entrances within the same wave. Spacing between units is dynamic but consistent within a group. The player may continue to place, upgrade, or sell towers during the wave as Shells are earned.

4. Enemies that reach the exit deal a fixed amount of damage to the arena's HP pool based on enemy type, then disappear; arena HP reaching zero ends the run.

5. Killed enemies drop Shells based on enemy type, scaled by current level/wave; when the last enemy of the wave dies a wave clear bonus is awarded (amount TBD).

6. Between waves — the player visits the upgrade store and spends Shells on available offers before the next wave countdown begins. Repeat from step 1.

Unlike lane-based TD games, the player’s maze layout directly determines enemy pathing. Longer, more convoluted mazes increase tower exposure time. At least one valid path from an entry point to an exit point must always exist. This is enforced proactively: if placing a tower would eliminate all valid paths, the placement is rejected and the player is not permitted to confirm it.

**Unit interaction rules:** Enemies cannot affect player towers in any way. Each tower defines only its own fire rate, damage, and range — towers do not buff or debuff other towers. Towers may apply fire or ice DoT effects directly to enemies they hit.

**Targeting:** Each tower targets the enemy within its range that is farthest along the current path toward an exit — prioritising the most immediate threat to the arena.

**Projectiles:** Towers fire projectiles that travel visually across the arena toward their target. Damage is applied instantly on firing — the projectile travel is cosmetic. This keeps combat feel snappy without requiring collision-based hit detection.

**Placement during combat:** Tower placement is not locked to the build phase. The player may place, upgrade, or reposition towers at any point during a wave as Shells become available. Path visualisation updates in real time as new towers are placed. All enemies currently on the arena immediately recalculate their path when the layout changes — live rerouting applies to every active unit, not just newly spawned ones.

---

## **3\. Arena & Layout**

The arena is a flat, open killzone. Visually clean and grid-based to support touch placement on mobile. The grid resolves at a size that allows comfortable finger-tap accuracy on phones. Each level generates a fresh arena with its own layout and optional blocking terrain.

The arena is always called Bullet Alley. The name belongs to the space the player creates.

| Attribute | Value |
| :---- | :---- |
| Entry points | Left edge and top edge |
| Exit points | Right edge and bottom edge |
| Grid size | TBD |
| Pathfinding | A\* real-time |

---

## **4\. Tower Roster (Initial)**

Each tower is an action hero archetype. Naming follows action movie character conventions.

**Upgrade system:** Each tower has branching upgrade paths. Within each branch, the player purchases incremental upgrades that improve a core metric (damage, fire rate, range, or other stats). When a branch is fully upgraded, a new upgrade path unlocks — evolving the tower into a new unit type with expanded abilities. Fully evolved units can inflict damage-over-time (DoT) effects that persist on an enemy for a set duration:

| DoT Type | Behavior |
| :---- | :---- |
| Fire | Deals repeated damage ticks for a duration after the hit |
| Ice | Reduces enemy movement speed for a duration after the hit |

**DoT rules:**
- Effects do not stack — a subsequent hit of the same type refreshes the duration rather than adding a second instance
- Effects do not spread or travel; they apply only to the enemy directly hit by the attack
- Fire and Ice can coexist on the same enemy simultaneously

**Evolved unit visuals:** As a tower evolves through its upgrade tree, its ASCII character representation grows more prominent — shifting from lowercase to uppercase, increasing in visual weight, or using a bolder character variant. More advanced units look more imposing at a glance.

The upgrade tree is deep enough to give players meaningful long-term build decisions within a single run.

**Footprint:** Most towers occupy a single 1×1 cell. Some towers occupy 3 or more contiguous cells in irregular shapes (L-shapes, T-shapes, etc.). The full footprint must fit on empty, unoccupied cells for placement to be valid. Footprints are fixed and do not rotate — all towers operate in a full 360-degree arc and have no facing direction.

### **The Grunt**

**Archetype:** Basic / single-target

Cheap, reliable. Fast attack rate, low damage. The expendable backbone of any build. Upgrade path: faster fire rate or wider range.

### **The Sniper**

**Archetype:** Long range / high damage

Extreme range, very slow fire rate. Prioritizes highest-HP target. One-shots standard enemies late in upgrade path.

### **The Bomber**

**Archetype:** Area of effect / high damage

Slow attack rate, high damage per shot. Attacks deal AoE damage to all enemies in a radius around the target. Ideal for chokepoints and tightly packed groups. AoE radius TBD.

### **The Femme Fatale**

**Archetype:** Ice / area slow

Applies ice DoT to enemies in a radius — reducing their movement speed for a duration. Low cost, low footprint.

---

## **5\. Enemy Roster (Initial)**

| Name | Archetype | Behavior | Tier |
| :---- | :---- | :---- | :---- |
| The Thug | Standard | Relatively low HP, average speed. Appears in standard numbers per wave. No special mechanics. | 1 |
| The Runner | Fast / fragile | Low HP, very fast. Punishes gaps in coverage. | 2 |
| The Bruiser | Mid-tier heavy | High HP, slow movement, moderate exit damage. Uncommon — appears occasionally within standard waves. | 3 |
| The Enforcer | High-tier heavy | Very high HP, very slow movement, high exit damage. Rare — less common than The Bruiser. | 4 |
| The Heavy | Boss | Massive HP, slowest movement, highest exit damage. One per wave maximum. Designated boss unit. | Boss |

---

## **6\. New Mechanics (Beyond DTD)**

**One-liner system** — When a tower scores a kill streak, it triggers a quip. Cosmetic only but reinforces theme identity and gives feedback on performance. Delivery method (voiced or text) TBD pending audio direction.

**Repositioning cost** — Moving a placed tower costs a small Shell fee, adding weight to placement decisions without fully locking the player in.

**Selling** — Towers may be sold at any time, including during combat. Selling returns 70% of the tower's buy price. Enemies on the arena reroute immediately when a tower is removed, consistent with live rerouting on placement.

**Blocking terrain** — Each level has a chance of spawning a small number of pre-placed terrain objects at round start. These cells cannot have towers placed on them and cannot be crossed by enemies. They reshape the open arena into something irregular, forcing the player to adapt their maze strategy. See Section 6a for details.

---

## **6a\. Blocking Terrain**

Each level has a random chance of placing a small number of terrain objects in the arena before the first wave. These are permanent for the duration of the run and cannot be removed. No tower may be placed on them; no enemy may cross them.

**Name: TBD** — candidates listed below. Blocking terrain is currently inert: no secondary effects on enemies or towers. Thematically and aesthetically appropriate for the arena, present as environmental obstacles only. Secondary effects may be considered in a future pass.

| Candidate Name | Theme Fit |
| :---- | :---- |
| Wrecked Cars | Strong — classic 80s action set piece |
| Barrels | Strong — iconic action movie / gaming prop |
| Crates | Strong — warehouse/depot feel |
| Dumpsters | Good — urban action setting |
| Sandbag Piles | Good — military compound setting |

**Spawn rules (TBD):** Probability of terrain spawning per level, min/max count, placement constraints (must not block all paths, must not spawn on entry/exit edges).

---

## **7\. Progression & Economy**

Shells are earned per kill and per wave cleared — collected from the ground after each engagement. Tower costs follow a DTD-style tiered pricing model — cheap units available early, specialist units gated by cost. A starting budget of Shells is granted at run start.

**Structure:** The game is endless — there is no final level. The player reaches for a high score determined by total enemies killed and the highest level reached.

**Levels** are auto-generated and increase incrementally in difficulty. Each level begins with a freshly generated arena, including any blocking terrain for that level (see Section 6a). The arena layout remains fixed for the entire level. Each level contains a dynamic number of waves that increases as levels progress — early levels have fewer waves, later levels have more.

**Waves** escalate in difficulty within each level: enemy count, type mix, and exit damage increase across waves. Entry point variety also expands as levels progress.

**Tower persistence:** Each level starts fresh. The arena is empty and the player is given the opening Shell budget at the start of every level. No towers carry over between levels.

**Arena HP:** Each level has its own unique HP value, scaled to the difficulty of that level. Arena HP does not carry between levels — it resets fully at the start of each new arena. Within a level, all damage is permanent. Certain consumables can restore arena HP during a level.

**Between-wave upgrade store:** After each wave, the player visits the upgrade store. There is no timer — the player may take as long as needed. The store presents 3 or 4 randomly selected items. The player may:

- **Purchase** one or more items by spending Shells — applies immediately
- **Reroll** the item list by spending Shells — replaces all current offers with a new random selection. Reroll cost starts at a fixed base amount each store visit and increases by a fixed increment with each use (e.g. 5 → 10 → 15 → ...). The cost resets at the start of every between-wave store visit. Exact base cost and increment TBD via playtesting.
- **Skip** — proceed to the next wave countdown without buying anything

All purchases apply immediately. There is no inventory. Upgrade types include:

| Type | Effect |
| :---- | :---- |
| Stat upgrade | Permanent boost for the remainder of the run (e.g. increased tower damage, improved Shell income) |
| Immediate payout | One-time grant of Shells, arena HP, or other resource |

The store creates a meaningful Shell-spending decision each wave — the player must weigh tower investment vs. upgrades vs. saving Shells for a reroll.

The name does quiet thematic work: the arena is called Bullet Alley, the currency is Shells, and the player is literally spending spent casings to hire the people who made them.

| Attribute | Value |
| :---- | :---- |
| Currency | Shells |
| Starting budget | Small — enough to introduce the economy and allow a meaningful initial build choice; exact amount TBD via playtesting |
| Sell value | 70% of buy price |
| Arena HP | Starting value is low enough that a small number of enemies reaching the exit is threatening; exact value TBD via playtesting |
| Exit damage | Per enemy type, scales upward each wave. Wave 1 is balanced so that if all enemies reached the exit uncontested, they would deal twice the arena's starting HP in total damage — the player must stop at least half to survive |
| Shell reward | Per kill, varies by enemy type; scales with level/wave |
| Wave clear bonus | Awarded on last enemy kill per wave; amount TBD (to be tuned) |
| High score | Composite of total enemies killed and highest level reached; exact formula TBD |

---

## **8\. Aesthetic Direction**

The game is intentionally graphically minimal. Game elements — towers, enemies, terrain, projectiles — are represented by ASCII characters rendered as physical 3D objects. Characters are not flat sprites; they exist in three-dimensional space and move with physical weight and smoothness. An enemy marching across the arena tilts into turns, bobs as it walks, and reacts physically when hit. Projectiles arc or travel through 3D space. Towers have presence and idle animation.

ASCII characters are rendered as flat planes (billboards) that always face the camera. They move smoothly through 3D space — tilting, rotating, and reacting physically — while remaining fully readable as characters from the top-down view. This gives the game a demoscene / experimental quality that is visually distinctive without requiring conventional artwork.

**Death animation:** On death, a unit flashes briefly and disappears. No ragdoll or debris.

**Idle animation:** Player-placed towers may rotate slowly or pulse while idle — reinforcing their physical presence between shots. Exact behavior defined per tower type during implementation.

**Color:** Colored ASCII — a simple, constrained palette where each element category (enemy type, tower type, terrain, projectile) has a consistent color identity. Background is dark. Grid lines are not rendered. Each level uses its own muted complementary palette — colors shift as the player progresses, giving each level a distinct mood without loud or saturated hues.

**Cursor:** During placement, the cursor highlights the full grid cell under the player's finger/pointer as a single highlighted block. No visible grid otherwise.

**HUD:** Simple geometric shapes — not ASCII. Clean, readable UI panels for Shell count, arena HP, wave info, and speed controls.

**Camera:** Fixed top-down orthographic. Grid aligns cleanly to screen space; touch targeting is unambiguous.

**Font:** JetBrains Mono.

**Key aesthetic tags:** ASCII-as-physical-objects, colored, dark background, 3D smooth movement, minimal HUD.

---

## **9\. Mobile UX Considerations**

* Grid cells must meet minimum touch target size (44×44pt iOS guideline)

* Tower placement uses tap-to-select, tap-grid-cell-to-place flow — no drag and drop

* Pre-wave countdown is timer-limited — player should begin placing towers immediately when the countdown starts

* Speed controls (1×, 2×, pause) always visible during combat phase

* Portrait orientation primary; landscape optional

* Shell count always visible in HUD — tower picker never more than one tap away

* No internet required for core gameplay

**Arena scrolling / camera**

Arena size grows as levels progress and will exceed the visible screen area at higher levels. The viewport must support panning across the arena. Primary input is touch-screen, which creates a gesture conflict: a pan gesture and a tower-placement tap occur on the same surface.

Proposed resolution:

* **Short tap** — place/select tower on the tapped cell
* **Press-and-drag** — pan the viewport
* A threshold (e.g. 8–10px movement) distinguishes a tap from a drag before committing the action

Additional considerations:

* Off-screen enemy indicators — directional arrows pinned to the viewport edges point toward enemies outside the current view. No minimap. Arrows carry no explicit text (no count or type label) but scale in size/intensity with the threat level of off-screen enemies. Indicators are visible during combat phase only — not during build phase.
* HUD elements (tower picker, Shell count, wave info, speed controls) must remain fixed on screen and outside the scrollable arena viewport — never scroll away
* Pinch-to-zoom (optional) — allows the player to zoom out for a strategic overview; minimum zoom level must keep cells tappable

**Tower shop UX — open**

How the player views tower stats before purchasing. Candidates:

* **Tap to preview** — tapping a tower in the shop opens a stat card before entering placement mode
* **Always visible** — stats shown inline in the shop without needing to tap
* **Placement preview** — stats only visible once the player enters placement mode with the tower ghosted on the grid

**Placed tower interaction — open**

When the player taps an already-placed tower, a context panel appears. Contents to be defined — candidates include: upgrade tree, sell option, stats/info panel. Layout and interaction flow TBD.

---

## **10\. Open Questions**

| Status | Question |
| :---- | :---- |
| Resolved | Title confirmed: Bullet Alley |
| Resolved | Currency confirmed: Shells |
| Resolved | Monetization: premium (pay upfront, all gameplay included) |
| Resolved | Director's Cut mode: removed from scope |
| Resolved | Levels: auto-generated, incrementally difficult, no hand-crafted sets |
| Resolved | Starting Shell budget: small; introduces economy and allows initial build choice; exact value TBD via playtesting |
| Open | Grid dimensions - constrained to fully fit mobile screen; exact cell count TBD via playtesting |
| Resolved | Blocking terrain: inert (no secondary effects); name TBD from Section 6a candidates |
| Resolved | Pathfinding: minimum one valid path always enforced; placement rejected if it would block all paths |
| Open | Tower shop UX — stat preview method (tap-to-preview, always visible, or placement preview) |
| Open | Placed tower interaction — context panel contents and layout |
| Resolved | Tower footprint: mostly 1x1; some towers use 3+ contiguous cells in irregular shapes |
| Resolved | Win/loss: enemies deal fixed HP damage on exit by type; arena HP carries over between waves within a level, resets each new level; run ends when arena HP hits 0 |
| Resolved | Entry points: per-wave groups can spawn from left or top; early levels single entrance, later levels both |
| Resolved | Shell rewards: per kill, varies by enemy type, scales with level/wave |
| Resolved | Wave clear bonus: awarded on last enemy kill; amount TBD/tunable |
| Open | Blocking terrain spawn rules - probability, min/max count per level |
| Open | Audio - licensed 80s-adjacent tracks vs. original synth score? |