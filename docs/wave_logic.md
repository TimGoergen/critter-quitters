# Wave Logic Reference

Critter Quitters — live code snapshot, June 2026.

---

## Enemy Stats

Base values are fixed per enemy type. Only HP scales with wave progression (see below).

| Enemy | Base HP | Speed (cells/s) | Infestation | Bounty (BB) | XP | Size (cells) | Notes |
|:------|--------:|----------------:|------------:|------------:|---:|-------------:|:------|
| Gnat | 5 | 5.6 | 4.0 | 3 | 1 | 1.6 | Fastest; tutorial enemy |
| Ant | 10 | 2.5 | 8.0 | 6 | 2 | 2.0 | Baseline unit |
| Cricket | 12 | 3.2 | 8.0 | 10 | 2 | 1.8 | |
| Rat | 65 | 1.3 | 22.0 | 20 | 6 | 2.4 | Also spawned by Rat King death |
| Beetle | 25 | 1.5 | 20.0 | 20 | 5 | 2.4 | |
| Mosquito | 15 | 5.5 | 18.0 | 10 | 3 | 1.8 | Flying; ignores pathfinder |
| Cockroach | 80 | 1.0 | 35.0 | 35 | 8 | 2.6 | |
| Mouse | 200 | 0.6 | 60.0 | 60 | 20 | 3.2 | Boss; steals 20 BB on exit |
| Rat King | 600 | 0.35 | 100.0 | 180 | 40 | 3.8 | Mega-boss; splits into 3 Rats on death |

---

## HP Scaling

HP increases by **30% per 5 waves** (applied at spawn time):

```
max_hp = base_hp × (1.0 + floor(wave / 5) × 0.3)
```

| Wave band | Multiplier | Ant HP | Cockroach HP | Mouse HP |
|:----------|:----------:|-------:|-------------:|---------:|
| 1–4 | 1.0× | 10 | 80 | 200 |
| 5–9 | 1.3× | 13 | 104 | 260 |
| 10–14 | 1.6× | 16 | 128 | 320 |
| 15–19 | 1.9× | 19 | 152 | 380 |
| 20–24 | 2.2× | 22 | 176 | 440 |
| 25–29 | 2.5× | 25 | 200 | 500 |

Speed, bounty, XP, and infestation value do **not** scale with wave number.

---

## Wave Composition

### Wave size

10 enemies per wave. Configurable in the debug dialog.

### Wave 1

Always 100% Gnats — acts as a tutorial wave with no real threat.

### Boss waves (every 10th wave)

Even 10-wave cycles (wave 10, 30, 50, …) spawn **Mouse**.  
Odd 10-wave cycles (wave 20, 40, 60, …) spawn **Rat King**.

Boss waves still contain 10 enemies total. The boss is included in that count.

### Enemy unlock schedule

New enemy types enter the spawn pool at specific waves:

| Wave | Enters pool |
|-----:|:------------|
| 1 | Gnat |
| 2 | Ant |
| 3 | Cricket, Mosquito (if player has an anti-air trap) |
| 5 | Beetle |
| 7 | Gnat removed |
| 8 | Cockroach |

### Spawn pool weighting

Each non-boss wave draws enemies from a weighted pool. Entries per type:

| Enemy | Pool weight |
|:------|:-----------:|
| Ant | 3 |
| Gnat | 3 |
| Cockroach | 3 |
| Cricket | 2 |
| Beetle | 2 |
| Mosquito | 1 |

Higher weight = more frequent appearance within a wave.

### Example pools

| Wave | Active pool |
|-----:|:------------|
| 2 | Ant ×3, Gnat ×3 |
| 4 | Ant ×3, Gnat ×3, Cricket ×2 |
| 7 | Ant ×3, Cricket ×2, Beetle ×2 |
| 10 | Mouse (boss wave) |
| 12 | Ant ×3, Cricket ×2, Beetle ×2, Cockroach ×3 |
| 20 | Rat King (boss wave) |

---

## Spawn Timing

```
SPAWN_INTERVAL      = 0.36 s   (delay before first enemy of each wave)
WAVE_COUNTDOWN      = 5 s      (between-wave pause)
```

The gap between individual enemies is dynamic — it depends on enemy size and speed so that enemies don't visually stack on the path:

```
gap_seconds = (visual_size + 0.4) / enemy_speed
```

Larger or slower enemies naturally space further apart; small fast enemies (Gnat, Mosquito) pack tighter.

---

## Entrance & Despawn

```
Grid size:   41 × 29 cells
Entrance:    column 0,  rows 13–15  (randomly chosen per spawn)
Exit:        column 40, rows 13–15
Spawn cell:  (-1, 14)    (one cell off-screen left)
Despawn cell: (41, 14)   (one cell off-screen right)
```

Enemies randomly pick one of the 3 entrance rows so they don't all march single-file.

---

## Rat King Split

On death, the Rat King spawns 3 Rats at the kill cell with a staggered delay:

- Rat 0: immediate
- Rat 1: +0.4 s
- Rat 2: +0.8 s

The stagger ensures the active-enemy count never briefly hits zero (which would trigger wave-end logic prematurely) and gives the spawned Rats slight visual separation.

---

## XP & Level-Up

Kill XP is fixed per enemy type (see stats table). Level-up thresholds grow geometrically:

```
xp_to_level(n) = floor(20 × 1.03^n)
```

| Level | XP required |
|------:|------------:|
| 1 | 20 |
| 2 | 21 |
| 3 | 22 |
| 5 | 23 |
| 10 | 27 |
| 20 | 36 |
| 30 | 49 |

Design target: one level-up roughly every 2–4 waves in the early game, slowing as the run progresses.

---

## Early-Send Bonus

Players can send the next wave early during the between-wave countdown. The bonus is:

```
bonus = seconds_remaining × early_wave_bonus_rate   (per wave sent)
```

`early_wave_bonus_rate` is set each wave. A wave multiplier (×1 / ×5 / ×10) scales the total payout when sending multiple waves at once.

---

## Economy Constants

| Constant | Value |
|:---------|------:|
| Starting Bug Bucks | 100 |
| Infestation threshold (run ends) | 20 pts (= 100% bar) |
| Trap sell refund | 70% of buy price |

---

## What Does Not Scale

The following are **constant** across all waves and all difficulty settings:

- Enemy speed
- Bug Bucks bounty per kill
- XP per kill
- Infestation value per escape
- Spawn gap formula coefficients
- Wave size (10 enemies)
- Boss rotation pattern
