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
| Swap leader | Space or Shift | A or right bumper |
| Pick a level-up card | 1 / 2 / 3 or click | X / Y / B |
| Restart after a run | R | Start |

Fallen heroes get back up if the leader stands next to them for 3 seconds.

## How the party behaves

- **The leader** is yours: they face your mouse, and their basic attack fires where you aim.
- **Followers** hunt the nearest enemies, but only inside the leash (the faint circle, 8 metres around the leader). Past it, they run back.
- **The healer (Kheiron)** goes to whichever ally has the lowest health percentage, and otherwise stays back and fires from range.
- **Badly hurt followers** (below 35% health) stop hunting and fall back behind the leader.

Tuning numbers live at the top of `scripts/party.gd` (`LEASH`, `HEAL_SEEK_BELOW`, `RETREAT_BELOW`).

## The heroes (grey-box versions)

Basic attacks fire on their own at each hero's attack speed. The leader's Q and E are yours to cast; followers cast theirs the moment they're ready and would do something.

**Solenne**: slashes in an arc. Gains Contempt when struck (+5% damage per stack).
- Q, *I'll Give You My Back* (passive): 30% chance when struck to counter with a skewer that pierces up to 4 enemies.
- E, *Face Me* (16 s): taunts enemies within 6 m for 6 s, and she takes 40% less damage.

**Cenhelm**: left-right punches, each splashing where it lands. Damage scales with his max HP. Takes 25% of hits aimed at his allies.
- Q, *The Gate* (10 s): ground slam around him. Every punch takes 1 s off the cooldown.
- E, *Walk Out* (12 s): dashes to an ally (the one nearest your aim when you lead him), stunning enemies on the way for 1.5 s.

**Kheiron**: fires bolts. Incurable: nothing heals him.
- Q, *Lesson* (4 s): heals the most hurt ally for 10% of their max health.
- E, *The Grove* (14 s): a leash-sized grove at his feet for 4 s; allies inside heal 3% of max health per second. Followers fight inside it and stand in it.

The leader deals 20% more damage. Swapping has a 1-second cooldown and a small entrance burst. Ultimates come later.

## Project layout

- `scenes/main.tscn`: the one scene; everything else is built in code for now.
- `scripts/`: one script per system (party, hero, enemies, XP, effects, HUD, upgrades). Each file starts with a comment explaining what it does.
- `tests/smoke_test.gd`: a bot that plays a full run without a window and reports how it went. Run it with:
  `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_test.gd`

## Next: milestone 2

Ultimates that fire when a hero swaps in, more enemy types, an elite, the boss at 12 minutes, and real skill-upgrade cards.
