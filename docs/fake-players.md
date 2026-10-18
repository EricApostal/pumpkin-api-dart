# Fake players

`fake-player.wit`: server side actors that act like players for items, blocks,
entities, events and protection checks, with no connection. Wrappers:
`fake_players.dart` (`FakePlayers`, `FakePlayerActions`). Permission:
`fake-players`.

```dart
final bot = FakePlayers.create(world, 'Deployer');
bot.moveTo(null, (x + .5, y, z + .5), yaw: 0, pitch: 90);
await bot.inventory.give(await ItemStacks.of('iron_pickaxe'));
final broke = await bot.breakBlock(pos, BlockDirection.up);
await bot.useItemOnBlock(pos, BlockDirection.up);
FakePlayers.remove(bot);
```

* A fake player is the ordinary `Player` (`isFakePlayer`), so inventory, held
  item, game mode, permissions and effects work. Calls that send something to a
  client do nothing. It is not in the tab list, not counted online, not saved
  and not ticked.
* Actions fire the events of a connected player (block break, interact, use
  item, damage) with the fake player as the player.
* `startBreaking` / `continueBreaking` return `BreakProgress` (`Rejected`,
  `InProgress(f)`, `Broken`). `breakBlock` loops once per tick; it waits for
  timers, so the callback's lent resources (`server`, `sender`) are gone after
  the first wait ([async.md](async.md)). The fake `Player` itself is owned and
  stays valid.
* Errors (uuid taken, out of reach) throw `HostException`. Remove fake players
  you do not need; they are not removed on unload by themselves, so use
  `context.onUnload(() => FakePlayers.remove(bot))`.
