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
| Leader's skill | Q | Left bumper |
| Leader's ultimate | E | Either trigger |
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
- **Ranged followers (Kheiron, Bram, Levana) kite.** When their shot is ready they get in range and fire; while it reloads they slip to the nearby spot with the fewest enemies, keeping their target in range and staying inside the leash.
- **Melee followers keep moving while they fight.** They pick a target on the edge of the crowd (close by, few enemies round it) and stand on its quietest side, just inside their reach, re-judging three times a second. Stepping out of an enemy's reach resets its wind-up. It's all judged relative to what's around them, so it works the same against 20 enemies or 2,000.
- **Nerve:** if a melee follower is losing health faster than it can take (Solenne and Cenhelm 10% of their health a second, Halvar, Niten and Rhian 6%, Cael 4%), it breaks away toward thinner ground near the group for a moment, firing its skill if that helps it get out (Halvar dashes out, Niten's waves push the crowd back as he hops away, Rhian spins, Cenhelm leaps), then goes back to fighting from the edge. Health loss is averaged over 1.5 s and healing counts against it, so a hero being healed can hold a big crowd. Numbers are in `scripts/hero_data.gd` (`nerve`, `escape`).
- **The healer (Kheiron)** also stays within 5 m of whoever is hurt the most.
- **Badly hurt followers** (below 35% health) stop hunting and go to Kheiron (or into a grove) if he's in the party, otherwise fall back behind the leader.

Tuning numbers live at the top of `scripts/party.gd` (`LEASH`, `HEAL_SEEK_BELOW`, `RETREAT_BELOW`, the `KITE_` and `MELEE_` numbers).

## The heroes

Each hero has a basic attack that fires on its own, a **skill (Q)** and an **ultimate (E)**. Followers use their skill the moment it would help; **only the leader can use an ultimate**, so swap a hero in to use theirs. Ultimates start each night half charged. Every hero's numbers and words live in `scripts/hero_data.gd`, and what they do in `scripts/kits/<hero>.gd`.

**Solenne**: swipes her sword in an arc.
- Q *Face Me* (14 s): taunts enemies within 6 m for 8 s. While taunting, every blow she takes has a 30% chance to counter with a straight 6 m stab.
- E *Ultrix* (40 s): slashes across, then forwards, ×3 damage each.

**Cenhelm**: one-two punches, each splashing where it lands.
- Q *Walk Out* (10 s): leaps to the furthest enemy within 8 m; ×1.5 in 4 m where he lands.
- E *The Horn* (45 s): after a 0.5 s wind-up, the whole screen is slowed 40% for 6 s, takes ×0.5 every second and is pushed back each tick.

**Kheiron**: fires bolts. *Lesson* is automatic: every 2 s he heals the most hurt ally (never himself) for 5% of their max health. Healing on him is halved.
- Q *The Grove* (14 s): a leash-sized grove for 4 s; allies inside heal 1.5% a second.
- E *Give the Sky* (60 s): pays 20% of his health to reset the other heroes' ultimates.

**Halvar**: throws two axes at the nearest enemy, 0.3 s apart. They land, then fly back to his hands, hitting again on the way. Every hit bleeds (15% of his attack a second for 4 s).
- Q *Reaving Rush* (10 s): dashes forward through a line, then spins (×0.8 each, bleeding).
- E *Hall of Axes* (35 s): +50% attack speed for 8 s, and the axes come back faster.

**Niten**: slow, heavy cuts: a 135° swing (45° left to 90° right), then a stab.
- Q *Twin Wind* (9 s): two slices 0.6 s apart, each sending a 90° wave 8 m forward (×1.5); he hops back 1 m with each.
- E *Heaven Strike* (40 s): after 0.5 s, lightning strikes the toughest enemy in sight (bosses first), ×3 within 4 m.

**Bram**: hammers nails at the nearest enemy; they pierce 2 and fly 6 m.
- Q *Anvil* (16 s): an anvil between the party; for 8 s, heroes within 6 m attack 15% faster and deal 15% more damage.
- E *Temper* (45 s): a 4.5 s channel that carries on if he's swapped out: four strikes in rings of 2, 4, 6 and 8 m (×1.5 each), slowing what they catch by 40%.

**Rhian**: a piercing 4 m stab. Each stab that lands makes the next 20% faster, up to 5 times, while she keeps hitting.
- Q *Hold the Line* (9 s): a spin that knocks everything within 7 m out to 7 m (×0.8).
- E *The Line* (40 s): a battle cry, then three lightning stabs from furthest enemy to furthest enemy in the leash, ×2.5 to everything she passes.

**Levana**: throws daggers (5 m, pierce 2) that stay where they land, up to 10.
- Q *Vanish* (12 s): her 10 newest daggers fly back to her, cutting on the way; she's invisible with +30% speed for 3 s, and can't attack meanwhile.
- E *Smoke and Poison* (35 s): two smoke bombs at the furthest enemies in the leash: 5 m clouds for 6 s, slowing 20% and dealing 30% of her attack a second.

**Cael**: a fast double sweep that reaches 6 m but only hits the far 3 m.
- Q *Claim* (10 s): throws his spear at the thickest crowd within 8 m (×0.8 in 2 m), then leaps to it, untouchable (×1.5 in 4 m).
- E *Skyfall* (40 s): leaps into the air, untouchable; a blue target drifts toward the cursor at 1 m/s. After 4 s (or press E again) he lands: ×3 within 2 m, ×1.5 out to 6 m.

**Picking the party:** at the campfire, open **HEROES**, choose a hero, and swap them in for someone. The pick is saved. For now all nine are open; later, heroes join through rescue nights. Placeholder models are KayKit characters, tinted where two heroes share a body.

The leader deals 20% more damage. Swapping has a 1-second cooldown and a small entrance burst.

## A run

- **Elites** (purple, bigger) appear every 90 s and drop a chest. Walk onto it: it charges for 2 s, glowing in its rarity colour, then pops with gold.
- **Hunters** (mini-bosses) arrive at 2:30, 5:00, 7:30 and 10:00. Each one killed scratches a bloody claw mark behind the kill counter.
- **The final boss** arrives at 12:00. The timer turns to ∞. Killing it strikes through the tally, locks your score and wins the run.
- **Swarms:** every 500 kills, a minute of double spawning, mostly tiny swarmlings.
- **Treasure goblin:** every 3rd chest opened sends one running. Catch it for gold before it escapes (20 s).
- **Followers** focus elites, bosses and goblins when one is inside the leash.
- **Enemy blows:** an enemy that reaches a hero strikes after 0.25 s, then every 0.5 s while it stays in reach. Stepping out of reach resets that first wait.
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

Cards are built for the three heroes in the party, coloured by hero (party cards are grey) and bordered by rarity. **Every card shows real numbers, before → after**, and its level (e.g. "Lv 2/5").

| Rarity | What it gives | Example |
|---|---|---|
| Common | Small steps that stack (up to 5) | Damage ×1.00 → ×1.15 · Attack speed · Max health |
| Rare | Bigger steps (up to 3) | Face Me cooldown 14.0 s → 11.9 s · skill damage · area |
| Epic | One more per attack (up to 3) | Sword arc: 1 → 2 swipes |
| Legendary (every 5th level) | Ultimate upgrades that change how it works | *Twice Blind*: Ultrix's two strikes come round once more |
| Bond (every 5th level) | Duo combos | *Back to Back* (Solenne + Cenhelm) |

Party cards (up to 5 each): Might, Haste, Vigour, Swiftness, Keen Eyes, Reach, Focus, and the rare **Echo** (+1 to every hero's basic attack).

- A bond unlocks once both of its heroes have at least one ultimate card.
- 3 rerolls and 3 banishes per night. A banished card never comes back that night.
- The cards are built in `scripts/upgrades.gd`.

## Project layout

- `scenes/main.tscn`: the one scene; everything else is built in code for now.
- `scripts/`: one script per system (arena, camp, campfire interface, results, party, hero, enemies, XP, effects, HUD, upgrades, barks, ui_kit for shared menu styling). Each file starts with a comment explaining what it does.
- `tests/smoke_test.gd`: a bot that plays a full run without a window and reports how it went. Run it with:
  `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_test.gd` (tests skip the campfire and never touch your save)
- `tests/follower_test.gd`: compares the melee follower AI with the old "walk up and stand there" behaviour. The first hero leads all night, so the other two are followers throughout. `PARTY=kheiron,halvar,rhian MELEE_AI=old` (or `new`).
- `tests/all_cards_test.gd`: switches on every card at once and plays two minutes, to catch broken card effects.

## Placeholder art

Until the real heroes arrive, the party wears models from **KayKit Adventurers 2.0** (Knight = Solenne, without her helmet; Barbarian = Cenhelm; Mage = Kheiron), with idle, run and death animations from the same pack. The ruins, braziers and chests come from **KayKit Dungeon Pack 1.1**. Walls, pillars, rubble, barrels and braziers are solid: heroes and enemies walk round them.

Both packs are by Kay Lousberg (www.kaylousberg.com) and are CC0 (licences in `assets/kaykit/`). If a model file is missing, the game falls back to the grey-box shapes.

## Next

The Keep: a closed square round the camp with gates, guards on the walls, and see-through walls.
