import 'dart:async';

import 'bindings.g.dart' as generated;
import 'bindings.g.dart';
import 'block_registry_core.dart' as core show BlockBox;
import 'blocks.dart' show registryKeysMatch;
import 'events.dart';
import 'events.g.dart';
import 'host_result.dart';

/// The hooks of one custom block (`block-callbacks.wit`): the logic of a block
/// that a plugin registered with `BlockRegistries.host`.
///
/// Give a handler for each hook the block needs. A block only costs the host
/// something for the hooks it has, so leave the others `null`. Handlers get
/// the events of this block only (the `block` key is compared for you). Event
/// data carries `stateIndex`: add it to the block's `baseStateId` for the
/// state id (`docs/block-registry.md`).
///
/// ```dart
/// context.registerBlockBehavior(
///   'my_plugin:lamp',
///   BlockBehavior(
///     onNeighborUpdate: (server, e) => e.targetWorld
///         .setRedstoneOutput(e.pos, weak: 15),
///     onCanPlace: (server, e) => e.face != BlockDirection.down,
///   ),
/// );
/// ```
///
/// The `neighbor-update`, `update-shape`, `entity-collision` and `entity-step`
/// hooks run very often: keep their handlers fast.
final class BlockBehavior {
  /// A neighbour of the block changed.
  final FutureOr<void> Function(Server server, CustomBlockNeighborUpdateEventData event)? onNeighborUpdate;

  /// The block was set in the world, by a player or not (`event.player`).
  /// Sets both the `placed` and `player-placed` hooks.
  final FutureOr<void> Function(Server server, CustomBlockPlacedEventData event)? onPlaced;

  /// The block was replaced by another block or moved.
  final FutureOr<void> Function(Server server, CustomBlockStateReplacedEventData event)? onStateReplaced;

  /// A player broke the block.
  final FutureOr<void> Function(Server server, CustomBlockBrokenEventData event)? onBroken;

  /// A tick scheduled with `World.scheduleTick` is due.
  final FutureOr<void> Function(Server server, CustomBlockTickEventData event)? onScheduledTick;

  /// The block got a random tick.
  final FutureOr<void> Function(Server server, CustomBlockTickEventData event)? onRandomTick;

  /// An entity is inside the block.
  final FutureOr<void> Function(Server server, CustomBlockEntityCollisionEventData event)? onEntityCollision;

  /// An entity stands on or walks over the block.
  final FutureOr<void> Function(Server server, CustomBlockEntityStepEventData event)? onEntityStep;

  /// Asked before the block is placed; return `false` to refuse. `event.canPlace`
  /// is the answer so far.
  final FutureOr<bool> Function(Server server, CustomBlockCanPlaceEventData event)? onCanPlace;

  /// A neighbour changed and the block updates its shape; return the new
  /// `stateIndex` of the block, or `null` to keep `event.newStateIndex`.
  final FutureOr<int?> Function(Server server, CustomBlockUpdateShapeEventData event)? onUpdateShape;

  /// Redstone reads the weak power (0 to 15) of the block. Needs no stored
  /// output (`World.setRedstoneOutput`). Runs whenever redstone looks at the
  /// block.
  final FutureOr<int> Function(Server server, CustomBlockRedstonePowerEventData event)? onWeakPower;

  /// Redstone reads the strong power (0 to 15) of the block.
  final FutureOr<int> Function(Server server, CustomBlockRedstonePowerEventData event)? onStrongPower;

  /// A comparator reads the block; return the analog output (0 to 15) or
  /// `null` for none.
  final FutureOr<int?> Function(Server server, CustomBlockComparatorOutputEventData event)? onComparatorOutput;

  /// The shape depends on more than the state (a copycat taking the shape of
  /// another block). Asked for the collision, selection and visual shape
  /// (`event.kind`); return the boxes, or `null` to keep `event.shapes` (the
  /// shapes of the block's [BlockDefinition] rules). The answer is cached per
  /// position: call `World.invalidateShape` when it changes.
  final FutureOr<List<core.BlockBox>?> Function(Server server, CustomBlockShapeEventData event)? onShape;

