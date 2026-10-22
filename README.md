# Party Survivors (prototype)

Lead a party of three heroes through a horde. Steer one, the other two fight at your heels, and swap who leads at any moment.

This is **milestone 1**: a grey-box prototype to answer one question — is steering a party through a crowd fun?

## How to play it

1. Install **Godot 4.7** (standard version) from godotengine.org.
2. Open Godot, choose **Import**, and select this folder's `project.godot`.
3. Press **F5** (or the ▶ Play button, top right).

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | WASD or arrow keys | Left stick |
| Aim (the leader faces it) | Mouse | Right stick |
| Leader's skills | Q / E | Left bumper / left trigger |
| Leader's ultimate | R | Right trigger |
| Swap leader | Space or Shift | A or right bumper |
| Pick a level-up card | 1 / 2 / 3 or click | X / Y / B |
| Reroll / banish (level-up screen) | F / B | |
| Restart after a run | Enter | Start |

Fallen heroes get back up if the leader stands next to them for 3 seconds.

## How the party behaves

- **The leader** is yours: they face your mouse, and their basic attack fires where you aim.
- **Followers** hunt the nearest enemies, but only inside the leash (the faint circle, 8 metres around the leader). Past it, they run back.
- **The healer (Kheiron)** goes to whichever ally has the lowest health percentage, and otherwise stays back and fires from range.
- **Badly hurt followers** (below 35% health) stop hunting and fall back behind the leader.

Tuning numbers live at the top of `scripts/party.gd` (`LEASH`, `HEAL_SEEK_BELOW`, `RETREAT_BELOW`).

## The heroes (grey-box versions)

Basic attacks fire on their own at each hero's attack speed. The leader's Q, E and R are yours to cast. Followers cast Q and E the moment they'd do something; **only the leader can use an ultimate**, so swap a hero in to use theirs. Ultimates start each run half charged.

Enemies strike in distinct blows (once a second each, after a short wind-up).

**Solenne**: slashes in an arc. Gains Contempt when struck (+5% damage per stack).
- Q, *I'll Give You My Back* (passive): every blow she takes has a 30% chance to trigger a counter-skewer at the attacker, piercing up to 4 enemies. No cap.
- E, *Face Me* (16 s): taunts enemies within 6 m for 6 s, and she takes 40% less damage.
- R, *Ultrix* (45 s): a slash as she steps back 1 m, then an 8 m lunge where you aim (3x her basic damage to everything she passes). Untouchable throughout.

**Cenhelm**: left-right punches, each splashing where it lands. Damage scales with his max HP. Takes 25% of hits aimed at his allies.
- Q, *The Gate* (10 s): ground slam around him. Every punch takes 1 s off the cooldown.
- E, *Walk Out* (12 s): dashes to the lowest-health ally in the leash, stunning enemies on the way and where he lands for 1.5 s.
- R, *The Horn* (40 s): everything within 16 m is slowed by half for 6 s, takes a little damage each second, and is pushed back slightly.

**Kheiron**: fires bolts.
- Q, *Lesson* (4 s): heals the lowest-health ally (never himself) for 5% of their max health.
- E, *The Grove* (14 s): a leash-sized grove at his feet for 4 s; allies inside heal 1.5% of max health per second. Followers fight inside it and stand in it.
- R, *Give the Sky* (60 s): pays 20% of his max health (never below 1) to reset the other heroes' ultimates. Combo: Kheiron R, swap, Solenne R, swap, Cenhelm R.

The leader deals 20% more damage. Swapping has a 1-second cooldown and a small entrance burst.

## Level-up cards

Cards are coloured by hero (Solenne red, Cenhelm orange, Kheiron green, party grey) and bordered by rarity, each with its own reveal:

| Rarity | Reveal | What's in it |
|---|---|---|
| Common | Already there | Small stat boosts |
| Rare | Blue, after 0.5 s, gentle glow | Bigger stats, cooldowns, extra bolts |
| Epic | Purple, crackles for 1 s, then a lightning strike | Behaviour changers |
| Legendary | Gold, burns into place over 1.5 s, flames stay | Ultimate upgrades (every 5th level) |
| Bond | Gold with lightning, split diagonally into two heroes' colours | Duo combos |

- Every 5th level offers 3 cards drawn from all heroes' remaining ultimate upgrades plus any unlocked bonds, so the hero you want isn't guaranteed.
- A bond unlocks once both of its heroes have at least one ultimate card. Three for now: *Back to Back* (Solenne + Cenhelm), *Penance* (Solenne + Kheiron), *Walk Out Together* (Cenhelm + Kheiron).
- 3 rerolls and 3 banishes per run. A banished card never comes back that run.
- The full card list is in `scripts/upgrades.gd`.

## Project layout

- `scenes/main.tscn`: the one scene; everything else is built in code for now.
- `scripts/`: one script per system (party, hero, enemies, XP, effects, HUD, upgrades). Each file starts with a comment explaining what it does.
- `tests/smoke_test.gd`: a bot that plays a full run without a window and reports how it went. Run it with:
  `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_test.gd`
- `tests/all_cards_test.gd`: switches on every card at once and plays two minutes, to catch broken card effects.

## Next

More enemy types, an elite, the boss at 12 minutes, and real skill-upgrade cards.
