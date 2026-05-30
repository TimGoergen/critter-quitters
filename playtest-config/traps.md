# Trap Playtest Config

All values here are the authoritative source for trap balance during playtesting.
Edit freely — game code is only updated when you explicitly say "sync config to game."

The `enum_name` field is the key used during sync. **Do not change it.**

---

## Global Upgrade Factors

These apply uniformly to all traps.

| Property | Value | Notes |
|---|---|---|
| UPGRADE_DAMAGE_FACTOR | 0.20 | +20% of base damage per level |
| UPGRADE_RANGE_FACTOR | 0.10 | +10% of base range per level |
| UPGRADE_FIRE_RATE_FACTOR | 0.08 | −8% of base cooldown per level (faster shots) |
| CRIT_CHANCE_BASE | 0.00 | Starting crit chance; 0 = dormant until upgraded |
| CRIT_DAMAGE_BONUS_BASE | 0.25 | +25% damage multiplier on a crit |
| UPGRADE_CRIT_CHANCE_PER_LEVEL | 0.02 | +2% crit chance per level |
| UPGRADE_CRIT_DAMAGE_PER_LEVEL | 0.25 | +25% crit damage bonus per level |
| MAX_UPGRADE_LEVEL | 3 | Maximum upgrade levels per stat |
| FULL_UPGRADE_BONUS | 0.075 | +7.5% to all stats when every stat reaches max |

---

## SNAP_TRAP

| Property | Value |
|---|---|
| enum_name | SNAP_TRAP |
| display_name | Snap Trap |
| description | Targets the nearest pest in range. Fast fire rate, low damage. Can hit flying pests. |
| cost | 25 |
| damage | 5.0 |
| range | 5.6 |
| cooldown | 1.0 |
| upgrade_costs | 20, 30, 50 |

---

## ZAPPER

| Property | Value |
|---|---|
| enum_name | ZAPPER |
| display_name | Zapper |
| description | Targets the pest farthest along the path. Slow rate, high damage. Cannot hit flying pests. |
| cost | 75 |
| damage | 30.0 |
| range | 9.6 |
| cooldown | 2.5 |
| upgrade_costs | 50, 75, 120 |

---

## FOGGER

| Property | Value |
|---|---|
| enum_name | FOGGER |
| display_name | Fogger |
| description | Fires an expanding cloud that hits all pests from closest to farthest. Cannot hit flying pests. |
| cost | 60 |
| damage | 3.0 |
| range | 4.0 |
| cooldown | 2.2 |
| upgrade_costs | 40, 60, 100 |

---

## GLUE_BOARD

Passive trap — cooldown is always 0.0 and is not editable.
`damage` here is the base adhesion factor (slow strength). The `adhesion_levels` table
overrides this value per upgrade level, so edit `adhesion_levels` to tune slow strength.
`duration_levels` controls how long the slow lingers after an enemy leaves the radius.

| Property | Value |
|---|---|
| enum_name | GLUE_BOARD |
| display_name | Glue Board |
| description | Continuously slows every ground pest inside its range. Passive — no firing. Cannot hit flying pests. |
| cost | 45 |
| damage | 0.20 |
| range | 4.8 |
| cooldown | 0.0 |
| upgrade_costs | 30, 45, 70 |
| adhesion_levels | 0.20, 0.30, 0.40, 0.50 |
| duration_levels | 3.0, 4.5, 6.0, 8.0 |

---

## FLY_STRIP_LAUNCHER

`cloud_duration` is how long the sticky cloud persists after impact.
`adhesion` is the base slow factor applied to flying enemies in the cloud.
`adhesion_levels` overrides `adhesion` per third-stat upgrade level.

| Property | Value |
|---|---|
| enum_name | FLY_STRIP_LAUNCHER |
| display_name | Fly Strip Launcher |
| description | Targets flying pests only. Releases a sticky cloud on impact that slows and damages. |
| cost | 65 |
| damage | 2.0 |
| range | 5.0 |
| cooldown | 5.0 |
| cloud_duration | 3.0 |
| adhesion | 0.30 |
| upgrade_costs | 40, 65, 100 |
| adhesion_levels | 0.30, 0.40, 0.55, 0.70 |

---

## BAIT_STATION

Passive trap — cooldown is always 0.0 and is not editable.
`pulse_interval` is seconds between poison pulses (independent of cooldown).
`poison_damage_per_tick` is damage per tick of the DoT applied after each pulse.
`poison_tick_rate` is seconds between DoT ticks.
`poison_duration_levels` overrides the base `poison_duration` per duration upgrade level.

| Property | Value |
|---|---|
| enum_name | BAIT_STATION |
| display_name | Bait Station |
| description | Passable by enemies. Pulses poison onto every pest in range, dealing damage over time. |
| cost | 40 |
| damage | 3.0 |
| range | 3.5 |
| cooldown | 0.0 |
| pulse_interval | 4.0 |
| poison_damage_per_tick | 1.5 |
| poison_duration | 3.0 |
| poison_tick_rate | 0.5 |
| upgrade_costs | 30, 45, 70 |
| poison_duration_levels | 3.0, 4.5, 6.0, 8.0 |