  /// The collision shape for one entity, when it differs from the block's own
  /// shape (a minecart assembler a minecart passes through but a player stands
  /// on). Asked for every move of an entity inside the block; return the boxes,
  /// or `null` to keep `event.shapes` (the shapes the block would use). Not
  /// cached: the answer depends on the entity.
  final FutureOr<List<core.BlockBox>?> Function(
    Server server,
    CustomBlockCollisionShapeEventData event,
  )?
  onEntityCollisionShape;

  /// A player right clicks the block, with or without an item
  /// (`event.withItem`). Return the result; `BlockUseResult.pass` lets the item
  /// act. Sets both use hooks unless [onUseWithItem] or [onUseWithoutItem]
  /// is given for that case.
  final FutureOr<BlockUseResult> Function(Server server, CustomBlockUseEventData event)? onUse;

  /// Like [onUse] for a right click holding an item only.
  final FutureOr<BlockUseResult> Function(Server server, CustomBlockUseEventData event)? onUseWithItem;

  /// Like [onUse] for a right click with an empty hand only.
  final FutureOr<BlockUseResult> Function(Server server, CustomBlockUseEventData event)? onUseWithoutItem;

  /// A player left clicks the block (starts digging).
  final FutureOr<void> Function(Server server, CustomBlockAttackEventData event)? onAttack;

  /// A player picks the block (middle click). Return the item, or `null` for
  /// none.
  final FutureOr<ItemStack?> Function(Server server, CustomBlockCloneItemEventData event)? onCloneItem;

  /// A player is about to break the block. Return `false` to cancel.
  final FutureOr<bool> Function(Server server, CustomBlockPlayerWillDestroyEventData event)? onPlayerWillDestroy;

  /// The friction (0.6 for most blocks). Cached per position.
  final FutureOr<double> Function(Server server, CustomBlockPhysicsEventData event)? onFriction;

  /// The speed factor (1.0 normally). Cached per position.
  final FutureOr<double> Function(Server server, CustomBlockPhysicsEventData event)? onSpeedFactor;

  /// The jump factor (1.0 normally). Cached per position.
  final FutureOr<double> Function(Server server, CustomBlockPhysicsEventData event)? onJumpFactor;

  /// Whether an entity can destroy the block (explosions, the wither).
  final FutureOr<bool> Function(Server server, CustomBlockConditionEventData event)? canEntityDestroy;

  /// Whether mobs can path through the block; `event.condition` is
  /// `pathfindableLand`, `pathfindableWater` or `pathfindableAir`.
  final FutureOr<bool> Function(Server server, CustomBlockConditionEventData event)? isPathfindable;

  /// Whether redstone wire connects to the block.
  final FutureOr<bool> Function(Server server, CustomBlockConditionEventData event)? canConnectRedstone;

  /// An entity landed on the block after a fall. Return the fall damage
  /// multiplier (`event.damageMultiplier` is the current one, 0 cancels the
  /// damage).
  final FutureOr<double> Function(Server server, CustomBlockLandedEventData event)? onLandedUpon;

  /// The name of the sound type of the block (`stone`, `wood`, ...).
  final FutureOr<String> Function(Server server, CustomBlockSoundTypeEventData event)? soundType;

  /// How fast the block catches fire and burns, each 0 to 255.
  final FutureOr<({int spreadChance, int burnChance})> Function(Server server, CustomBlockFireSpreadEventData event)? onFireSpread;

  /// The block is a redstone source that uses the output stored with
  /// `World.setRedstoneOutput`.
  final bool redstoneOutput;

  /// Comparators read the output stored with `World.setComparatorOutput`
  /// (without a handler in [onComparatorOutput] this is the only source).
  final bool comparatorOutput;

  /// Handler priority for the blocking hooks ([onCanPlace], [onUpdateShape],
  /// [onWeakPower], [onStrongPower], [onComparatorOutput]) and the others.
  final EventPriority priority;

