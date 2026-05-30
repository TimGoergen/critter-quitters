# Level-Up Upgrade Playtest Config

All values here are the authoritative source for level-up upgrade balance during playtesting.
Edit freely — game code is only updated when you explicitly say "sync config to game."

The `id` field is the key used during sync. **Do not change it.**

Level-up upgrades appear when the player gains an XP level. The screen pauses, presents
three randomly chosen cards, and the player picks one. Cards come in two categories:

- **Campaign buffs** — global effects that apply to all traps for the rest of the run.
- **Equipment upgrades** — type-wide free upgrades that apply to a specific placed trap type
  (and all future placements of that type). These are drawn from a separate pool from the
  paid Bug Bucks upgrades, so a stat can be offered here even if already paid-maxed.

---

## Tier Probabilities

Each card rolls its tier independently before its content is chosen.

| Tier | ID | Roll range | Probability |
|---|---|---|---|
| Rare | 2 | < 0.01 | 1% |
| Professional | 1 | 0.01 – 0.16 | 15% |
| Common | 0 | 0.16 – 1.0 | 84% |

---

## Equipment Upgrade Rules

Equipment cards target a specific trap type present on the arena. One type is chosen at
random from all placed types that still have at least one stat below the free-upgrade cap.

| Property | Value | Notes |
|---|---|---|
| FREE_MAX_LEVEL | 3 | Max free upgrades per stat per trap type |
| equip_display_pct_common | 5 | "+5%" shown on Common equipment cards |
| equip_display_pct_professional | 10 | "+10%" shown on Professional equipment cards |
| equip_display_pct_rare | 20 | "+20%" shown on Rare equipment cards |
| equip_vs_campaign_chance | 0.50 | Probability of attempting an equipment card first |

**Eligible stats per trap type:**

| Trap type | Available stats |
|---|---|
| Active traps (Snap Trap, Zapper, Fogger, Fly Strip Launcher) | damage, range, fire_rate, crit_chance, crit_dmg |
| Passive traps (Glue Board, Bait Station) | damage, range, duration, crit_chance, crit_dmg |

`duration` replaces `fire_rate` for passive traps.
`crit_chance` and `crit_dmg` are offered on all trap types for consistency, even though
crits have no mechanical effect on Glue Board (the stats are dormant until the crit system
applies to that trap type in a future pass).

---

## Campaign Buffs

Eight buffs are in the pool. Each level-up draws three unique cards; the same id cannot
appear twice in one level-up draw. Magnitudes are indexed by tier: [Common, Professional, Rare].

---

### dmg_all — Extermination Formula

Applies a global damage multiplier to every placed trap and all future placements.
Stacks additively with Pheromone Dispenser boosts and per-trap Bug Bucks upgrades.

| Property | Value |
|---|---|
| id | dmg_all |
| title | Extermination Formula |
| stat_name | Damage |
| impact_template | +%s%% Damage to all traps |
| magnitudes | 0.05, 0.10, 0.20 |
| display_values | +5%, +10%, +20% |

---

### range_all — Extended Reach

Applies a global range multiplier to every placed trap and all future placements.
Larger range means enemies spend more time inside each trap's kill zone.

| Property | Value |
|---|---|
| id | range_all |
| title | Extended Reach |
| stat_name | Range |
| impact_template | +%s%% Range for all traps |
| magnitudes | 0.05, 0.10, 0.20 |
| display_values | +5%, +10%, +20% |

---

### firerate_all — Hair Trigger

Applies a global fire rate multiplier to every placed trap and all future placements.
Stacks with Compressor boosts and per-trap fire rate upgrades.

| Property | Value |
|---|---|
| id | firerate_all |
| title | Hair Trigger |
| stat_name | Fire Rate |
| impact_template | +%s%% Fire Rate for all traps |
| magnitudes | 0.05, 0.10, 0.20 |
| display_values | +5%, +10%, +20% |

---

### crit_chance_all — Sharpened Instincts

Adds a flat crit chance bonus to every placed trap and all future placements.
Applies directly regardless of each trap's own upgrade level — a trap at 0% crit chance
becomes 2%/4%/8% immediately after selection. This bonus stacks additively with per-trap
Bug Bucks crit chance upgrades.

| Property | Value |
|---|---|
| id | crit_chance_all |
| title | Sharpened Instincts |
| stat_name | Crit Chance |
| impact_template | +%s%% Crit Chance for all traps |
| magnitudes | 0.02, 0.04, 0.08 |
| display_values | +2%, +4%, +8% |

---

### crit_dmg_all — Lethal Potency

Increases the crit damage multiplier for every placed trap and all future placements.
At base, a crit deals 1.25× damage (25% bonus). Each level of this buff adds to that bonus.
Combines with per-trap Crit Damage Bug Bucks upgrades.

| Property | Value |
|---|---|
| id | crit_dmg_all |
| title | Lethal Potency |
| stat_name | Crit Damage |
| impact_template | +%s%% Crit Damage bonus |
| magnitudes | 0.10, 0.20, 0.40 |
| display_values | +10%, +20%, +40% |

---

### bucks_all — Invoice Padding

Multiplies the Bug Bucks payout from every kill, including boss splits and spawned units.
Applies at the moment of kill; does not retroactively change already-earned bucks.

| Property | Value |
|---|---|
| id | bucks_all |
| title | Invoice Padding |
| stat_name | Bug Bucks |
| impact_template | +%s%% Bug Bucks per kill |
| magnitudes | 0.10, 0.20, 0.40 |
| display_values | +10%, +20%, +40% |

---

### infestation_heal — Hazmat Protocol

Each kill reduces the Infestation Level by a small fraction of the bar.
Magnitudes are raw fractions of the 0.0–1.0 internal infestation value.
Display values are multiplied by 100 so they read as bar-percentage (e.g. 0.002 → "−0.2% bar per kill").

The card text in code states "An escaped Ant fills the bar by 5%." Verify this against the
live infestation scaling before tuning these magnitudes — the displayed percentage depends
on how INFESTATION_MAX maps to the visible 0–100% bar at the time of playtesting.

| Property | Value |
|---|---|
| id | infestation_heal |
| title | Hazmat Protocol |
| stat_name | Infestation |
| impact_template | -%s%% bar per kill |
| magnitudes | 0.002, 0.004, 0.008 |
| display_values | −0.2%, −0.4%, −0.8% bar per kill |
| display_format | one decimal place (%.1f) |

---

### upgrade_discount — Bulk Procurement

Reduces the Bug Bucks cost of all future trap and boost upgrades by a percentage.
Applies immediately to all subsequent upgrade purchases in the run.
Does not retroactively refund past upgrades.

| Property | Value |
|---|---|
| id | upgrade_discount |
| title | Bulk Procurement |
| stat_name | Upgrade Costs |
| impact_template | -%s%% Upgrade Costs |
| magnitudes | 0.05, 0.10, 0.20 |
| display_values | −5%, −10%, −20% |

---

## Notes for Playtesting

- All three cards are de-duplicated: the same `id` cannot appear twice in one level-up draw.
- Equipment cards are attempted first with 50% probability; if no eligible trap type exists,
  a campaign card is used instead.
- Campaign card pool shuffles randomly each draw; first non-duplicate entry wins.
- If the pool is exhausted (unlikely with 8 entries and only 3 draws), the fallback is
  `dmg_all` at Common tier.
- Equipment upgrade display is always relative (+5%/+10%/+20% of current value), not absolute,
  because two traps of the same type may have different absolute stats from prior Bug Bucks upgrades.
