# Party Survivors (prototype)

Lead a party of three heroes through a horde. Steer one, the other two fight at your heels, and swap who leads at any moment.

This is **milestone 1**: a grey-box prototype to answer one question — is steering a party through a crowd fun?

## Between nights: the campfire

The game opens at the party's campfire in the middle of the arena: Kheiron and Cenhelm on logs, Solenne standing. **FIGHT** (Enter) and they get up and walk out as the camera rises into the battle view. **HEROES** (or click a hero at the fire) shows each hero's kit. **TALENTS** unlocks later. **SETTINGS** has damage numbers and captions, saved straight away.

When a night ends, the results appear on top while the game carries on behind them, all in one shot:
- **A win (or Return to the Keep from the pause menu):** the horde crumbles, the party walks back and sits by the fire, and the camera settles in. **Keep Fighting** works at any moment: they turn round (or get up) and head straight back out.
- **A fall:** the screen behind the results goes black. **Try Again** fades in on the camp as they stand and set out; **Return to the Keep** fades in with them resting.

Gold earned is banked, and nights survived are counted, in `user://save.json` (with your settings).

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
| Pause (resume, settings, return to the Keep) | Esc or P | Start |
| Menus | Mouse, or arrows + Enter / Esc | Stick + A / B |

Fallen heroes get back up if the leader stands next to them for 3 seconds.

**Health rings:** each hero has a small arc on the ground in front of them, outlined in black, that empties as they're hurt (green, then amber, then red). It's open behind them so it never crosses their body. The leader's has a gold outline and flashes red when they're low. The rings draw over the horde, and when an enemy stands between the camera and a hero, the hero shows through as a see-through silhouette in their colour.

**The cursor** shows a ring that fills as the leader's next basic attack charges, and pulses when it fires. If a hero falls, "Kheiron is down!" appears under the cursor with an arrow pointing to them.

The screen's edge glows red when anyone drops below 30%, pulsing harder the lower they are.

**Hold to attack (setting):** off by default. When on, the leader swings only while you hold the left mouse button (X on a gamepad); a press just before the swing is ready still counts. Followers always fight on their own.

## How the party behaves

- **The leader** is yours: they face your mouse, and their basic attack fires where you aim.
- **Followers** hunt the nearest enemies, but only inside the leash (the faint circle, 8 metres around the leader). Past it, they run back.
- **Ranged followers (Kheiron) kite.** When their shot is ready they get in range and fire; while it reloads they slip to the nearby spot with the fewest enemies, keeping their target in range and staying inside the leash. Melee followers keep diving in.
- **The healer (Kheiron)** also stays within 5 m of whoever is hurt the most.
- **Badly hurt followers** (below 35% health) stop hunting and fall back behind the leader.

Tuning numbers live at the top of `scripts/party.gd` (`LEASH`, `HEAL_SEEK_BELOW`, `RETREAT_BELOW`, and the `KITE_` numbers).

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

## A run

- **Elites** (purple, bigger) appear every 90 s and drop a chest. Walk onto it: it charges for 2 s, glowing in its rarity colour, then pops with gold.
- **Hunters** (mini-bosses) arrive at 2:30, 5:00, 7:30 and 10:00. Each one killed scratches a bloody claw mark behind the kill counter.
- **The final boss** arrives at 12:00. The timer turns to ∞. Killing it strikes through the tally, locks your score and wins the run.
- **Swarms:** every 500 kills, a minute of double spawning, mostly tiny swarmlings.
- **Treasure goblin:** every 3rd chest opened sends one running. Catch it for gold before it escapes (20 s).
- **Followers** focus elites, bosses and goblins when one is inside the leash.
- **Damage numbers** show for big hits and for hits on elites and bosses (a settings toggle comes with the menu).
- Gold is counted per run for now. The end screen shows a placeholder "next unlock".

## The arena and the night

- The arena is a circle walled by **runestones**: rough standing stones with faint purple runes on their inner faces, some joined by lintels. There's no way out.
- Every run starts at **sundown**. Over the first two and a half minutes the light sinks into a steady, reddish, fire-lit night. It's never pitch black: the runes glow brighter as the sun goes, braziers burn in the ruins, and a warm glow follows the party.
- When the Beast arrives at 12:00, a **faint sunrise** begins.
- Colours and timings live at the top of `scripts/arena.gd` (`SKY`, `NIGHTFALL`).

## Captions

Spoken lines show as captions at the bottom of the screen until the voices are recorded:
- The leader walks into the runestones: *"We're trapped."* / *"There's no way out."* (once per run per hero).
- The Beast at half health: *"The Heart is MINE!"*
- The Beast falls: *"Finally, some rest."* … Solenne: *"...for now."*

Every line lives in `scripts/barks.gd` (`LINES`), with room for several variants per hero. Captions can be switched off with `Game.settings["captions"]` (the settings menu comes later).

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
- `scripts/`: one script per system (arena, camp, campfire interface, results, party, hero, enemies, XP, effects, HUD, upgrades, barks, ui_kit for shared menu styling). Each file starts with a comment explaining what it does.
- `tests/smoke_test.gd`: a bot that plays a full run without a window and reports how it went. Run it with:
  `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_test.gd` (tests skip the campfire and never touch your save)
- `tests/all_cards_test.gd`: switches on every card at once and plays two minutes, to catch broken card effects.

## Placeholder art

Until the real heroes arrive, the party wears models from **KayKit Adventurers 2.0** (Knight = Solenne, without her helmet; Barbarian = Cenhelm; Mage = Kheiron), with idle, run and death animations from the same pack. The ruins, braziers and chests come from **KayKit Dungeon Pack 1.1**. Walls, pillars, rubble, barrels and braziers are solid: heroes and enemies walk round them.

Both packs are by Kay Lousberg (www.kaylousberg.com) and are CC0 (licences in `assets/kaykit/`). If a model file is missing, the game falls back to the grey-box shapes.

## Next

The Keep: a closed square round the camp with gates, guards on the walls, and see-through walls.
