# Google Play phone screenshots — 1.5

Seven real captures of the app running on a 1080 x 1920 Android emulator
(Pixel 2 profile, Android 15). Nothing is drawn on top: no device frame and
no caption is baked in. They are already 9:16, so they need no cropping.

Upload them in file order. Play has no caption field, so the captions below
are for the listing text, a translated listing, or a graphic you make later —
at most one short line each.

| File | What it shows | Suggested caption |
| --- | --- | --- |
| `01-hilo-table.png` | Hi-Lo Training mid-round: five seats, the dealer's hole card face down, score, combo, round and shoe | Count every card the dealer deals |
| `02-survival-keypad.png` | The count keypad in Survival, an answer typed in, the clock running, three lives | The dealer stops. What's the count? |
| `03-results-combo-rank.png` | A perfect game: ×2, ×3 and ×4 combos, a new best, a rank gained and three achievements | Perfect counts build combos and rank |
| `04-hilo-hub-daily.png` | The Hi-Lo hub: the player's rank and today's Daily Challenge | One shared shoe for everyone, every day |
| `05-coach-correction.png` | The table coach naming a misplay: "11 vs 2 — basic strategy says Double" | The coach names the right play |
| `06-online-five-seats.png` | A five-player online table with each player's name and avatar | Up to five friends at one table |
| `07-table-rules.png` | The table-rule picker | Practise for the rules you'll face |

`extras/` has two more real captures if you want an eighth image (Play allows
eight): the home screen with Today's next step, and a verdict with "COMBO ×3!".

The player in the pictures ("Alex", with Maya, Jordan, Priya and Diego at the
online table) is a made-up profile seeded for the capture. The online table
ran over the app's in-memory transport, so no real server or players were
involved.

## Reshooting

1. Boot a 1080 x 1920 emulator, for example:
   ```bash
   avdmanager create avd -n HiLoStore1080 -d pixel_2 \
     -k "system-images;android-35;google_apis;arm64-v8a"
   emulator -avd HiLoStore1080 -no-snapshot
   ```
2. Switch it to gesture navigation:
   `adb shell cmd overlay enable com.android.internal.systemui.navbar.gestural`
3. Run `python3 tool/capture_store_screenshots.py <out_dir>`. It sets a clean
   status bar (9:41, full battery), runs
   `integration_test/store_screenshots_test.dart`, and saves a
   `adb exec-out screencap` each time the test reaches a shot.

The older `../play-ready/` set (1.1, center-cropped from 1080 x 2400) is
superseded by this one.
