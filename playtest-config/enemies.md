# Enemy Playtest Config

All values here are the authoritative source for enemy balance during playtesting.
Edit freely — game code is only updated when you explicitly say "sync config to game."

The `enum_name` field is the key used during sync. **Do not change it.**

---

## Global Scaling

| Property | Value | Notes |
|---|---|---|
| HP_WAVE_SCALE | 1.02 | Additional HP added per wave number (wave 1 = base + 1.02, wave 10 = base + 10.2) |

---

## ANT

| Property | Value |
|---|---|
| enum_name | ANT |
| display_name | Ant |
| hp | 10 |
| speed | 2.5 |
| infestation | 1.0 |
| bounty | 10 |
| is_flying | false |
| bug_bucks_steal | 0 |
| notes | Basic ground unit. Fast, low HP. |

---

## GNAT

| Property | Value |
|---|---|
| enum_name | GNAT |
| display_name | Gnat |
| hp | 5 |
| speed | 5.6 |
| infestation | 0.5 |
| bounty | 5 |
| is_flying | false |
| bug_bucks_steal | 0 |
| notes | Fastest ground unit. Glass cannon — dies to almost anything but hard to catch. |

---

## CRICKET

| Property | Value |
|---|---|
| enum_name | CRICKET |
| display_name | Cricket |
| hp | 12 |
| speed | 3.2 |
| infestation | 1.0 |
| bounty | 15 |
| is_flying | false |
| bug_bucks_steal | 0 |
| notes | Slightly tankier than Ant, medium speed. |

---

## BEETLE

| Property | Value |
|---|---|
| enum_name | BEETLE |
| display_name | Beetle |
| hp | 25 |
| speed | 1.5 |
| infestation | 3.0 |
| bounty | 15 |
| is_flying | false |
| bug_bucks_steal | 0 |
| notes | Slow and moderately tough. High infestation on exit. |

---

## COCKROACH

| Property | Value |
|---|---|
| enum_name | COCKROACH |
| display_name | Cockroach |
| hp | 80 |
| speed | 1.0 |
| infestation | 5.0 |
| bounty | 25 |
| is_flying | false |
| bug_bucks_steal | 0 |
| notes | Tanky, slow. Significant infestation threat if it reaches the exit. |

---

## MOSQUITO

Flying enemies travel in a straight line from entrance to exit, ignoring the path and all ground obstacles.

| Property | Value |
|---|---|
| enum_name | MOSQUITO |
| display_name | Mosquito |
| hp | 15 |
| speed | 5.5 |
| infestation | 3.0 |
| bounty | 8 |
| is_flying | true |
| bug_bucks_steal | 0 |
| notes | Only flying enemy. Bypasses most traps. Fly Strip Launcher and Snap Trap can hit it. |

---

## MOUSE

Boss every 10 waves (alternates with Rat King every 20 waves).
Steals Bug Bucks from the player on exit in addition to dealing infestation damage.

| Property | Value |
|---|---|
| enum_name | MOUSE |
| display_name | Mouse |
| hp | 200 |
| speed | 0.6 |
| infestation | 10.0 |
| bounty | 50 |
| is_flying | false |
| bug_bucks_steal | 20 |
| notes | Boss-tier. Very high HP and infestation. Slow enough to focus fire, but economically punishing if it exits. |

---

## RAT_KING

Mega-boss every 20 waves. Splits into 3 RATs on death.

| Property | Value |
|---|---|
| enum_name | RAT_KING |
| display_name | Rat King |
| hp | 600 |
| speed | 0.35 |
| infestation | 20.0 |
| bounty | 150 |
| is_flying | false |
| bug_bucks_steal | 0 |
| notes | Mega-boss. Extreme HP and infestation. Splits into 3 Rats on death. Near-certain run loss if it exits. |

---

## RAT

Mid-tier ground enemy. Spawned from a RAT_KING death split; also enters the standard wave pool from wave 15 so the player encounters it before ever facing the Rat King.

| Property | Value |
|---|---|
| enum_name | RAT |
| display_name | Rat |
| hp | 65 |
| speed | 1.3 |
| infestation | 4.0 |
| bounty | 25 |
| is_flying | false |
| bug_bucks_steal | 0 |
| notes | Mid-tier enemy. Tanky, moderate speed. Spawned by Rat King on death; also appears in regular waves from wave 15. |

---

## COCKROACH_NYMPH

**Planned — not yet implemented in code.**
Splits into two COCKROACH_MINI on death. The split is hardcoded behavior — not driven by config.

| Property | Value |
|---|---|
| enum_name | COCKROACH_NYMPH |
| display_name | Cockroach Nymph |
| hp | 80 |
| speed | 1.5 |
| infestation | 8.0 |
| bounty | 25 |
| is_flying | false |
| bug_bucks_steal | 0 |
| notes | Splits into 2× COCKROACH_MINI on death. Very high infestation if it exits. |

---

## COCKROACH_MINI

**Planned — not yet implemented in code.**
Spawned from a COCKROACH_NYMPH split. Not placed directly in waves.

| Property | Value |
|---|---|
| enum_name | COCKROACH_MINI |
| display_name | Cockroach Mini |
| hp | 20 |
| speed | 2.0 |
| infestation | 2.0 |
| bounty | 5 |
| is_flying | false |
| bug_bucks_steal | 0 |
| notes | Spawned by COCKROACH_NYMPH death split. Not placed directly in waves. |
