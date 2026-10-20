// The actor API (pure): `MovementContext`, `MovementBehaviour` and the registry that maps blocks to
// them, `MovingInteractionBehaviour`. Blocks that sit on a contraption get a behaviour from the
// registry; the contraption entity calls it every tick. The ~45 actors of Create implement
// [MovementBehaviour] and register themselves here (see `api/contraptions.dart`).
import 'dart:async';

import '../../api/block_state.dart';
import '../../common/common.dart';
import 'contraption.dart';
import 'level.dart';
import 'nbt_map.dart';
import 'structure_info.dart';
import '../storage/mounted_storage.dart';
import '../storage/stacks.dart';

/// `UnaryOperator<Vec3>`.
typedef VecRotation = Vec3 Function(Vec3 v);

Vec3 _identity(Vec3 v) => v;

/// `MovementContext`: the state of one actor block on a contraption.
final class MovementContext {
  /// Where the actor is in the world, `null` before the first tick of the contraption.
  Vec3? position;

  /// How far the actor moved in the last tick (world space).
  Vec3 motion = vec3Zero;

  /// [motion] in the space of the contraption.
  Vec3 relativeMotion = vec3Zero;

  /// Rotates a vector from the space of the contraption to the world.
  VecRotation rotation = _identity;

  /// The world the contraption is in: read blocks and entities through it. On the host this
  /// is a `HostContraptionLevel` (`api/contraptions.dart` has helpers for the host `World`).
  final ContraptionLevel level;
  final String worldId;

  /// The state of the block on the contraption.
  BState state;

  /// The position of the block in the contraption.
  final Pos localPos;

  /// The saved block entity data of the block.
  NbtMap? blockEntityData;

  /// The actor wants the contraption to stop moving.
  bool stall = false;

  /// The actor was disabled by contraption controls.
  bool disabled = false;
  bool firstMovement = true;

  /// Persistent data of the actor (saved with the contraption).
  NbtMap data = NbtMap();
  final Contraption contraption;

  /// Data that is not saved.
  Object? temporaryData;

  MovementContext(
    this.level,
    this.worldId,
    StructureBlockInfo info,
    this.contraption,
  ) : state = info.state,
      blockEntityData = info.nbt,
      localPos = info.pos;

  /// The mounted item storage of this block, `null` if there is none.
  MountedItemStorage? get itemStorage =>
      contraption.storage.allItemStorages[localPos];

  /// The mounted fluid storage of this block, `null` if there is none.
  MountedFluidStorage? get fluidStorage =>
      contraption.storage.fluidStorages[localPos];

  /// `getAnimationSpeed`.
  double getAnimationSpeed() {
    const modifier = 1000;
    final length = -motion.length;
    if (disabled) return 0;
    if (contraption.stalled && isClientSide) return 700;
    if (length.abs() < 1 / 512) return 0;
    return (((length * modifier + 100 * length.sign).toInt()) ~/ 100 * 100)
        .toDouble();
  }

  /// Always false: the server never runs the client animations.
  bool get isClientSide => false;

  /// `MovementContext.readNBT`.
  static MovementContext readNbt(
    ContraptionLevel level,
    String worldId,
    StructureBlockInfo info,
    NbtMap nbt,
    Contraption contraption,
  ) {
    final c = MovementContext(level, worldId, info, contraption);
    c.motion = nbt.getVec('Motion');
    c.relativeMotion = nbt.getVec('RelativeMotion');
    if (nbt.contains('Position')) c.position = nbt.getVec('Position');
    c.stall = nbt.getBool('Stall');
    c.firstMovement = nbt.getBool('FirstMovement');
    c.data = nbt.getCompound('Data');
    return c;
  }

  /// `writeToNBT`.
  NbtMap writeToNbt(NbtMap nbt) {
    nbt.putVec('Motion', motion);
    nbt.putVec('RelativeMotion', relativeMotion);
    final p = position;
    if (p != null) nbt.putVec('Position', p);
    nbt.putBool('Stall', stall);
    nbt.putBool('FirstMovement', firstMovement);
    nbt.putCompound('Data', data.copy());
    return nbt;
  }
}

/// `MovementBehaviour`, also known as an actor: what a block does while it sits on a contraption.
/// Override what you need; every method has Create's default. The ticking methods may be
/// asynchronous because the host calls are.
abstract class MovementBehaviour {
  const MovementBehaviour();

  /// `isActive`.
  bool isActive(MovementContext context) => !context.disabled;

  /// `tick`.
  FutureOr<void> tick(MovementContext context) {}