  const BlockBehavior({
    this.onNeighborUpdate,
    this.onPlaced,
    this.onStateReplaced,
    this.onBroken,
    this.onScheduledTick,
    this.onRandomTick,
    this.onEntityCollision,
    this.onEntityStep,
    this.onCanPlace,
    this.onUpdateShape,
    this.onWeakPower,
    this.onStrongPower,
    this.onComparatorOutput,
    this.onShape,
    this.onEntityCollisionShape,
    this.onUse,
    this.onUseWithItem,
    this.onUseWithoutItem,
    this.onAttack,
    this.onCloneItem,
    this.onPlayerWillDestroy,
    this.onFriction,
    this.onSpeedFactor,
    this.onJumpFactor,
    this.canEntityDestroy,
    this.isPathfindable,
    this.canConnectRedstone,
    this.onLandedUpon,
    this.soundType,
    this.onFireSpread,
    this.redstoneOutput = false,
    this.comparatorOutput = false,
    this.priority = EventPriority.normal,
  });

  /// The host flags for the hooks this behavior uses.
  Set<BlockCallbackFlagsFlag> get flags => {
    if (onNeighborUpdate != null) BlockCallbackFlagsFlag.neighborUpdate,
    if (onPlaced != null) ...{
      BlockCallbackFlagsFlag.placed,
      BlockCallbackFlagsFlag.playerPlaced,
    },
    if (onStateReplaced != null) BlockCallbackFlagsFlag.stateReplaced,
    if (onBroken != null) BlockCallbackFlagsFlag.broken,
    if (onScheduledTick != null) BlockCallbackFlagsFlag.scheduledTick,
    if (onRandomTick != null) BlockCallbackFlagsFlag.randomTick,
    if (onEntityCollision != null) BlockCallbackFlagsFlag.entityCollision,
    if (onEntityStep != null) BlockCallbackFlagsFlag.entityStep,
    if (onCanPlace != null) BlockCallbackFlagsFlag.canPlace,
    if (onUpdateShape != null) BlockCallbackFlagsFlag.updateShape,
    if (redstoneOutput) BlockCallbackFlagsFlag.redstoneOutput,
    if (onWeakPower != null) BlockCallbackFlagsFlag.weakPower,
    if (onStrongPower != null) BlockCallbackFlagsFlag.strongPower,
    if (comparatorOutput || onComparatorOutput != null)
      BlockCallbackFlagsFlag.comparatorOutput,
    if (onShape != null) BlockCallbackFlagsFlag.dynamicShape,
    if (onEntityCollisionShape != null)
      BlockCallbackFlagsFlag.entityCollisionShape,
    if (onUse != null || onUseWithoutItem != null)
      BlockCallbackFlagsFlag.useWithoutItem,
    if (onUse != null || onUseWithItem != null)
      BlockCallbackFlagsFlag.useWithItem,
    if (onAttack != null) BlockCallbackFlagsFlag.attack,
    if (onCloneItem != null) BlockCallbackFlagsFlag.getCloneItem,
    if (onPlayerWillDestroy != null) BlockCallbackFlagsFlag.playerWillDestroy,
    if (onFriction != null) BlockCallbackFlagsFlag.getFriction,
    if (onSpeedFactor != null) BlockCallbackFlagsFlag.getSpeedFactor,
    if (onJumpFactor != null) BlockCallbackFlagsFlag.getJumpFactor,
    if (canEntityDestroy != null) BlockCallbackFlagsFlag.canEntityDestroy,
    if (onLandedUpon != null) BlockCallbackFlagsFlag.onLandedUpon,
    if (soundType != null) BlockCallbackFlagsFlag.getSoundType,
    if (isPathfindable != null) BlockCallbackFlagsFlag.isPathfindable,
    if (canConnectRedstone != null) BlockCallbackFlagsFlag.canConnectRedstone,
    if (onFireSpread != null) BlockCallbackFlagsFlag.getFireSpread,
  };
}

