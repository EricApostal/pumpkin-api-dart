/// The public API of the depot part of the processing module (re-exported by
/// `lib/src/api/processing.dart`).
///
/// A depot belongs to the conveyance module, but the machines of this module (the mechanical arm)
/// interact with it. [DepotApi] is the service they use: the conveyance module registers an
/// accessor for each depot block, and the machines read or fill the depot through it without
/// importing the conveyance internals.
library;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/pos.dart';
import '../common/stack.dart';

/// The item state of a depot: the held item and its processing output buffer.
final class DepotContents {
  final PStack held;
  final List<PStack> outputs;

  const DepotContents(this.held, this.outputs);

  static const DepotContents empty = DepotContents(PStack.empty, []);
}

/// One depot, seen by the machines of the processing module.
abstract interface class DepotAccess {
  /// Whether a depot or weighted ejector block entity is present at the position.
  bool get isPresent;

  /// Whether the block is the weighted ejector (`create:weighted_ejector`).
  bool get isEjector;

  /// `DepotBehaviour.getHeldItemStack()` and the output buffer.
  DepotContents contents();

  /// `DepotBehaviour.insert(stack)`: the remainder.
  PStack insert(PStack stack, {bool simulate = false});

  /// Takes up to [amount] items off the depot (held item first, then the output buffer).
  PStack extract(int amount, {bool simulate = false});

  /// `EjectorBlockEntity.setTarget`: the target of the launcher.
  void setTarget(int horizontalDistance, int verticalDistance);

  /// `EjectorBlockEntity.activate`: launches on the next tick.
  void activate();

  /// `EjectorBlockEntity.deployElytra`: sets the player gliding
  /// (`EntityHack.setElytraFlying`).
  void deployElytra(Player player);

  /// `EjectorAwardPacket.applySettings`: `AllAdvancements.EJECTOR_MAXED.awardTo(player)`.
  void awardMaxed(Player player);

  /// `EjectorPlacementPacket.handle`: the horizontal facing the client picked for the
  /// ejector.
  void setFacing(int facing);
}

/// The registry of depot accessors by block key (`create:depot`, `create:weighted_ejector`).
/// Provided by `DepotPart`; the conveyance module fills it in `onServerLoaded`.
final class DepotApi {
  final Map<String, DepotAccess Function(String worldId, Pos pos)> _factories =
      {};

  /// Registers the accessor of the depot block [blockKey].
  void register(
    String blockKey,
    DepotAccess Function(String worldId, Pos pos) factory,
  ) => _factories[blockKey] = factory;

  /// The accessor of the depot of block [blockKey] at [pos], or `null` when the block is not a
  /// depot or the accessor is not registered yet.
  DepotAccess? at(String worldId, Pos pos, String blockKey) =>
      _factories[blockKey]?.call(worldId, pos);

  /// The accessor of whichever depot block (`create:depot`, `create:weighted_ejector`) is at
  /// [pos], or `null` when there is none. Used by the ejector payloads, which only know the
  /// position they were sent for.
  DepotAccess? accessAt(String worldId, Pos pos) {
    for (final factory in _factories.values) {
      final access = factory(worldId, pos);
      if (access.isPresent) return access;
    }
    return null;
  }
}