  /// `startMoving`: the contraption starts moving.
  FutureOr<void> startMoving(MovementContext context) {}

  /// `visitNewPosition`: the actor moved into another block of the world.
  FutureOr<void> visitNewPosition(MovementContext context, Pos pos) {}

  /// `getActiveAreaOffset`: where the actor acts, relative to its block centre.
  Vec3 getActiveAreaOffset(MovementContext context) => vec3Zero;

  /// `canBeDisabledVia`: the item the contraption controls filter uses to find this actor (its
  /// block item), `null` if it cannot be disabled.
  ///
  /// `new ItemStack(block)` of a block without an item is an empty stack, which no filter matches.
  StoredStack? canBeDisabledVia(MovementContext context) =>
      context.level.blockHasItem(context.state)
      ? StoredStack(context.state.key, 1)
      : StoredStack.empty;

  /// `onDisabledByControls`.
  void onDisabledByControls(MovementContext context) => cancelStall(context);

  /// `mustTickWhileDisabled`.
  bool mustTickWhileDisabled() => false;

  /// `onSpeedChanged`.
  FutureOr<void> onSpeedChanged(
    MovementContext context,
    Vec3 oldMotion,
    Vec3 motion,
  ) {}

  /// `PortableStorageInterfaceMovement`: the actor was moved to a new position without ticking.
  FutureOr<void> refreshAtNewPosition(MovementContext context) {}

  /// `shouldActorTrigger` ignores the motion for the first movement of this actor
  /// (`PortableStorageInterfaceMovement`).
  bool get ignoresMotionForFirstMovement => false;

  /// `stopMoving`.
  FutureOr<void> stopMoving(MovementContext context) {}

  /// `cancelStall`.
  void cancelStall(MovementContext context) => context.stall = false;

  /// `writeExtraData`: put data into `context.data` before the contraption is saved.
  void writeExtraData(MovementContext context) {}

  /// `disableBlockEntityRendering`: client only, kept so ported actors can state it.
  bool disableBlockEntityRendering() => false;

  /// Whether this actor breaks blocks in the world (`BlockBreakingMovementBehaviour` or
  /// `HarvesterMovementBehaviour`); used to decide whether a contraption can be picked up.
  bool breaksBlocks() => false;

  /// `ContraptionCollider.isCollidingWithWorld`: whether the block the contraption moves into at
  /// [colliderPos] lets it pass because this actor handles that block.
  ///
  /// `null` when the actor has no say and the collider falls through to its generic rules
  /// (`stateReplaceable`, empty collider, ...). A block breaking actor answers its own
  /// `canBreak` (`BlockBreakingMovementBehaviour`, narrowed by the drill, saw, plough and
  /// roller), the harvester its crop rules; otherwise the collider would block on every solid
  /// block.
  ///
  /// Inverted from the concrete type tests, so this API stays pure and the collider does not
  /// import the world-touching actor implementations (they override this instead).
  bool? passesThroughCollision(
    ContraptionLevel level,
    Pos colliderPos,
    BState collidedState,
  ) => breaksBlocks() ? false : null;
}

/// Hooks the contraption controls actor installs so the core can apply its filters without
/// knowing the actor. All optional: without them no actor is disabled by controls.
abstract final class ActorControlHooks {
  /// `ContraptionControlsMovement.isDisabledInitially(context)`.
  static bool Function(MovementContext context)? isDisabledInitially;

  /// `ContraptionControlsMovement.getFilter(context)`.
  static StoredStack? Function(MovementContext context)? filterOf;

  /// `ContraptionControlsMovement.isSameFilter(a, b)`.
  static bool Function(StoredStack a, StoredStack b)? isSameFilter;
}

/// A registry that maps blocks to values by key, with a fallback by block tag
/// (`SimpleRegistry` of Create).
final class BlockRegistryOf<T> {
  final Map<String, T> _byKey = {};
  final List<(String, T)> _byTag = [];

  /// Registers [value] for the block [blockKey] (`create:seat`).
  void register(String blockKey, T value) => _byKey[blockKey] = value;

  /// Registers [value] for all blocks of the tag [tag].
  void registerTag(String tag, T value) => _byTag.add((tag, value));

  /// The value of a block state: by key first, then by tag.
  T? get(BState state, [ContraptionLevel? level]) {
    final k = _byKey[state.key];
    if (k != null) return k;
    if (level != null) {
      for (final (tag, v) in _byTag) {
        if (level.stateHasTag(state, tag)) return v;
      }
    }
    return null;
  }

