# Writing prompts for game moves

These notes come from about 50 takes for a historical RTS: legionaries, Carthaginians, workers and townsfolk. The
model was Kimodo-SOMA-RP-v1.1 on an RTX 4090, where one take of 2–5 s takes about 30 s.

## What works

- **Describe a person, one action, in the present tense.** Mocap descriptions read like "A person …", "A soldier …"
  or "A farmer …".
- **Describe the arms when they hold something.** Kimodo has no props. "Sword strike" alone gives a limp swing to
  shoulder height, with the left arm hanging. Adding *"the left arm held forward as if holding a shield"* gives a
  proper legionary stance, with the shield arm up and the strike over it.
- **Name the body part and the direction:** "raises the right hand above the head and quickly strikes down at an
  enemy in front".
- **Expect the action in the middle.** Kimodo stands still first, does the move around 1.4–1.7 s into a 2.5 s clip,
  then settles. Cut the clip in the engine (`cut = "action"`) rather than fighting it with the prompt.
- **Loops (walk, jog, sidestep) want 4–5 s**, so a clean cycle can be cut from the middle.

## What does not

- **"Again and again"** often gives one swing, then the body freezes in the end pose (pickaxe, gathering). Count
  the repeats instead ("three times in a row"), spell out each step of the cycle ("squats down, picks up … stands
  up … drops it into a basket … squats down again"), and give it 5 s.
- **"Overhead with both hands" or "axe"** turns into chopping wood: bent over, swinging down at a log.
- **"Running forward while looking back"** came out as running backwards. Check the travel direction (the hips path
  against the facing) before you use a take.
- **Bows** need the pose spelled out: "the left arm held straight out in front, pulls the string back to the right
  cheek".
- **Riders:** there is no horse. Use another tool for mounted moves.
- **Characters holding things.** Kimodo has no props. "As if holding a shield" gives the right arm *position*, but
  the forearm roll and the grip are Kimodo's guess. In the author's game, a big shield came out sideways with the
  fist outside, even with the roll aligned exactly. For soldiers and workers, take the arms (shoulder to hand) from
  your own clip made for that prop, and use Kimodo for the hips, legs, spine and head. Leave characters that hold
  nothing fully on Kimodo.

## Checking a take without opening it

Two numbers catch most bad takes:

- **Travel:** where the hips end up, compared with where they face. A side-step should move sideways, a walk should
  move forwards, and a strike should stay roughly in place.
- **Hand height over head** for overhead moves, and the **peak downward hand speed** after it. In our tests, a good
  overhead strike had the hand at least 5 cm above the head and moving down faster than 4 m/s.

A 10-frame stick-figure strip per take (side or three-quarter view) is enough to pick the best seed. Wrong turns,
backwards runs and frozen poses are obvious at a glance.

## The 32 takes we kept

All are 30 fps, made with Kimodo-SOMA-RP-v1.1. The "seed" column is the take number.

| Clip | s | seed | Prompt | Notes |
|---|---|---|---|---|
| overhead | 2.5 | 1 | A person raises the right hand above the head and quickly strikes down at an enemy in front, the left arm held forward as if holding a shield. | |
| slash | 2.5 | 1 | A person swings the right hand in a fast horizontal slash from right to left at an enemy in front, the left arm held forward as if holding a shield. | |
| thrust | 2.5 | 2 | A person steps forward and thrusts the right hand straight forward at chest height as if stabbing with a short sword, the left arm held forward as if holding a shield. | |
| thrust_low | 2.5 | 1 | A person holds a long spear with both hands at the waist and thrusts it forward low, then pulls it back. | |
| bash | 2 | 2 | A person shoves forward hard with the left arm as if hitting an enemy with a shield, then steps back into stance. | |
| throw | 2.5 | 1 | A person takes a step forward and throws a javelin overhand with the right arm. | |
| sling | 3 | 1 | A person whirls the right arm in circles above the head and then releases a sling throw forward. | one big wind-up, not a whirl |
| shoot | 3 | 3 | An archer raises a bow with the left arm held straight out in front, pulls the string back to the right cheek with the right hand, holds for a moment and releases. | "bow in the left hand … to the face" gave a weak draw; naming the straight bow arm and the cheek fixed it |
| guard | 4 | 1 | A person stands in a low defensive stance, the left arm held forward as if holding a shield, shifting weight slightly. | |
| impact | 2 | 2 | A person is hit hard in the chest, staggers back one step and recovers. | |
| death | 3.5 | 1 | A person is struck, drops to the knees and collapses forward onto the ground, lying still. | |
| death_back | 3.5 | 1 | A person is struck, falls backward onto the ground and lies still. | |
| climb | 4 | 1 | A person climbs up a ladder, hand over hand. | climbs 1.7 m; use `cut = "climb"` |
| walk_back | 4 | 1 | A person walks backward slowly while facing forward, keeping the guard up. | |
| strafe_l | 4 | 1 | A person sidesteps to the left several times while facing forward. | |
| strafe_r | 4 | 1 | A person sidesteps to the right several times while facing forward. | |
| trot | 4 | 1 | A soldier jogs forward at a steady pace. | 2.3 m/s |
| turn_l | 2 | 1 | A person standing still turns in place 90 degrees to the left. | use `cut = "turn"` |
| turn_r | 2 | 1 | A person standing still turns in place 90 degrees to the right. | |
| build | 4 | 1 | A person hammers a nail into a wooden beam at waist height, striking repeatedly with the right hand. | |
| chop | 4 | 1 | A person chops a standing tree trunk with an axe, swinging it from the side with both hands again and again. | |
| mine | 5 | 1 | A miner raises a pickaxe high over the right shoulder with both hands and brings it down onto the rock in front, three times in a row. | two full swings; "again and again" at 4 s gave one swing and a frozen pose |
| gather | 5 | 1 | A person squats down, picks up an object from the ground, stands up and drops it into a basket held at the left hip, then squats down again for another. | a full cycle (~4.4 s); "bends down … repeating" bent and stayed |
| hoe | 4 | 1 | A farmer works the soil with a hoe, raising it and pulling it down toward the feet again and again. | |
| knife | 4 | 1 | A person kneels on one knee and cuts something on the ground with a knife in the right hand. | bends rather than kneels |
| talk | 5 | 1 | A person stands and talks to someone, gesturing with both hands while speaking. | |
| walk_elder | 5 | 1 | An old man walks forward slowly with a slight stoop. | 0.46 m/s, stooped |
| walk_woman | 5 | 1 | A woman walks forward calmly with small steps. | 1.2 m/s |
| run_child | 4 | 1 | A child runs forward playfully. | adult-sized skeleton |
| walk_child | 5 | 1 | A child walks forward with a bouncy step. | |
| walk_noble | 5 | 1 | A dignified man walks forward slowly and upright with the hands clasped behind the back. | |
| idle_citizen | 5 | 1 | A person stands idle, looking around and shifting weight from foot to foot. | |

Rejected: "A person flees in panic, running forward fast while looking back." (it ran backwards), and several
"overhead with both hands" variants (they chopped wood).
