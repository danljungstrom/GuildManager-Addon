# Guildion addon changelog

The newest version is on top. The heading of the top entry, `## Version` in
`Guildion/Guildion.toc` and the "Current version" line in `docs/ADDON.md` name the same
version; `tests/units/version_test.lua` and `tools/release.sh` both refuse anything else.

## 0.5.0

- The addon is now called **Guildion**: the folder is `Guildion` and the command is `/gc` (or
  `/guildion`). Settings and stored sessions of an earlier GuildManager install are not carried
  over; export or note them before you switch.
- `/gc export guild`, or **Guild roster** on the Sessions tab, copies the guild roster (names,
  ranks, levels, classes and public notes, offline members included) for the app's roster
  import. Officer notes are never read. The addon turns "Show offline members" on for the read
  and puts your setting back. It refuses with a try-again message while the client has no roster rows yet, and chat says so when the export holds fewer members than the client counted.
- Party and solo logs now record the full `First Last` name on WoW Forever (they recorded the
  first name only), for the recorder, party members and the recorder's own loot. A session saved
  by an older version still resumes.

## 0.4.0

- Runs on the WoW Forever client (`## Interface: 16001, 11509`); Classic Era 1.15.9 still loads it.
- Wears the client's own window frame: the helmet in the round portrait, the title bar, the red
  close button, the views as icon tabs down the right edge, the game's buttons, check boxes,
  dropdown and inset panels.
- A gear tab opens and closes the settings, and the addon has a page in Esc > Options > AddOns
  that opens the settings or the window.
- A Spartan helmet icon in the AddOns list and on the minimap button, which now sits on the
  minimap's edge like other addons' buttons.
- The idle Current tab says when recording starts by itself, or that automatic recording is off.
- A relog onto another character no longer goes on recording into the first character's raid:
  that session ends where it was last seen, and the new character records its own.
- A raid that disbanded while you were offline ends at your logout, so the time away is no
  longer counted as time in the raid.
- An item the master looter takes back in Gargul after the raid is also taken out of that
  raid's log, and the bridge now hooks Gargul after a `/reload` too.
- Loot is linked to the boss kill it dropped from, never to a wipe.
- Chat says when the oldest stored raid is removed to make room.
- The window's side tabs stay on screen when it is dragged to the right edge.

## 0.3.1

- Declares the Classic Era 1.15.9 client (`## Interface: 11509`), so the game no longer lists the
  addon as out of date. Nothing else changed.

## 0.3.0

- The Gargul bridge: while Gargul is installed, the awards it makes during the raid are recorded
  and travel in the same string as the raid log, so an officer no longer pastes a second export.
  Rolls come along, including the ones Gargul deletes from awards older than five weeks.
- Awards made by another master looter are picked up too, and an export sweeps Gargul's own
  history for the session's window, so an addon enabled mid-raid still catches the evening.
- The Current tab counts the awards beside the loot, and `/gc help` says which Gargul was found,
  or that none was.
- Nothing is sent to Gargul and nothing of Gargul's is written: its award history is read only.
- Without Gargul the addon behaves exactly as before, and says nothing about it.

## 0.2.0

- The window: `/gc` or the minimap button opens it. Sessions lists the stored raids with Export
  and Delete; Current shows the raid being recorded with Start, Stop, Mark kill and Mark wipe.
- Export ends in a copy box in the window's footer. The 0.1.0 popup is gone.
- Mark kill and Mark wipe close a pull by hand when the game never reports the end of a fight. A
  real result that arrives later replaces the mark.
- A settings window (the cogwheel): loot quality threshold, auto-record, the prompt to export, the
  minimap button, 5-player dungeons for testing.
- When a raid ends the window opens on its row. It waits for the end of combat and never takes
  the keyboard. A setting turns it off.
- `/gc` alone used to print the status and the command list; that is `/gc help` now.
- Saved data stays at version 1: 0.1.0 can still read it after a rollback.

## 0.1.0

- Records raid sessions (attendance, pulls, loot) and exports them as a `GM1:` string with
  `/gc export`. No window yet.