  T? byKey(String blockKey) => _byKey[blockKey];

  Iterable<String> get keys => _byKey.keys;

  void clear() {
    _byKey.clear();
    _byTag.clear();
  }
}

/// `MovementBehaviour.REGISTRY`.
abstract final class MovementBehaviours {
  static final BlockRegistryOf<MovementBehaviour> registry = BlockRegistryOf();

  static void register(String blockKey, MovementBehaviour behaviour) =>
      registry.register(blockKey, behaviour);

  static void registerAll(
    Iterable<String> blockKeys,
    MovementBehaviour behaviour,
  ) {
    for (final k in blockKeys) {
      registry.register(k, behaviour);
    }
  }

  static void registerTag(String tag, MovementBehaviour behaviour) =>
      registry.registerTag(tag, behaviour);

  static MovementBehaviour? of(BState state, [ContraptionLevel? level]) =>
      registry.get(state, level);
}

/// A player seen by a [MovingInteractionBehaviour]. The host wraps its `Player`.
abstract class InteractingPlayer {
  String get uuid;
  bool get isSneaking;
  bool get isCreative;

  /// Whether the player is riding an entity (`player.isPassenger()`).
  bool get isPassenger => false;

  /// Whether the held item of the interacting hand is a wrench.
  bool get holdsWrench;

  /// `player.isWithinBlockInteractionRange(pos, distance)`.
  bool canInteractWith(Pos pos, double distance) => true;

  /// Plays [sound] at the player for everybody else (`level.playSound(player, ...)`).
  void playSound(String sound, double pitch, {double volume = 0.3});

  /// The player object of the host (`Player`), for behaviours that need more.
  Object get hostPlayer;
}

/// An entity that touches a contraption (`handleEntityCollision`). The host wraps its `Entity`.
abstract class CollidingEntity {
  int get id;
  String get uuid;
  String get typeKey;
  Vec3 get position;
  bool get isLiving;

  /// The host entity.
  Object get hostEntity;
}

/// `MovingInteractionBehaviour`: what happens when a player clicks, or an entity touches, a block
/// on a contraption.
abstract class MovingInteractionBehaviour {
  const MovingInteractionBehaviour();

  /// `handlePlayerInteraction`: true if the interaction was handled.
  FutureOr<bool> handlePlayerInteraction(
    InteractingPlayer player,
    Pos localPos,
    Contraption contraption,
  ) => true;

  /// `handleEntityCollision`.
  FutureOr<void> handleEntityCollision(
    CollidingEntity entity,
    Pos localPos,
    Contraption contraption,
  ) {}

  /// `setContraptionBlockData`: changes a block of the contraption and syncs it.
  void setContraptionBlockData(
    Contraption contraption,
    Pos pos,
    StructureBlockInfo info,
  ) {
    contraption.entity?.setBlock(pos, info);
  }
}

/// `MovingInteractionBehaviour.REGISTRY`.
abstract final class MovingInteractions {
  static final BlockRegistryOf<MovingInteractionBehaviour> registry =
      BlockRegistryOf();

  static void register(String blockKey, MovingInteractionBehaviour behaviour) =>
      registry.register(blockKey, behaviour);

  static void registerTag(String tag, MovingInteractionBehaviour behaviour) =>
      registry.registerTag(tag, behaviour);

  static MovingInteractionBehaviour? of(
    BState state, [
    ContraptionLevel? level,
  ]) => registry.get(state, level);
}

/// `SimpleBlockMovingInteraction`: an interaction that changes the state of the clicked block.
abstract class SimpleBlockMovingInteraction extends MovingInteractionBehaviour {
  const SimpleBlockMovingInteraction();

  @override
  FutureOr<bool> handlePlayerInteraction(
    InteractingPlayer player,
    Pos localPos,
    Contraption contraption,
  ) {
    final info = contraption.blocks[localPos];
    if (info == null) return false;
    final newState = handle(player, contraption, localPos, info.state);
    if (info.state == newState) return false;
    setContraptionBlockData(
      contraption,
      localPos,
      StructureBlockInfo(info.pos, newState, info.nbt),
    );
    if (updateColliders) contraption.invalidateColliders();
    return true;
  }

  /// `updateColliders`.
  bool get updateColliders => false;

  /// `handle`: the new state of the block.
  BState handle(
    InteractingPlayer? player,
    Contraption contraption,
    Pos pos,
    BState currentState,
  );

  /// `playSound` at the player.
  void playSound(InteractingPlayer? player, String sound, double pitch) =>
      player?.playSound(sound, pitch);
}
