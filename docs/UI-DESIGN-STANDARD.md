# MechOS UI Design Standard

## Master reference

The approved MechOS graphical concept is the **Master reference** for the operating system UI. New MechOS-owned interfaces should look and behave like parts of the same product rather than independent desktop applications.

The implementation name for this visual system is **MechOS Reference UI v2**.

## Visual identity

- deep black and midnight-navy backgrounds
- purple, blue and restrained magenta neon accents
- bright white primary text with blue-gray secondary text
- rounded cards and elevated panels with subtle purple/blue borders
- gradient primary actions instead of flat desktop-style buttons
- large, readable headings and consistent section labels
- strong visible focus rings for controller and keyboard navigation
- full-screen/console presentation for MechScope gaming surfaces
- no KDE window chrome or desktop panel visible while MechScope owns Gaming Mode

## Shared components

The shared design system applies to buttons, navigation tabs, focus states, text fields, lists, tables, cards, progress bars, sliders, checkboxes, radio buttons, menus, dialogs and scroll bars.

Reference theme runtime:

`/usr/share/mechos/theme/mechos-ui.qss`

Reference token file:

`/usr/share/mechos/theme/reference-ui-v2.conf`

## Required product surfaces

The following MechOS-owned interfaces must use this visual system:

- MechScope 2.0 home and library
- MechScope Unified Store
- MechScope Downloads and Quick Actions
- Performance Center
- Update Center
- Creator Mode
- MechOS Installer and native install progress
- Recovery Center
- first-boot/OOBE
- System Tools Hub
- Companion/Bridge settings when implemented

## MechScope rules

MechScope is the console-first surface. It should be frameless and full-screen in Gaming Mode. Store, library and other core gaming pages must stay visually inside MechScope rather than appearing as ordinary KDE desktop windows.

Steam Gamepad UI is an application launched from MechScope; it does not replace the MechScope shell as the operating-system home UI.

When Gamescope is unavailable in a VM or unsupported graphics configuration, Plasma may provide the compositor fallback, but Plasma desktop chrome should remain hidden while MechScope is active.

## Installer rules

The Installer uses the same background, cards, buttons, progress language and typography as MechScope. Its left-side step navigation should remain clear and readable, with the current step highlighted in the same purple focus/selection treatment used elsewhere in MechOS.

Destructive actions must remain visually distinct and must not be hidden behind decorative styling.

## Performance and Update Center rules

Performance Center and Update Center use the same card system as the MechScope dashboard. Metrics should be presented in grouped panels with clear labels and status colors. Progress bars use the shared blue-to-purple gradient.

## Creator Mode rules

Creator Mode shares the same shell language while allowing denser project/tool layouts. It should look like a creator workspace belonging to MechOS, not a separate third-party launcher.

## Input and accessibility

- every primary action must be reachable with controller, keyboard and mouse
- controller/keyboard focus must be clearly visible
- focused controls use the shared bright purple focus border
- text contrast must remain readable against dark surfaces
- critical warnings must not rely on color alone
- layouts should remain usable at common 720p, 1080p and higher displays

## Build authority

`scripts/mechos-reference-ui-integration.sh` is the final visual-authority stage in the cumulative ISO build. It runs after other late UI/runtime integrations and rewrites the shared QSS in both the Live image and installed-system payload.

Future MechOS graphical work should extend the shared reference system rather than introducing unrelated per-app themes.
