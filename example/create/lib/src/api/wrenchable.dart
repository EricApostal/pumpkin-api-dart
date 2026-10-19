/// `IWrenchable` for all modules (published by the `equipment` module as a service).
///
/// Every Create block the wrench acts on registers a handler by block key. Most blocks only
/// want the defaults of `IWrenchable` (rotate on use, dismantle on sneak use):
///
/// ```dart
/// final wrench = ctx.services.require<WrenchRegistry>();
/// wrench.registerDefault(['create:shaft', 'create:cogwheel']);
/// // override only what differs:
/// wrench.register('create:belt', CallbackWrenchable(
///   onWrenched: (c) async { ...; return WrenchResult.success; },
/// ));
/// // or add behaviour on top of the default:
/// wrench.register('create:fluid_pipe', CallbackWrenchable(
///   beforeWrenched: (c) async => await tryRemoveBracket(c) ? WrenchResult.success : null,
/// ));
/// ```
///
/// The registry implements `WrenchItem.useOn` (the Create wrench) and
/// `WrenchEventHandler` (any item in the `create:wrench`-like tag `#c:tools/wrench` acting
/// like the Create wrench on Create blocks). `WrenchItem.canWrenchPickup` blocks (tag
/// `create:wrench_pickup`) are dismantled by sneak-use even without a handler.
library;

import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

export '../equipment/wrench/wrench_rotation.dart' show WrenchRotation;

/// `InteractionResult` of a wrench action, reduced to what the click handling needs.
enum WrenchResult {
  /// `SUCCESS`: the click is consumed and the arm swings.
  success,

  /// `PASS`: the click goes on (the next handler or the vanilla action runs).
  pass,

  /// `FAIL` / `CONSUME`: the click is cancelled without effect.
  fail,
}

/// What a wrench action knows (`UseOnContext` + the clicked state).
final class WrenchContext {
  final Player player;
  final World world;

  /// `getClickedPos()`.
  final BlockPos pos;

  /// `getClickedFace()`.
  final BlockDirection face;

  /// The clicked block's key and global state id.
  final String blockKey;
  final int stateId;

  /// The block state's properties (`BlockState.getValue`).
  final Map<String, String> properties;

  final Hand hand;
  final ItemStack stack;

  /// The hit position inside the block, 0..1 per axis.
  final (double, double, double) cursor;

  /// The registry (for [WrenchRegistry.defaultRotate] and the state switcher).
  final WrenchRegistry registry;

  const WrenchContext({
    required this.registry,
    required this.player,
    required this.world,
    required this.pos,
    required this.face,
    required this.blockKey,
    required this.stateId,
    required this.properties,
    required this.hand,
    required this.stack,
    required this.cursor,
  });
}

/// `IWrenchable`.
abstract interface class Wrenchable {
  /// `onWrenched(state, context)`: a plain wrench click.
  Future<WrenchResult> onWrenched(WrenchContext c);

  /// `onSneakWrenched(state, context)`: a sneaking wrench click.
  Future<WrenchResult> onSneakWrenched(WrenchContext c);
}

/// Replaces `KineticBlockEntity.switchToBlockState`: applies a rotated state to a block
/// keeping what must be kept (kinetic sources, block entity data). The kinetics module
/// installs its own through [WrenchRegistry.stateSwitcher].
typedef BlockStateSwitcher = Future<void> Function(World world, BlockPos pos, int newStateId);

/// `IWrenchable.updateAfterWrenched` / `getRotatedBlockState` hooks of one block kind.
typedef WrenchRotateState = int? Function(WrenchContext c);

/// A [Wrenchable] built from callbacks; whatever is `null` uses the `IWrenchable` default.
final class CallbackWrenchable implements Wrenchable {
  /// Runs first on a plain click; a non-null result ends the action
  /// (`IWrenchableWithBracket.onWrenched` removes the bracket here).
  final FutureOr<WrenchResult?> Function(WrenchContext c)? beforeWrenched;

