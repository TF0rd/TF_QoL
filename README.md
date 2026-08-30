# TF QoL

A lightweight World of Warcraft addon of quality-of-life tweaks for WoW 12.0 (Midnight), with its own Catppuccin Mocha-themed settings panel.

## Modules

Open the settings panel with `/tf` and toggle each module under its sidebar tab.

### Character Viewer

One window with one row per character: item level, Great Vault progress, currencies, gold, and warband bank gold — plus per-character currency tooltips, seasonal currency cap detection, item level tier coloring, and filters. A drop-in replacement for the retired Wowthing_Viewer addon. *Enabled by default.*

### Macros

Auto-updating account macros:

- **TFHealthPotion** / **TFDrink** — inventory-, level-, and spec-aware macros that rebuild when you loot, level up, or change spec.
- **Power Infusion helper** — target a player and run `/tf pi` (or press the **TFSetPI** macro) to bake their name into your **PI** macro (mouseover > that player > you). The macro body is an editable template in the settings: `{target}` is replaced with the baked name, so you can add, remove, or edit lines (e.g. drop the Shadow Word: Madness cast or spec-gate the trinket line).

### Item Upgrade Reminder

Alerts you when equipped items can be upgraded with zero crests, using the high-watermark system with Midnight Season 2 upgrade tracks. On-screen text with configurable font, position, and test mode.

### Blizzard Frames

Hides the Micro Menu and Bags bar, and adds a frame mover for Blizzard panels: drag by the title bar, CTRL + mousewheel to scale, middle-click to reset a window's position and scale.

### Action Bar Toggle

A keybind that shows/hides action bars 1–8. Supports Blizzard bars, EllesmereUI, and NorskenUI frames.

### Mount Actions

Keybinds for the Repair Mount and Auction House Mount, using standard WoW bindings so they sync with the Key Bindings panel.

### Potion Alert

A floating "Potion Ready" indicator when an endgame combat potion is off cooldown, with instance-type and combat filters and an optional sound.

### Lust Alert

A floating indicator when Bloodlust/Heroism (or an equivalent) is available — i.e. no sated/exhaustion debuff is active. Same filters as Potion Alert, plus an option to only show it on lust-capable classes (Shaman, Mage, Hunter, Evoker).

### Stealth Indicator

A floating "Stealth" label while the player is stealthed.

### OCE Tag

Flags Oceanic-realm groups with a red [OCE] tag in the Premade Groups finder.

### Group Joined Reminder

Prints a chat message when you join a Mythic+ or Mythic raid group, showing the dungeon/raid name and group name.

### CVar Browser

Tracks the CVars you change in-game and lists them in the GUI so you can review and revert your modifications. *Enabled by default.*

### Mute Sounds

Mute game sounds by preset category (mounts, trinkets, emotes) or by custom sound file ID. Changes apply immediately.

### Shared Action Bars

Automatically enforces Shared Action Bars on every talent loadout.

## Settings

The settings panel (`/tf`) is a custom Catppuccin Mocha-themed GUI with:

- **Test Mode** — previews all enabled alert modules at once so you can position them
- **Global Font Family** — apply any LibSharedMedia font to all module displays
- **Slug Font Rendering** — thick outline on module text for readability
- Per-module font size, position, and optional sound
- **50 built-in sound callouts** (Bloodlust, Innervate, Pain Suppression, …) selectable in any alert module

## Slash Commands

| Command   | Action                          |
| --------- | ------------------------------- |
| `/tf`     | Open the settings panel         |
| `/tf char`| Toggle the Character Viewer     |
| `/tf pi`  | Bake targeted player into the PI macro |

## Installation

1. Download or clone this repo
2. Copy the `TF_QoL` folder into your WoW addons directory:
   ```
   World of Warcraft\_retail_\Interface\AddOns\TF_QoL
   ```
3. Enable the addon from the character select screen

## License

[MIT](LICENSE)
