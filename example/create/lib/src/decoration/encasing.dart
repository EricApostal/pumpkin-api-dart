// `EncasableBlock` / `EncasedBlock` / `EncasingRegistry` (host side): casings applied to shafts,
// cogwheels, pipes and belts with a right click.
//
// Kinetics and fluids register their encased variants and call [EncasingRegistry.tryEncase] from the
// `use with item` hook of the encasable block:
//
// ```dart
// final encasing = ctx.services.require<EncasingRegistry>();
// encasing.addVariant('create:shaft', EncasedVariant(
//   encasedKey: 'create:andesite_encased_shaft',
//   casingItemKey: 'create:andesite_casing',
//   handleEncasing: (c) async => switchToBlockState(c.world, c.pos, encasedState),
// ));
// // in ShaftBlock's onUseWithItem:
// final r = await encasing.tryEncase(world: e.targetWorld, pos: e.pos, state: state, heldItemKey: key);
// ```
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../common/host_bridge.dart';
import 'runtime.dart';

/// What an encasing handler gets (`handleEncasing(state, level, pos, heldItem, player, hand, ray)`).
final class EncasingContext {
  final World world;
  final BlockPos pos;
  final BState state;
  final String heldItemKey;
  final Player? player;
  final Hand? hand;

  const EncasingContext({
    required this.world,
    required this.pos,
    required this.state,
    required this.heldItemKey,
    this.player,
    this.hand,
  });
}

/// An `EncasedBlock` registered for an `EncasableBlock`.
final class EncasedVariant {
  /// The key of the encased block (`getCasing()` is [casingItemKey]'s block).
  final String encasedKey;

  /// The item that encases: `getCasing().asItem()`.
  final String casingItemKey;

  /// `handleEncasing`: changes the block (typically `KineticBlockEntity.switchToBlockState`).
  final Future<void> Function(EncasingContext c) handleEncasing;

  const EncasedVariant({required this.encasedKey, required this.casingItemKey, required this.handleEncasing});
}

/// `EncasingRegistry`.
final class EncasingRegistry {
  final Map<String, List<EncasedVariant>> _variants = {};

  /// `EncasingRegistry.addVariant(encasable, encased)`.
  void addVariant(String encasableKey, EncasedVariant variant) =>
      _variants.putIfAbsent(encasableKey, () => []).add(variant);

  /// `EncasingRegistry.getVariants(block)`.
  List<EncasedVariant> getVariants(String blockKey) => _variants[blockKey] ?? const [];

  /// `EncasableBlock.tryEncase`: [BlockUseResult.success] when a casing was applied, otherwise
  /// [BlockUseResult.tryEmptyHand] (the caller goes on with its other handling).
  Future<BlockUseResult> tryEncase({
    required World world,
    required BlockPos pos,
    required BState state,
    required String heldItemKey,
    Player? player,
    Hand? hand,
  }) async {
    for (final variant in getVariants(state.key)) {
      if (variant.casingItemKey != heldItemKey) continue;
      await variant.handleEncasing(
        EncasingContext(world: world, pos: pos, state: state, heldItemKey: heldItemKey, player: player, hand: hand),
      );
      playEncaseSound(world, pos);
      return BlockUseResult.success;
    }
    return BlockUseResult.tryEmptyHand;
  }

  /// `EncasableBlock.playEncaseSound`: the place sound of the new block, a bit lower.
  void playEncaseSound(World world, BlockPos pos) {
    final key = HostBlockGetter(world).stateAt(pos.toPos()).key;
    world.playCustomSound(
      soundName: '${blockSoundPrefix(key)}.place',
      category: SoundCategory.blocks,
      pos: (pos.x + .5, pos.y + .5, pos.z + .5),
      volume: 0.75,
      pitch: 0.8,
    );
  }
}