  /// Replaces the plain click completely.
  final Future<WrenchResult> Function(WrenchContext c)? onWrenchedOverride;

  /// Replaces the sneak click completely.
  final Future<WrenchResult> Function(WrenchContext c)? onSneakOverride;

  /// Replaces `getRotatedBlockState`: returns the rotated state id, or `null` for no change.
  final WrenchRotateState? rotatedState;

  /// Runs after the default dismantle breaks the block (e.g. to clean up).
  final FutureOr<void> Function(WrenchContext c)? afterDismantled;

  /// Replaces `updateAfterWrenched` (default: `Block.updateFromNeighbourShapes`, which the
  /// host does when the state is set with neighbour updates).
  final int Function(WrenchContext c, int rotatedStateId)? updateAfterWrenched;

  const CallbackWrenchable({
    this.beforeWrenched,
    this.onWrenchedOverride,
    this.onSneakOverride,
    this.rotatedState,
    this.afterDismantled,
    this.updateAfterWrenched,
  });

  @override
  Future<WrenchResult> onWrenched(WrenchContext c) async {
    final before = await beforeWrenched?.call(c);
    if (before != null) return before;
    final override = onWrenchedOverride;
    if (override != null) return override(c);
    return c.registry.defaultRotate(c, this);
  }

  @override
  Future<WrenchResult> onSneakWrenched(WrenchContext c) async {
    final override = onSneakOverride;
    if (override != null) return override(c);
    final result = await c.registry.defaultDismantle(c);
    if (result == WrenchResult.success) await afterDismantled?.call(c);
    return result;
  }
}

/// The registry of wrenchable blocks.
final class WrenchRegistry {
  final Map<String, Wrenchable> _handlers = {};

  /// Set by the equipment module: `IWrenchable.onWrenched` (rotate with [custom] hooks).
  Future<WrenchResult> Function(WrenchContext c, CallbackWrenchable? custom) _rotate =
      (c, custom) async => WrenchResult.pass;

  /// Set by the equipment module: `IWrenchable.onSneakWrenched`.
  Future<WrenchResult> Function(WrenchContext c) _dismantle = (c) async => WrenchResult.pass;

  /// Installs the default implementations (called by the equipment module).
  void installDefaults({
    required Future<WrenchResult> Function(WrenchContext c, CallbackWrenchable? custom) rotate,
    required Future<WrenchResult> Function(WrenchContext c) dismantle,
  }) {
    _rotate = rotate;
    _dismantle = dismantle;
  }

  /// `IWrenchable.onWrenched`: rotate (using the hooks of [custom], if any), check
  /// `canSurvive`, switch state, play the sound.
  Future<WrenchResult> defaultRotate(WrenchContext c, [CallbackWrenchable? custom]) => _rotate(c, custom);

  /// `IWrenchable.onSneakWrenched`: break the block, hand the drops to the player, play the sound.
  Future<WrenchResult> defaultDismantle(WrenchContext c) => _dismantle(c);

  /// Replaces `KineticBlockEntity.switchToBlockState` (default: a plain state change).
  BlockStateSwitcher? stateSwitcher;

  /// Registers [handler] for the block [blockKey] (`create:shaft`).
  void register(String blockKey, Wrenchable handler) => _handlers[blockKey] = handler;

  /// Registers [handler] for all of [blockKeys].
  void registerAll(Iterable<String> blockKeys, Wrenchable handler) {
    for (final k in blockKeys) {
      _handlers[k] = handler;
    }
  }

  /// Registers the `IWrenchable` defaults (rotate / dismantle) for [blockKeys].
  void registerDefault(Iterable<String> blockKeys) => registerAll(blockKeys, const CallbackWrenchable());

  /// The handler of [blockKey], or `null` when the block is not a `IWrenchable`.
  Wrenchable? of(String blockKey) => _handlers[blockKey];

  bool isWrenchable(String blockKey) => _handlers.containsKey(blockKey);

  Iterable<String> get blocks => _handlers.keys;
}
