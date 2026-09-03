# MechOS 0.3.1 roadmap — wallpaper collection

This file is part of the MechOS **0.3.1** roadmap and tracks the new official MechOS desktop wallpaper collection.

## 0.3.1 — 16 high-resolution MechOS wallpapers

Ship all 16 new MechOS-themed wallpapers as an official 16:9 desktop collection using the established dark metallic, electric-blue and purple neon visual language.

1. **Neon Mech Hangar at Night** — colossal MechOS combat mech in a neon-lit maintenance hangar with holographic diagnostics and city skyline.
2. **MechOS Neon Cyber Interface** — clean abstract MechOS branding wallpaper with circuit traces, HUD rings, hex patterns and blue/purple energy waves.
3. **Cyberpunk Command Bridge over Neon City** — MechOS cockpit/command bridge overlooking a futuristic city with system dashboards and mech telemetry.
4. **Mech Guardian Overlooking the Neon Megacity** — armored MechOS guardian on a rain-soaked rooftop looking over a blue/purple cyber city.
5. **MechOS Cyberpunk Command Center** — premium creator/developer workstation with mech blueprints, code, analytics and MechOS system status displays.
6. **Neon Mech over a Cybernetic Valley** — giant illuminated mech rising above a futuristic digital landscape under a star-filled sky.
7. **MechOS Neon Guardian Interface** — close-up futuristic mech face with glowing blue eyes and subtle MechOS HUD/interface elements.
8. **MechOS Futuristic System Boot Screen** — minimal dark boot-style wallpaper with centered MechOS emblem, blue/purple light streaks and system-initialization styling.
9. **MechOS Aurora over Glacier Ridge** — combat mech overlooking a frozen futuristic city beneath blue/violet aurora lighting.
10. **Futuristic Neon M Interface** — minimal centered MechOS M emblem surrounded by concentric HUD rings, circuit traces and neon particles.
11. **MechOS Orbital Command Center** — large MechOS orbital station above a glowing planet with holographic mech diagnostics and sunrise on the horizon.
12. **Neon MechOS Command Center** — expanded creator battlestation with multiple mech blueprint displays, code panels and a neon city outside.
13. **Neon Mech Factory Assembly Bay** — massive MechOS manufacturing facility with giant mechs, assembly cranes, glowing production tracks and holographic status displays.
14. **MechOS at Sunset Canyon** — lone MechOS combat mech moving through a desert canyon at sunset with glowing energy paths and distant towers.
15. **Neon MechOS Helmet Interface** — dramatic close-up mech helmet portrait with split blue/violet lighting and system-status HUD panels.
16. **Neon M Core Cyberpunk Command City** — futuristic circuit-city landscape centered around a giant glowing MechOS M-core monolith.

## Integration requirements

- package the complete collection with the installed MechOS desktop assets for **0.3.1**
- keep all wallpapers at high resolution and 16:9, with desktop-safe framing and usable negative space where practical
- preserve the MechOS dark navy/black, electric-blue and purple visual identity across the collection
- expose all 16 wallpapers through KDE Plasma's normal wallpaper picker after installation
- provide thumbnail previews so users can identify each wallpaper quickly
- set one approved wallpaper as the default MechOS 0.3.1 Desktop Mode background while keeping all 15 alternatives immediately selectable
- allow Desktop Theme Layout presets to choose an appropriate wallpaper without deleting or hiding the full collection
- support multi-monitor assignment through Plasma's normal per-display wallpaper controls
- store the wallpapers as versioned MechOS-owned assets so reviewed replacements or additions can be delivered through the MechOS OTA channel
- keep wallpaper loading lightweight: no mandatory animated backgrounds, live video loops or always-running wallpaper processes
- ensure the Live ISO may display a MechOS-branded wallpaper, but the full installed collection is primarily an installed-system desktop feature
- include the wallpaper collection in 0.3.1 release notes and visual/branding QA

## Packaging target

Planned installed path:

`/usr/share/wallpapers/MechOS/`

Each wallpaper should receive a stable descriptive filename plus a matching preview/metadata entry so future releases can update individual assets without changing the entire collection identity.
