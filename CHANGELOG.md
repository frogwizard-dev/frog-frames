# FrogFrames

## 0.1.3

- An interrupted channel (Drain Life, a bandage) on a target or focus bar shows red "Interrupted" rather than ending as if finished, and a red bar no longer carries over to your new target.
- Shift-, ctrl- and alt-click on a frame now target too.
- The gamepad UI's target menu (Y) stays open with the target frame hidden.
- Portraits no longer go blank after a loading screen; 3D portraits of units the game keeps anonymous (in instances) show the 2D picture instead of nothing.
- Names in Russian, Korean or Chinese draw in every font.
- Less work: your target's target looks at its health and power a few times a second and everything else once a second; aura rows skip the reads the game would refuse anyway.
- Shared code (FrogLib 1.12.0): see its notes for the rest of what's fixed.

## 0.1.2

- Uses far less CPU and memory: in a ten-minute test session, about half the game calls, a tenth of the garbage and a fifth less memory. A burst of health, power or aura changes is drawn once rather than once per event, and each power change is handled once (the game sends two events for it); frames only listen to the events their settings use, and health, power and flag changes redraw only what they change; health text uses the health just read for its bar rather than asking the game again; nothing runs every frame while there's nothing to animate (the hit text over the portrait, the range and target-of-target checks), and party frames hear about range changes from the game rather than checking; icons, glows, empty text, the mana rule and the bars' frames are only touched when they change. Frame borders, party pets, the 3D portrait, hit text, your cast bar, the five-second rule, druid mana, glows and the unlock tint are only made when a frame uses them. It looks and works the same.
- Your target's target redraws as soon as your target switches targets, rather than at the next check.
- Buff and debuff rows no longer build a fresh set of icons (leaving the old ones behind) each time the row next to them opens or closes, and folding a row no longer restyles the cast bar, druid bar, combo points and fonts.
- Smaller download: the portrait, frame and dragon art is saved compressed (the same pictures, about a quarter of the size), and the package leaves out this changelog.
- The Place boxes in the settings follow the frame: after dragging it or "Reset position" they showed (and changed) its old place until a reload.
- A Forever update hid the size of every hit from add-ons, so a hit that was fully absorbed or blocked showed "0" over the portrait. It says Absorb or Block again, and a partly blocked hit shows its damage with "(Block)" after it, as Blizzard's own portrait does.
- Under the hood: the five-second rule's strip under your mana bar now comes from FrogLib, shared with Personal Resource Tweaks and XIVPlayer; clearer names and shorter notes throughout. It looks and works the same.

## 0.1.1

- Heal prediction now comes from FrogLib, shared with XIVPlayer. It looks and works the same.

## 0.1.0

First version: Classic-style unit frames for you, your pet, your target and its target, your focus and your party (up to four, with their pets if you like). No raid frames.

- **Round portraits** with a level badge, a name strip and health and power bars tucked in behind. Portraits can be a picture, a class icon, a 3D model or none, with the gold or silver dragon round elite and rare enemies.
- **Four looks**: Classic (glossy bars, dark metal ring), Modern (flat bars), Forever (the cooldown manager's bars) and Stone (the old action bar's carved frame). Or **Blizzard's own 1.x vanilla frame** for any frame, with an option for a large health bar.
- **Bar text from templates**, three places on each bar: value, max, percent, name, level and class.
- **Level coloured by difficulty**, a skull for bosses; health in class colours or by reaction, tapped enemies grey, or always green.
- **Heal prediction** and shields on your, your pet's and the party's health bars.
- **Cast bars** for the target and focus (interrupts flash red), **buffs and debuffs** with readable timers and stacks, and a few debuffs on each party member.
- **Combo points**, a **druid mana bar** in forms, the **five-second rule** under your mana, and a **threat glow** when enemies are on you or a party member.
- **Group roles, raid marks, leader, PvP and resting icons**, and a hunter's pet's happiness.
- **Fades when idle** (out of combat, at full health, nothing to do) and **out of range**.
- **Every frame its own page**: sizes, textures, text, portrait, where the cast bar, buffs, debuffs and combo points go, and a nudge for every part.
- **Unlock and drag** with a grid and snapping; every frame shows a full sample while unlocked.
- Any kind of frame can be switched off; Blizzard's own only hides while ours is on.
- Settings: `/ff`, the AddOn compartment, or Options > AddOns > Frog Wizard > FrogFrames.
