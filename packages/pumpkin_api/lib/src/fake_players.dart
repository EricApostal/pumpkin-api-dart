import 'dart:async';

import 'bindings.g.dart' as generated;
import 'bindings.g.dart';
import 'host_result.dart';
import 'scheduler.dart';

/// Fake players (`fake-player.wit`): server side actors that act like players
/// for item, block and entity handling, events and protection checks, without a
/// connection. They are not saved, not ticked, not in the tab list. Needs
/// [Permissions.fakePlayers].
///
/// ```dart
/// final bot = FakePlayers.create(world, 'Deployer');
/// bot.moveTo(world, (x + .5, y, z + .5), yaw: 0, pitch: 0);
/// await bot.useItemOnBlock(pos, BlockDirection.up);
/// FakePlayers.remove(bot);
/// ```
///
/// A fake player is an ordinary `Player` (`isFake` is true), so the inventory,
/// held item, game mode and effect functions of `Player` work on it. Remove
/// fake players you no longer need.
abstract final class FakePlayers {
  /// Creates a fake player in [world] at the world origin; move it before it
  /// acts. The uuid is the offline uuid of [name] unless [id] is given. Throws
  /// a [HostException] if a player already has the uuid.
  static Player create(World world, String name, {Uuid? id}) => unwrapHost(
    generated.fakePlayer.createFakePlayer(worldRef: world, profileName: name, id: id),
    'Creating the fake player $name',
  );

  /// Stops and unregisters [player].
  static void remove(Player player) =>
      unwrapHost(generated.fakePlayer.removeFakePlayer(player: player), 'Removing the fake player');
}

/// Actions of a fake player.
extension FakePlayerActions on Player {
  /// Whether this is a fake player.
  bool get isFakePlayer => isFake();

  /// Moves the fake player, into [world] if given and not the current one.
  void moveTo(
    World? world,
    (double, double, double) pos, {
    double yaw = 0,
    double pitch = 0,
  }) => unwrapHost(
    generated.fakePlayer.setFakePlayerLocation(
      player: this,
      worldRef: world,
      pos: pos,
      yaw: yaw,
      pitch: pitch,
    ),
    'Moving the fake player',
  );

  /// Sets whether the fake player sneaks (skips the use of the clicked block
  /// when holding an item).
  void setSneaking(bool sneaking) => unwrapHost(
    generated.fakePlayer.setFakePlayerSneaking(player: this, sneaking: sneaking),
    'Setting sneaking',
  );

  /// Right clicks the block [pos] on [face] with the item in [hand]. [cursor]
  /// is where on the face the click lands (0 to 1 per axis). Returns whether
  /// anything changed. Throws a [HostException] when out of reach.
  Future<bool> useItemOnBlock(
    BlockPos pos,
    BlockDirection face, {
    Hand hand = Hand.right,
    (double, double, double) cursor = (0.5, 0.5, 0.5),
  }) => unwrapHostAsync(
    generated.fakePlayer.useItemOnBlock(player: this, pos: pos, face: face, hand: hand, cursor: cursor),
    'Using an item on a block',
  );

  /// Uses the item in [hand] in the looking direction (eating, throwing, bows).
  Future<void> useHeldItem({Hand hand = Hand.right}) => unwrapHostAsync(
    generated.fakePlayer.useItem(player: this, hand: hand),
    'Using an item',
  );

  /// Attacks [target] with the held item at full strength.
  Future<void> attack(Entity target) => unwrapHostAsync(
    generated.fakePlayer.attackEntity(player: this, target: target),
    'Attacking an entity',
  );

  /// Right clicks [target] with the item in the main hand.
  Future<void> interact(Entity target) => unwrapHostAsync(
    generated.fakePlayer.interactEntity(player: this, target: target),
    'Interacting with an entity',
  );

  /// Starts breaking the block at [pos]. See [BreakProgress].
  Future<BreakProgress> startBreaking(BlockPos pos, BlockDirection face) =>
      unwrapHostAsync(
        generated.fakePlayer.startBreakBlock(player: this, pos: pos, face: face),
        'Starting to break a block',
      );

  /// Advances the break by one tick.
  Future<BreakProgress> continueBreaking() => unwrapHostAsync(
    generated.fakePlayer.continueBreakBlock(player: this),
    'Continuing to break a block',
  );

  /// Stops breaking the current block.
  Future<void> stopBreaking() => unwrapHostAsync(
    generated.fakePlayer.stopBreakBlock(player: this),
    'Stopping to break a block',
  );

  /// Breaks the block at [pos] like a survival player: starts, then continues
  /// once per tick for at most [maxTicks]. Returns whether the block broke.
  /// Needs a tick wait between calls, so only the host calls before the first
  /// wait are covered by the callback's server-lent resources (see
  /// `docs/async.md`).
  Future<bool> breakBlock(
    BlockPos pos,
    BlockDirection face, {
    int maxTicks = 600,
  }) async {
    var progress = await startBreaking(pos, face);
    for (var tick = 0; tick < maxTicks; tick++) {
      switch (progress) {
        case BreakProgressBroken():
          return true;
        case BreakProgressRejected():
          return false;
        case BreakProgressInProgress():
          await Future<void>.delayed(1.ticks);
          progress = await continueBreaking();
      }
    }
    await stopBreaking();
    return false;
  }
}
