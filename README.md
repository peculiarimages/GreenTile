# GreenTile

A small macOS menu-bar utility that puts tiling buttons right under the traffic lights of every
window, so you can snap a window to the left or right half of the screen with one click: no
hovering, no menu, no keyboard shortcut to remember.

```
 ● ● ●            ● ● ●
 ◐   ◑            ◖ ▮ ◗      <- hold Option
```

Each button sits directly below one of the traffic lights, centred on it, and is drawn like a
miniature green traffic light: half green for the part of the screen the window will take, half
white for the rest.

- **Two buttons:** left half under the red button, right half under the green one (the yellow one
  is left clear). Click ◐ and the window fills the left half of the display it is on (the area
  below the menu bar and beside the Dock); click ◑ for the right half.
- **Hold Option:** three buttons, left, center and right third, one under each traffic light.
  Release Option and it goes back to two.
- **Right-click** (or Control-click) any button to switch between halves and thirds for good. With
  thirds as the default, holding Option shows the halves instead, so Option always turns the
  current row over. The menu-bar icon has the same switch ("Thirds Instead of Halves"), and the
  choice is remembered.
- **Hover** a button for a moment and a small bubble says what it does and how to switch.

The buttons hide behind any window that covers theirs, never steal focus when clicked, and follow
their window as it moves. They work on every display, including displays arranged to the left of
or above the main one.

## Requirements

- macOS 14 or later.
- Xcode 15 or later to build it. There is no prebuilt download yet.
- **Accessibility permission.** GreenTile finds each window's traffic lights and moves windows
  through the Accessibility API, so macOS will ask you to allow it (System Settings > Privacy &
  Security > Accessibility). Without it nothing appears.

## Build and run

```sh
git clone https://github.com/peculiarimages/GreenTile.git
cd GreenTile
open GreenTile.xcodeproj      # then press Run
```

or from the command line: `xcodebuild -project GreenTile.xcodeproj -scheme GreenTile build`.

A tiling icon appears in the menu bar. From there you can hide the buttons, switch to thirds,
check the permission, and have GreenTile open at login.

### Signing and the Accessibility permission

By default the app is signed "to run locally" (ad-hoc), which works on any Mac without a developer
account. macOS ties the Accessibility permission to an app's code signature, and an ad-hoc
signature changes with every build, so you may have to grant the permission again after each
rebuild. For a stable signature, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`
(git ignores it) and put in your own signing identity and team ID. The permission then survives
rebuilds.

### Tests

```sh
xcodebuild -project GreenTile.xcodeproj -scheme GreenTile -destination 'platform=macOS' test
```

runs the unit tests for the layout and placement logic.

## How it works

- **Following windows.** The Quartz window list is polled (60 Hz for a second after any click,
  drag, app switch or Option press, about 7 Hz otherwise) to track every window's position and
  stacking. Each poll checks that a window's buttons are still directly in front of it, because the
  system moves a window above its buttons whenever it is brought forward.
- **Finding the traffic lights.** Accessibility is asked, on a background queue and only for new
  windows plus a re-check every 1.5 s, where each window's red and green buttons are. Windows
  without them (dialogs, panels, fixed-size windows, native full screen, Stage Manager thumbnails)
  get no buttons.
- **Stacking.** Each button is its own small, transparent, non-activating panel (so the space
  between buttons is genuinely empty and clicks there reach the window), ordered directly above its
  window. A window in front of it hides its buttons too, and clicking never steals focus.
- **Tiling.** Sets the window's size and position through Accessibility. Tile edges are rounded
  once and shared, so neighbouring tiles always meet exactly.

## Project layout

- `GreenTileKit/` pure geometry, layout, placement and help-text logic (no AppKit), covered by
  `GreenTileKitTests/`.
- `GreenTile/Accessibility/` Accessibility wrappers, the window list and the per-window scan.
- `GreenTile/Overlay/` the round button, its panel, the help bubble, and the controller that keeps
  one panel per button.
- `GreenTile/Actions/` the tiling action.
- `Config/` build settings, including the signing setup described above.
- `project.yml` is the source of truth for the Xcode project. Edit it and regenerate with
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`xcodegen generate`).

Debug builds have developer switches. Each runs once and exits; start them with
`open -n GreenTile.app --args <switch> <path>` so the app itself, not your terminal, holds the
Accessibility permission:

| Switch | Does |
|---|---|
| `--render-overlay <dir>` | writes light/dark PNGs of the buttons and the help bubble |
| `--dump-windows <file>` | reports every window the scan finds and where its buttons would go |
| `--selftest-tile <file>` | tiles a throwaway window to every layout on every display and checks the result |
| `--selftest-stacking <file>` | re-fronts a throwaway window repeatedly and checks its buttons come back in front |
| `--selftest-modes <file>` | fakes the Option key and delivers right-/Control-click events; checks each button sits under its light, the halves/thirds switching, and every button's result |
| `--selftest-help <file>` | hovers buttons with synthetic events; checks the help bubble's timing, text, placement and dismissal |

## Known limits

- The buttons cover whatever is underneath them: the top-left corner of the window's content (a
  sidebar's first row, for example). They hide while another window covers them, but not on hover.
- Some apps with a minimum window size cannot be squeezed to exactly half or a third of a display.
- Windows on other Spaces, or parked in the Stage Manager strip, have no buttons until shown.
- To tell which Accessibility window is which, GreenTile uses a private Accessibility symbol
  (`_AXUIElementGetWindow`) that most window managers rely on. It is not App Store compatible.

## License

[MIT](LICENSE). GreenTile is an independent project and is not affiliated with or endorsed by
Apple. macOS and Stage Manager are trademarks of Apple Inc.