/// Hooks of custom blocks, see [BlockBehavior].
extension BlockBehaviorRegistration on Context {
  /// Opts the block [blockKey] into the hooks of [behavior] and routes their
  /// events to its handlers. Needs the `registry.blocks` permission and, like
  /// all registration, runs while the server loads (`Plugin.onLoad`). Throws a
  /// [HostException] if the host refuses (unknown block, other callbacks than
  /// before, registration closed).
  ///
  /// Returns the event subscriptions, to stop the handlers early.
  List<EventSubscription> registerBlockBehavior(
    String blockKey,
    BlockBehavior behavior,
  ) {
    unwrapHost(
      generated.blockCallbacks.setBlockCallbacks(
        blockKey: blockKey,
        callbacks: behavior.flags,
      ),
      'Setting the callbacks of $blockKey',
    );

    bool mine(String block) => registryKeysMatch(block, blockKey);
    // The plugin can fire the placed event itself for a bulk write that skipped it
    // (`CustomBlockBehaviors.firePlaced`): the host does not fire it there.
    CustomBlockBehaviors.install(this);
    CustomBlockBehaviors.record(blockKey, behavior);
    final p = behavior.priority;
    final subscriptions = <EventSubscription>[];

    void on<D>(
      EventKind<D> kind,
      String Function(D data) blockOf,
      FutureOr<void> Function(Server server, D data)? handler,
    ) {
      if (handler == null) return;
      subscriptions.add(
        listen(kind, (server, data) {
          if (!mine(blockOf(data))) return null;
          return handler(server, data);
        }, priority: p),
      );
    }

    on(Events.customBlockNeighborUpdate, (d) => d.block, behavior.onNeighborUpdate);
    on(Events.customBlockPlaced, (d) => d.block, behavior.onPlaced);
    on(Events.customBlockStateReplaced, (d) => d.block, behavior.onStateReplaced);
    on(Events.customBlockBroken, (d) => d.block, behavior.onBroken);
    on(Events.customBlockScheduledTick, (d) => d.block, behavior.onScheduledTick);
    on(Events.customBlockRandomTick, (d) => d.block, behavior.onRandomTick);
    on(Events.customBlockEntityCollision, (d) => d.block, behavior.onEntityCollision);
    on(Events.customBlockEntityStep, (d) => d.block, behavior.onEntityStep);

    final canPlace = behavior.onCanPlace;
    if (canPlace != null) {
      subscriptions.add(
        intercept(Events.customBlockCanPlace, (server, data) {
          if (!mine(data.block)) return data;
          return thenOr(canPlace(server, data), (ok) => data.copyWith(canPlace: ok));
        }, priority: p),
      );
    }

    final updateShape = behavior.onUpdateShape;
    if (updateShape != null) {
      subscriptions.add(
        intercept(Events.customBlockUpdateShape, (server, data) {
          if (!mine(data.block)) return data;
          return thenOr(
            updateShape(server, data),
            (index) => index == null ? data : data.copyWith(newStateIndex: index),
          );
        }, priority: p),
      );
    }

    final weak = behavior.onWeakPower;
    final strong = behavior.onStrongPower;
    if (weak != null || strong != null) {
      subscriptions.add(
        intercept(Events.customBlockRedstonePower, (server, data) {
          if (!mine(data.block)) return data;
          final handler = data.strong ? strong : weak;
          if (handler == null) return data;
          return thenOr(handler(server, data), (power) => data.copyWith(power: power.clamp(0, 15)));
        }, priority: p),
      );
    }

    final comparator = behavior.onComparatorOutput;
    if (comparator != null) {
      subscriptions.add(
        intercept(Events.customBlockComparatorOutput, (server, data) {
          if (!mine(data.block)) return data;
          return thenOr(
            comparator(server, data),
            (out) => out == null
                ? data.copyWith(clearOutput: true)
                : data.copyWith(output: out.clamp(0, 15)),
          );
        }, priority: p),
      );
    }

    on(Events.customBlockAttack, (d) => d.block, behavior.onAttack);

    final shape = behavior.onShape;
    if (shape != null) {
      subscriptions.add(
        intercept(Events.customBlockShape, (server, data) {
          if (!mine(data.block)) return data;
          return thenOr(
            shape(server, data),
            (boxes) => boxes == null
                ? data
                : data.copyWith(shapes: [for (final b in boxes) _toWireBox(b)]),
          );
        }, priority: p),
      );
    }

    final entityShape = behavior.onEntityCollisionShape;
    if (entityShape != null) {
      subscriptions.add(
        intercept(Events.customBlockCollisionShape, (server, data) {
          if (!mine(data.block)) return data;
          return thenOr(
            entityShape(server, data),
            (boxes) => boxes == null
                ? data
                : data.copyWith(shapes: [for (final b in boxes) _toWireBox(b)]),
          );
        }, priority: p),
      );
    }

    if (behavior.onUse != null ||
        behavior.onUseWithItem != null ||
        behavior.onUseWithoutItem != null) {
      subscriptions.add(
        intercept(Events.customBlockUse, (server, data) {
          if (!mine(data.block)) return data;
          final handler = (data.withItem ? behavior.onUseWithItem : behavior.onUseWithoutItem) ?? behavior.onUse;
          if (handler == null) return data;
          return thenOr(handler(server, data), (r) => data.copyWith(result: r));
        }, priority: p),
      );
    }

    final clone = behavior.onCloneItem;
    if (clone != null) {
      subscriptions.add(
        intercept(Events.customBlockCloneItem, (server, data) {
          if (!mine(data.block)) return data;
          return thenOr(
            clone(server, data),
            (item) => item == null ? data.copyWith(clearItem: true) : data.copyWith(item: item),
          );
        }, priority: p),
      );
    }

    final willDestroy = behavior.onPlayerWillDestroy;
    if (willDestroy != null) {
      subscriptions.add(
        intercept(Events.customBlockPlayerWillDestroy, (server, data) {
          if (!mine(data.block)) return data;
          return thenOr(willDestroy(server, data), (ok) => data.copyWith(cancelled: !ok));
        }, priority: p),
      );
    }

    final friction = behavior.onFriction;
    final speed = behavior.onSpeedFactor;
    final jump = behavior.onJumpFactor;
    if (friction != null || speed != null || jump != null) {
      subscriptions.add(
        intercept(Events.customBlockPhysics, (server, data) {
          if (!mine(data.block)) return data;
          final handler = switch (data.kind) {
            BlockPhysicsKind.friction => friction,
            BlockPhysicsKind.speedFactor => speed,
            BlockPhysicsKind.jumpFactor => jump,
          };
          if (handler == null) return data;
          return thenOr(handler(server, data), (v) => data.copyWith(value: v));
        }, priority: p),
      );
    }

    final destroy = behavior.canEntityDestroy;
    final path = behavior.isPathfindable;
    final redstone = behavior.canConnectRedstone;
    if (destroy != null || path != null || redstone != null) {
      subscriptions.add(
        intercept(Events.customBlockCondition, (server, data) {
          if (!mine(data.block)) return data;
          final handler = switch (data.condition) {
            BlockCondition.entityDestroy => destroy,
            BlockCondition.pathfindableLand ||
            BlockCondition.pathfindableWater ||
            BlockCondition.pathfindableAir => path,
            BlockCondition.redstoneConnect => redstone,
          };
          if (handler == null) return data;
          return thenOr(handler(server, data), (v) => data.copyWith(value: v));
        }, priority: p),
      );
    }

    final landed = behavior.onLandedUpon;
    if (landed != null) {
      subscriptions.add(
        intercept(Events.customBlockLanded, (server, data) {
          if (!mine(data.block)) return data;
          return thenOr(landed(server, data), (m) => data.copyWith(damageMultiplier: m));
        }, priority: p),
      );
    }

    final sound = behavior.soundType;
    if (sound != null) {
      subscriptions.add(
        intercept(Events.customBlockSoundType, (server, data) {
          if (!mine(data.block)) return data;
          return thenOr(sound(server, data), (name) => data.copyWith(soundType: name));
        }, priority: p),
      );
    }

    final fire = behavior.onFireSpread;
    if (fire != null) {
      subscriptions.add(
        intercept(Events.customBlockFireSpread, (server, data) {
          if (!mine(data.block)) return data;
          return thenOr(
            fire(server, data),
            (r) => data.copyWith(
              spreadChance: r.spreadChance.clamp(0, 255),
              burnChance: r.burnChance.clamp(0, 255),
            ),
          );
        }, priority: p),
      );
    }
    return subscriptions;
  }
}

