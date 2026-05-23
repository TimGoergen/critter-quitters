# Boost Playtest Config

All values here are the authoritative source for boost balance during playtesting.
Edit freely — game code is only updated when you explicitly say "sync config to game."

The `enum_name` field is the key used during sync. **Do not change it.**

Boosts have three upgrade stats: Range (stat A), primary bonus (stat B), secondary bonus (stat C).
Two-stat boosts (Pheromone, Compressor) have no `stat_c_increment` or `capacity` row.
Perishable boosts (Air Freshener, Quarantine Marker) are destroyed when capacity reaches zero.

Upgrade cost applies uniformly to all three stats (one cost table per boost).
`range_upgrade_factor` is a fraction of base range added per range upgrade level.

---

## PHEROMONE_DISPENSER

| Property | Value |
|---|---|
| enum_name | PHEROMONE_DISPENSER |
| display_name | Pheromone Dispenser |
| description | Increases damage dealt by all traps within its aura. |
| cost | 50 |
| range | 4.0 |
| is_perishable | false |
| damage_bonus | 0.25 |
| upgrade_costs | 15, 25, 40 |
| stat_b_increment | 0.08 |
| range_upgrade_factor | 0.10 |

---

## COMPRESSOR

| Property | Value |
|---|---|
| enum_name | COMPRESSOR |
| display_name | Compressor |
| description | Increases the fire rate of all traps within its aura. |
| cost | 50 |
| range | 4.0 |
| is_perishable | false |
| fire_rate_bonus | 0.20 |
| upgrade_costs | 15, 25, 40 |
| stat_b_increment | 0.07 |
| range_upgrade_factor | 0.10 |

---

## CASH_REGISTER

`income_per_wave` is Bug Bucks awarded at wave start regardless of kills.
`kill_bonus` is Bug Bucks per kill that occurs inside the aura.

| Property | Value |
|---|---|
| enum_name | CASH_REGISTER |
| display_name | Cash Register |
| description | Earns Bug Bucks each wave and pays a bonus per kill inside its aura. |
| cost | 45 |
| range | 5.0 |
| is_perishable | false |
| income_per_wave | 5 |
| kill_bonus | 2 |
| upgrade_costs | 20, 35, 55 |
| stat_b_increment | 3 |
| stat_c_increment | 1 |
| range_upgrade_factor | 0.10 |

---

## AIR_FRESHENER

`reduction` is the fraction of infestation absorbed per exit event (0.0–1.0).
`capacity` is total infestation units absorbed before the boost is destroyed.
Stat B upgrades increase `reduction`; stat C upgrades increase `capacity`.

| Property | Value |
|---|---|
| enum_name | AIR_FRESHENER |
| display_name | Air Freshener |
| description | Absorbs infestation from pests that escape through its aura. Perishable — has finite capacity. |
| cost | 35 |
| range | 3.0 |
| is_perishable | true |
| reduction | 0.50 |
| capacity | 50.0 |
| upgrade_costs | 15, 25, 40 |
| stat_b_increment | 0.10 |
| stat_c_increment | 25.0 |
| range_upgrade_factor | 0.10 |

---

## QUARANTINE_MARKER

`restore_per_kill` is infestation points restored per kill inside the aura.
`capacity` is total infestation restored before the boost is destroyed.
Stat B upgrades increase `restore_per_kill`; stat C upgrades increase `capacity`.

| Property | Value |
|---|---|
| enum_name | QUARANTINE_MARKER |
| display_name | Quarantine Marker |
| description | Restores infestation for every kill inside its aura. Perishable — has finite capacity. |
| cost | 40 |
| range | 4.0 |
| is_perishable | true |
| restore_per_kill | 2.0 |
| capacity | 80.0 |
| upgrade_costs | 15, 25, 40 |
| stat_b_increment | 1.0 |
| stat_c_increment | 40.0 |
| range_upgrade_factor | 0.10 |
