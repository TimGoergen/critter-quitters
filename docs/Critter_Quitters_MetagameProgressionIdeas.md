# Critter Quitters Pest Control: Game Design Document

This document outlines the core progression, mechanics, and structural design for **Critter Quitters Pest Control**, a mobile tower defense game featuring dynamic mazing and a "one-man service" theme.

---

## 1. Game Concept & Theme
* **Title:** Critter Quitters Pest Control
* **Theme:** A blue-collar, one-man pest control service.
* **Player Character:** Magee, the technician.
* **Arena:** Landscape-oriented household environments (Kitchens, Attics, Basements).
* **Enemies:** Various pests (Ants, Roaches, Beetles, etc.).
* **Towers:** Professional pest control gear (Snap traps, Foggers, Sticky Pads).

---

## 2. Core Progression Hierarchy

The game follows a "nested" structure to balance immediate action with long-term strategy.

| Tier | Composition | Purpose | Reward Type |
| :--- | :--- | :--- | :--- |
| **Wave** | A specific swarm of pests. | Short-term tactical puzzle. | **Bounty ($$$):** Cash used for mid-level traps/upgrades. |
| **Round** | A set of 3–5 Waves. | Combat endurance & strategy pivot. | **Roguelike Perks:** 1 of 3 random temporary buffs. |
| **Level (Contract)**| A set of 5–10 Rounds. | Strategic "World" progression. | **Paycheck:** Permanent currency for Meta-upgrades. |

---

## 3. Movement & Mazing Mechanics

### The Invalid Placement Rule
The game features a wide-open arena where pests enter from the left and exit on the right. 
* Pests always calculate and follow the **Shortest Path** to the exit.
* **Constraint:** The player cannot place a trap if it completely blocks the path from entrance to exit. The UI provides visual feedback (e.g., turning red) when a placement is invalid.

### The Move Tool ("Relocation Service")
Designed for a static, top-down mobile camera, the move tool allows Magee to adapt to changing swarms.
* **Interaction:** Drag-and-drop traps to a new location.
* **Set-Up Time:** Traps have a brief "re-arming" period after being moved before they can fire again.
* **Avatar Integration:** The player character (Magee) physically moves to the trap to relocate it, making player positioning a strategic resource.

---

## 4. Economy & Upgrade System

The game utilizes a three-tier economy to keep players engaged in different timeframes.

### A. Tactical: Bounty Cash (Mid-Wave)
* **Earned by:** Killing pests.
* **Used for:** Buying new traps or upgrading the stats (Level 2, Level 3) of existing ones.
* **Persistence:** Resets at the start of every new Level (Contract).

### B. Strategic: Roguelike Perks (End of Round)
* **Earned by:** Surviving a Round.
* **System:** A "Pick 1 of 3" randomized draft.
* **Sample Perks:**
    * *Lightweight Plastics:* Removes set-up delay on moved traps.
    * *Industrial Solvent:* Foggers leave lingering poison pools.
    * *Marathon Sprinter:* Increases Magee's movement speed.

### C. Meta: The Paycheck (End of Level)
* **Earned by:** Successful contract completion.
* **Used in:** The Work Van / HQ Shop.
* **Permanent Upgrades:** Unlocking new trap types, increasing van capacity, or buying permanent stat boosts (starting cash, rerolls).

---

## 5. Mobile Landscape Design
* **Layout:** "Thumb-friendly" UI with the Toolbelt on the right and Dashboard (Health/Wave) on the left.
* **Replayability:** * **Contract Varieties:** Different house layouts and obstacle configurations.
    * **Resistant Strains:** High-difficulty levels with pests immune to certain chemical types.
    * **Daily Gigs:** Special challenges with unique modifiers (e.g., "No-Move" challenges).
