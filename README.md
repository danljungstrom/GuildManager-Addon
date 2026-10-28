# Guildion

An in-game raid recorder for the Guildion web app. It records who was in the raid, every
pull with its result and who was there, and the loot, then exports the evening as one string an
officer pastes into the guild's site.

The addon only records and exports. It reads nothing from the web app and has no network access.

Client: WoW Forever (interface 16001) and Classic Era 1.15.9 (11509).

## Install

1. Download `Guildion-x.y.z.zip` from the [releases](https://github.com/danljungstrom/Guildion-Addon/releases)
(or from CurseForge) and unzip it into your client's
`Interface/AddOns/` folder, so that `Interface/AddOns/Guildion/Guildion.toc` exists.
2. Restart the game (a `/reload` does not pick up a new addon) and tick **Guildion** in the
AddOns list on the character screen.

## Use

1. Join the raid and zone in. Recording starts by itself when your raid group enters a raid
instance (`Guildion: recording started.`).
2. Raid. Joins and leaves, every pull with its result and who was there, and loot of Rare quality
and better are saved as they happen, so a `/reload`, a logout or a disconnect loses nothing,
and a session seen less than 30 minutes ago resumes on relog. Only a client crash loses what
was recorded since the last clean exit.
3. The session ends when you leave the group, or 30 minutes after you left the instance. Chat
shows `Raid logged: 8 kills, 3 wipes. /gc export`, and the window opens on the raid's row
(after combat, and without taking the keyboard; a setting turns this off).
4. Press **Export** (or type `/gc export`). The string appears selected in the window's footer:
press Ctrl+C, then paste it into the raid's **Raid log** dialog on your guild's site. ESC
leaves the copy box, a second ESC closes the window.

The last 20 sessions are kept, account-wide, so any of your characters can export them.

## Guild roster

`/gc export guild`, or **Guild roster** on the Sessions tab, copies the guild roster: names,
ranks, levels, classes and public notes, offline members included. Paste it on your guild
site's roster import page, under **From the game**, to bring the site's roster in line with the
guild. Officer notes are never read. The addon turns "Show offline members" on for the read and
puts your setting back.

## The window

`/gc` or a left click on the minimap button opens it. It can be moved, and resized from its
bottom right corner; size and place are remembered. ESC or the red X closes it. The views are
the icon tabs down its right edge.

- **Sessions** lists the stored raids, newest first: date, instances, length, kills / wipes,
players, loot. Choose a row, then **Export** or **Delete**.
- **Current** shows the raid being recorded: where, for how long, who is present, every pull and
the loot. **Start** and **Stop** do what `/gc start` and `/gc stop` do. **Mark kill** and
**Mark wipe** close the pull in progress by hand, for a boss whose end the game never reports;
if the game reports the real result afterwards, that result replaces the mark.
- The gear tab opens or closes the settings.
- The minimap button: left click opens or closes the window, right click opens a menu, a drag
moves it round the minimap.

## Slash commands

`/gc` and `/guildion` are the same command. If another addon owns `/gc`, use the long form.

| Command | Does |
| ---------------- | --------------------------------------------------------------------------------- |
| `/gc` | Open or close the window |
| `/gc help` | Status and this list, in chat |
| `/gc export` | The session being recorded, else the newest stored one, as a string to copy |
| `/gc export raw` | The same log as uncompressed JSON, for debugging |
| `/gc export guild` | The guild roster, to paste on the site's roster import page |
| `/gc start` | Record now, whatever the group or zone. Ends with `/gc stop`, or 30 minutes offline |
| `/gc stop` | End the recording. Auto-record stays off until you leave the group or the instance |

## Settings

The gear tab, **Settings** in the minimap button's menu, or **Open settings** on the addon's page
in Esc > Options > AddOns. A change applies at once.

| Setting | Default | Meaning |
| ---------------- | ------- | -------------------------------------------------------------------- |
| Loot quality | Rare | Lowest item quality recorded |
| Auto-record | on | Start a session by itself when your raid group enters a raid |
| Prompt to export | on | Open the window on the raid's row when a recording ends |
| Minimap button | on | Show the minimap button |
| Dungeon testing | off | Also record in a party inside a 5-man dungeon, to test without a raid |

## Gargul

While [Gargul](https://github.com/papa-smurf/Gargul) is installed, the awards it makes during the
raid travel in the same string, rolls included, so an officer does not paste a Gargul export as
well. Nothing is sent to Gargul and nothing of Gargul's is changed.

## Development

The addon is developed in the Guildion repository, with its test suite; this repository
receives each release. Issues and suggestions are welcome here.

## License

MIT, see [LICENSE](LICENSE). The bundled LibDeflate is zlib-licensed and LibStub is public domain.
The icon is "Spartan helmet" by Delapouite, [game-icons.net](https://game-icons.net), CC BY 3.0.