/// The [BlockBehavior]s a plugin registered, so it can fire a block event itself.
///
/// [BlockBehaviorRegistration.registerBlockBehavior] routes the host's events to
/// the handlers, but the host only fires them for the writes it makes itself,
/// one callback per block. A bulk write ([WorldBulkBlocks.placeBlocks]) with
/// [BlockFlagsFlag.skipBlockAddedCallback] writes every block of the batch in one
/// host call without those callbacks - each callback is a host-to-plugin round
/// trip that costs far more than the write itself - so the plugin fires the
/// `placed` handling of what it wrote itself, once per position and in one
/// callback of its own: [firePlaced].
///
/// The handlers get the same [CustomBlockPlacedEventData] the host would send for
/// a `placed` event: the position, the block, its `stateIndex` within the block,
/// the state that was there before and `player: null` (`player-placed` is a
/// player's own write, which a bulk write is not).
abstract final class CustomBlockBehaviors {
  static Context? _context;
  static final Map<String, List<BlockBehavior>> _byBlock = {};

  /// Remembers the load context ([BlockBehaviorRegistration] passes it in), so a
  /// handler can be given a [Server] outside a host event.
  static void install(Context context) => _context = context;

  /// Records [behavior] as a handler of [blockKey].
  static void record(String blockKey, BlockBehavior behavior) =>
      _byBlock.putIfAbsent(blockKey, () => <BlockBehavior>[]).add(behavior);

