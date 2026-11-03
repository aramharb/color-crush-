# Gem Pop – Flutter (Android Studio)

Match-3 puzzle where every tile has a **color** and a **number**.

| Match (3+ in a row/column) | Result |
|---|---|
| Same **color** or same **number** | normal match |
| Same **color AND number** | **PERFECT**: clears the whole row + column, **+2 moves**, +300 bonus |
| Exactly **4** | creates a **Bomb** (clears 3x3 when matched; bombs chain) |
| **5+** | creates a **Rainbow** (swap it with a tile to clear all tiles of that color) |

Swipe a tile, or tap two neighbouring tiles, to swap. Cascades raise a combo multiplier,
25 moves per game, best score is saved. Sounds are synthesized in code (`lib/sound.dart`);
there are no asset files.

## Run in Android Studio
1. Install the Flutter SDK and the Flutter + Dart plugins in Android Studio.
2. **File → Open…** and choose this folder (the one with `pubspec.yaml`).
3. Run **Pub get** if prompted, pick an emulator or a USB device, press **Run ▶**.

CLI: `flutter pub get && flutter run` (or `flutter build apk`). Tests: `flutter test`.

## Layout
- `lib/main.dart` – app, HUD, overlays
- `lib/game.dart` – game rules, animation sequencing, input
- `lib/board_painter.dart` – `CustomPainter` that draws gems/particles
- `lib/sound.dart` – generated sound effects
- `native-android/` – the earlier native Kotlin version (separate Gradle project)
