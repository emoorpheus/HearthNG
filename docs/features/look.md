# Look

Everything in **Settings, Look**. Changes show at once on the home screen.

![Look: Theme group](../screenshots/settings-theme.jpg)

## Preset

**Preset** is the first row of *Look*. It sets the colours and decorations of the home screen in one go: theme, background, icon style, icon outline, names, the widget's colour, shadow and thickness, the bottom fade and quiet mode. It does not change sizes or places (icon size and gap, name size and font, widget size, place and font, margins, rows), your apps or the weather; only *OLED (minimal)* also sets four settings outside the look (below).

| Preset | What it sets | Why |
|---|---|---|
| **Standard** | The values of a fresh install. *Reset Hearth visual settings to default* also reads Standard. | A known starting point. |
| **OLED** | OLED black theme on a flat black background (no photo, no gradient, no bottom fade), *Dark mono* grey icons, no icon outline (the selected icon keeps its ring), the name only under the selected icon, widget without shadow, thinner (300) and at 80 %, quiet mode after 20 s and dimmed by 50 % after 20 s more, OLED shift on. | On OLED a black pixel is off, so only what you need is lit: one-colour icons, one name, no glow. |
| **OLED (minimal)** | The OLED look, plus four settings outside it: icons at 70 %, no widget (clock, date and weather), the weather off and Hearth's screen saver off (the TV's own screen saver still works). | As little lit as possible: only the apps, smaller, and at idle the TV's own screen saver. |
| **Night** | Like OLED, but dimmer: *Soft mono* icons at 70 %, grey names, a grey widget at 60 %, quiet mode after 10 s and dimmed by 70 %. | For a dark room. |
| **Minimal** | The *Warm graphite* theme's own background, the original pictures in the *Minimal* icon style (no borders), no names, no bottom fade, widget without shadow and thinner. | Calm and plain, in colour. |
| **Gallery** | The bundled photos as a slideshow, the original pictures, apps hide after 10 s without a key and the screen is not dimmed, widget with a full shadow and thicker (500). | The TV as a picture frame. |

When your look matches no preset, the row reads **Your own**. Choosing a preset keeps a copy of your own look (with its wallpaper); stepping back to **Your own** brings that copy back. If you change something after choosing a preset, the row reads *Your own* again and that new look is the one kept next time.

*OLED (minimal)* notes what its four settings were. Leaving it (for another preset or *Your own*) puts each of them back, except one you changed since: that one stays. Hearth's screen saver is turned off and on again the way its own row (*Custom Screen Saver*) does it, through the TV; if turning it on again fails, it stays off and a notification says why. *Reset Hearth visual settings to default* drops the note (icon size, widget and weather go back to their defaults; Hearth's screen saver stays as it is).

## Theme

A theme sets the colours of the tiles, the text and the background. Six are built in: **OLED black** (pure black, the starting choice), **Calm blue-grey**, **Midnight blue**, **Deep forest**, **Deep teal** and **Warm graphite**. Press Left or Right on **Current theme** to try them.

On a rooted TV you can also load your own theme:

- **OK** on *Current theme* loads a theme zip from the themes folder on the TV.
- **Export theme base** writes a starter zip with your apps (in their order), names and icons. **Start here:** this is the only way to get your app list and icons into a theme, so export first, then change the zip. Copy it to a computer, change it (or ask an AI helper to), and put it back in the themes folder.
- **Save this theme** keeps a loaded theme inside Hearth. **Delete this theme** removes it again.

How to make a theme: [Custom themes](../theme/theme-guide.md).

## Icons

![Look: Icons group](../screenshots/settings-icons.jpg)

- **Icon size, icon spacing, icon shape.**
- **Icon style:** *Original* (the real picture), *Minimal*, *Dark mono*, *Soft mono*, *Accent mono*, *Gradient mono* (one-colour shapes), *Tinted tile* (the real picture on a coloured tile) and *Glyph* (just the shape, with no tile; the highlighted icon only grows, and *Icon tile: Dark* gives dark shapes and labels, *Light* gives light ones). These are experimental.
- **Icon tile:** a *Dark* tile with a light shape, or a *Light* tile with a dark shape.
- **Icon colour:** the colour of the shapes (follows the theme at first).
- **Icon opacity:** lower numbers let the wallpaper show through.
- **Icon outline:** the thin line round every icon. Off: no line; the selected icon keeps its ring.

## Home row

![Look: Home row group](../screenshots/settings-home-row.jpg)

**Rows of apps** (one or two), **Row scroll speed** (how fast a held arrow runs), **When Home is pressed**, **Side margin** and **Bottom margin**, **Show input status**, the switches for the **LG Home** and **System Settings** tiles, and **Hide the Hearth Settings tile**. Before it hides the tile, HearthNG makes you try the way back once: hold OK on any app, press Up and choose the gear (**Hearth Settings**) above the tile. Once the tile is hidden, that is how you open the settings. Pressing Down five times on the Home screen (when there is no row below) shows the tile again until Hearth restarts.

## Labels (the app names)

Switch the names under the icons on or off, and choose their colour, font, size and thickness. **Name only under the selected icon** hides the other names, so less is lit on the screen.

## Quiet mode, Favourites, Recent apps

Quiet mode and OLED shift are explained in [Using Hearth](using.md#quiet-mode-and-oled-care). *Favourites* has its own side and bottom margin. *Recent apps* has the panel size (Small, Medium, Large).

## Reset

**Reset Hearth visual settings to default** puts the theme, wallpaper, look, quiet mode, clock and weather back to the starting values (the *Standard* preset). Your apps, their order and favourites are not touched. After updating from 1.x, **Restore my settings from before the update** brings back your old look once.

![Dark mono icons](../screenshots/home-dark-mono.jpg)
![Warm graphite theme](../screenshots/home-warm.jpg)
![Teal theme](../screenshots/home-teal.jpg)