  /// The behaviors registered for [blockKey] (`registryKeysMatch`, so a key
  /// without the `minecraft:` namespace still matches).
  static List<BlockBehavior> forBlock(String blockKey) => [
    for (final entry in _byBlock.entries)
      if (registryKeysMatch(entry.key, blockKey)) ...entry.value,
  ];

  /// Forgets every behavior (tests, plugin reloads).
  static void clear() {
    _byBlock.clear();
    _context = null;
  }

  /// Runs the `onPlaced` of every behavior registered for [blockKey], as the host
  /// would have for the block it wrote at [pos] itself.
  ///
  /// [stateIndex] is the state's index within the block and [oldStateId] the
  /// state that was at [pos] before the write (`null` for "not known"). The
  /// handlers run in registration order. Nothing happens when the plugin
  /// registered no behavior for [blockKey], and a handler does not run for a
  /// block another plugin registered.
  static Future<void> firePlaced({
    required World targetWorld,
    required BlockPos pos,
    required String blockKey,
    required int stateIndex,
    int? oldStateId,
  }) async {
    final behaviors = forBlock(blockKey);
    if (behaviors.isEmpty) return;
    final server = _context?.getServer();
    if (server == null) return;
    final event = CustomBlockPlacedEventData(
      targetWorld: targetWorld,
      pos: pos,
      block: blockKey,
      stateIndex: stateIndex,
      player: null,
      oldStateId: oldStateId,
      moved: false,
    );
    for (final behavior in behaviors) {
      await behavior.onPlaced?.call(server, event);
    }
  }
}

generated.BlockBox _toWireBox(core.BlockBox b) => generated.BlockBox(
  minX: b.minX,
  minY: b.minY,
  minZ: b.minZ,
  maxX: b.maxX,
  maxY: b.maxY,
  maxZ: b.maxZ,
);

/// The shape boxes of a `custom-block-shape-event` in the plugin's block box
/// type (the generated one is hidden).
extension CustomBlockShapeBoxes on CustomBlockShapeEventData {
  List<core.BlockBox> get boxes => [
    for (final b in shapes)
      core.BlockBox(b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ),
  ];
}

/// Redstone, block ticks and neighbour updates of a [World]
/// (`world.wit`), for plugin machines and blocks.
extension WorldRedstone on World {
  /// The redstone power (0 to 15) that reaches [pos] from [direction].
  Future<int> redstonePower(BlockPos pos, BlockDirection direction) =>
      getRedstonePower(pos: pos, direction: direction);

  /// The power [pos] receives from [direction] directly (strong power only).
  Future<int> directRedstonePower(BlockPos pos, BlockDirection direction) =>
      getDirectRedstonePower(pos: pos, direction: direction);

  /// Whether any neighbour of [pos] gives a redstone signal.
  Future<bool> hasRedstoneNeighborSignal(BlockPos pos) => hasNeighborSignal(pos: pos);

  /// The strongest signal among the neighbours of [pos].
  Future<int> bestNeighborSignal(BlockPos pos) => getBestNeighborSignal(pos: pos);

  /// The analog (comparator) signal of the block next to [pos] in
  /// [direction], or `null` when it has none.
  Future<int?> analogSignal(BlockPos pos, BlockDirection direction) =>
      getAnalogSignal(pos: pos, direction: direction);

  /// Stores the redstone output of the custom block at [pos]: [weak] and
  /// [strong] power (0 to 15) and updates the neighbours. With [face] only that
  /// face gets the output. Needs the `redstone-output` hook
  /// (`BlockBehavior.redstoneOutput`). The output is kept in memory only: store
  /// it again after a restart. Throws a [HostException] on failure.
  Future<void> setRedstoneOutput(
    BlockPos pos, {
    int weak = 0,
    int strong = 0,
    BlockDirection? face,
  }) => unwrapHostAsync(
    face == null
        ? setBlockRedstoneOutput(pos: pos, weak: weak, strong: strong)
        : setBlockRedstoneOutputFace(pos: pos, face: face, weak: weak, strong: strong),
    'Setting the redstone output at (${pos.x}, ${pos.y}, ${pos.z})',
  );

  /// Stores the analog output (0 to 15) comparators read from the custom block
  /// at [pos], `null` to remove it.
  Future<void> setComparatorOutput(BlockPos pos, int? output) => unwrapHostAsync(
    setBlockComparatorOutput(pos: pos, output: output),
    'Setting the comparator output at (${pos.x}, ${pos.y}, ${pos.z})',
  );

  /// Tells the neighbours of [pos] that it changed. [sourceBlock] is the key of
  /// the block that caused it (the block at [pos] if `null`).
  Future<void> notifyNeighbors(BlockPos pos, {String? sourceBlock}) =>
      unwrapHostAsync(
        updateNeighbors(pos: pos, sourceBlock: sourceBlock),
        'Updating the neighbours of (${pos.x}, ${pos.y}, ${pos.z})',
      );

  /// Forgets what the plugin answered for the block at [pos] (the dynamic
  /// shape, friction, speed factor and jump factor hooks) so it is asked again.
  /// Call it whenever such an answer changes, for example when a copycat gets a
  /// new material. Replacing the block clears it on its own.
  void invalidateShape(BlockPos pos) => invalidateBlockShape(pos: pos);

  /// Schedules a tick of the block at [pos] after [delay] (rounded up to whole
  /// ticks, at most 255). It arrives as `BlockBehavior.onScheduledTick`.
  void scheduleTick(
    BlockPos pos,
    Duration delay, {
    TickPriority priority = TickPriority.normal,
  }) => scheduleBlockTick(
    pos: pos,
    delayTicks: ((delay.inMilliseconds + 49) ~/ 50).clamp(0, 255),
    priority: priority,
  );
}
