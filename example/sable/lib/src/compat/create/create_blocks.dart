// Create's blocks as Sable sub-level content: the lift providers, the custom
// centres of mass, the physics collision callbacks and the assembly listeners
// Create's blocks contribute to a sub-level.
//
// In Java each of these is a mixin that makes a Create block implement a Sable
// interface (`SailBlockMixin implements BlockSubLevelLiftProvider`, ...). The
// Dart Create port describes blocks as data (`CreateBlock`), not as classes, so
// there is no object to make implement an interface. The compat layer therefore
// keeps one registry per interface, keyed by block key, and the Sable side asks
// the registry. The behaviour is the same; only the dispatch is by key.
//
// Pure: no host imports, so the Dart VM tests can load it.
//
// Java: `dev.ryanhcode.sable.neoforge.mixin.compatibility.create.sails_providing_lift.SailBlockMixin`,
// `...belt.BeltBlockMixin`, `...impact.AbstractBellBlockMixin`,
// `...chain_conveyor.ChainConveyorBlockMixin`, `...display_link.DisplayLinkBlockMixin`,
// `...lectern_controller.LecternControllerBlockMixin`.
//
// create's positions and block states are not exported from its public barrel
// yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState, BlockGetter;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/contraptions/bearing/sail.dart' show isSailKey, sailColors, sailFrame, dyedSail;

import '../../sublevel/math/pose.dart';
import '../../sublevel/math/vector.dart';
import '../../sublevel/model/server_sub_level.dart';
import '../../sublevel/api/block/block_sub_level_assembly_listener.dart';
import '../../sublevel/api/block/block_sub_level_custom_center_of_mass.dart';
import '../../sublevel/api/block/block_sub_level_lift_provider.dart';
import '../../sublevel/api/physics/callback/block_sub_level_collision_callback.dart';
import 'create_block_hooks.dart' show BeltStateReader, ChainConveyorAssemblyListener, DisplayLinkAssemblyListener, BeltBlockCallback;

/// Parses a block state string as the plot host reports it
/// (`create:white_sail[facing=north]`) into a [BState].
///
/// A bare block id has no properties; an unknown or malformed property list is
/// ignored rather than fatal, because a plot chunk can hold a block this build
/// does not know.
BState parseBlockState(String state) {
  final open = state.indexOf('[');
  if (open < 0 || !state.endsWith(']')) return BState(state);

  final props = <String, String>{};
  final body = state.substring(open + 1, state.length - 1);
  for (final pair in body.split(',')) {
    final equals = pair.indexOf('=');
    if (equals <= 0) continue;
    props[pair.substring(0, equals)] = pair.substring(equals + 1);
  }
  return BState(state.substring(0, open), props);
}

/// `SailBlockMixin`: a sail is a lift provider whose normal is the opposite of
/// its `facing`, and a block whose centre of mass is the block centre.
///
/// The Java mixin implements both interfaces on `SailBlock`; a single stateless
/// instance serves every sail key here.
final class SailLiftProvider implements BlockSubLevelLiftProvider, BlockSubLevelCustomCenterOfMass {
  const SailLiftProvider();

  /// The centre of mass of a sail: the middle of the block
  /// (`JOMLConversion.HALF`).
  static final Vector3d half = Vector3d(0.5, 0.5, 0.5);

  /// `sable$getNormal`: `state.getValue(FACING).getOpposite()`.
  ///
  /// A sail catches air on the face it was placed against, so the lift normal
  /// points away from its `facing`.
  @override
  Direction sable$getNormal(BState state) => (state.dir('facing') ?? Direction.north).opposite;

  /// `getCenterOfMass`: the middle of the block.
  @override
  Vector3d getCenterOfMass(BlockGetter blockGetter, BState state) => Vector3d.copy(half);

  // The remaining `BlockSubLevelLiftProvider` members keep the interface
  // defaults: an interface's method bodies are not inherited by its
  // implementers in Dart, so they are forwarded here.

  @override
  double sable$getParallelDragScalar() => BlockSubLevelLiftProvider.defaultParallelDragScalar;

  @override
  double sable$getDirectionlessDragScalar() => BlockSubLevelLiftProvider.defaultDirectionlessDragScalar;

  @override
  double sable$getLiftScalar() => BlockSubLevelLiftProvider.defaultLiftScalar;

  @override
  void sable$contributeLiftAndDrag(
    LiftProviderContext ctx,
    ServerSubLevel subLevel,
    Pose3d? localPose,
    double timeStep,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
    Vector3d linearImpulse,
    Vector3d angularImpulse, [
    LiftProviderGroup? group,
  ]) => BlockSubLevelLiftProvider.contributeLiftAndDrag(
    this,
    ctx,
    subLevel,
    localPose,
    timeStep,
    linearVelocity,
    angularVelocity,
    linearImpulse,
    angularImpulse,
    group,
  );
}

/// One lift provider entry: the block and the normal it lifts along.
final class CreateLiftProviderEntry {
  final Pos pos;
  final BState state;

  /// The lift normal as the direction's step vector.
  final Vector3d normal;

  const CreateLiftProviderEntry(this.pos, this.state, this.normal);

  /// The context the physics tick passes to the provider
  /// (`BlockSubLevelLiftProvider.LiftProviderContext`).
  LiftProviderContext toContext() => LiftProviderContext(pos, state, Vector3d.copy(normal));

  @override
  String toString() => 'CreateLiftProviderEntry[$pos, $state, $normal]';
}

/// The Create blocks that take part in sub-level physics, by block key.
///
/// [install] registers Create's own blocks; a module (Simulated, Aeronautics)
/// registers its own through the same methods, which is the Dart equivalent of
/// its block classes implementing the interfaces.
abstract final class CreateCompatBlocks {
  /// Block key -> lift provider.
  static final Map<String, BlockSubLevelLiftProvider> liftProviders = {};

  /// Block key -> custom centre of mass.
  static final Map<String, BlockSubLevelCustomCenterOfMass> centersOfMass = {};

  /// Block key -> physics collision callback.
  static final Map<String, BlockSubLevelCollisionCallback> collisionCallbacks = {};

  /// Block key -> assembly listener.
  static final Map<String, BlockSubLevelAssemblyListener> assemblyListeners = {};

  // The host lookups the block-entity listeners need. They are function
  // pointers rather than imports so this library stays loadable on the VM: the
  // plugin installs the real ones in `create_host.dart`.

  /// The block entity at a position, or `null`. Installed by the plugin.
  ///
  /// The identifier is the **dimension key** of the level the listener runs for
  /// (`SableLevel.dimensionId`, `minecraft:overworld`), not a world id — Create's
  /// `BlockEntityStore` is keyed by `World.getId()` (the folder name `world`), so the installed
  /// lookup has to resolve the identifier through the world table (`Worlds.worldIdOf`) before it
  /// reads the store. Passing it straight through silently finds nothing.
  static Object? Function(String dimensionId, Pos pos)? blockEntityLookup;

  /// Reads the belt data of a block entity, `null` when it is not a belt.
  static BeltStateReader? beltStateReader;

  /// `ChainConveyorBlockEntity.notifyConnectedToValidate`.
  static void Function(Object blockEntity)? chainConveyorValidate;

  /// `ChainConveyorBlockEntity.checkInvalid = true`.
  static void Function(Object blockEntity)? chainConveyorCheckInvalid;

  /// `DisplayLinkBlockEntity.getTargetPosition()`.
  static Pos? Function(Object blockEntity)? displayLinkTarget;

  /// `DisplayLinkBlockEntity.target(pos)`.
  static void Function(Object blockEntity, Pos target)? displayLinkRetarget;

  static bool _installed = false;

  /// Whether Create's own block contributions are registered.
  static bool get installed => _installed;

  /// Registers [provider] for every key in [blockKeys].
  static void registerLiftProvider(Iterable<String> blockKeys, BlockSubLevelLiftProvider provider) {
    for (final key in blockKeys) {
      liftProviders[key] = provider;
    }
  }

  /// Removes the lift provider of [blockKey].
  static void unregisterLiftProvider(String blockKey) => liftProviders.remove(blockKey);

  /// Registers [centerOfMass] for every key in [blockKeys].
  static void registerCenterOfMass(Iterable<String> blockKeys, BlockSubLevelCustomCenterOfMass centerOfMass) {
    for (final key in blockKeys) {
      centersOfMass[key] = centerOfMass;
    }
  }

  /// Registers [callback] for [blockKey].
  static void registerCollisionCallback(String blockKey, BlockSubLevelCollisionCallback callback) {
    collisionCallbacks[blockKey] = callback;
  }

  /// Registers [listener] for [blockKey].
  static void registerAssemblyListener(String blockKey, BlockSubLevelAssemblyListener listener) {
    assemblyListeners[blockKey] = listener;
  }

  /// The lift provider of [state], or `null`.
  static BlockSubLevelLiftProvider? liftProviderOf(BState state) => liftProviders[state.key];

  /// The lift provider at [pos] with [state], or `null`.
  ///
  /// This is the `sable$buildProperties` lookup of
  /// `AbstractContraptionEntityMixin` and the `liftProviderAt` hook of
  /// `ServerLevelPlot`, in one place.
  static CreateLiftProviderEntry? liftProviderAt(Pos pos, BState state) {
    final provider = liftProviders[state.key];
    if (provider == null) return null;

    final step = provider.sable$getNormal(state);
    return CreateLiftProviderEntry(
      pos,
      state,
      Vector3d(step.stepX.toDouble(), step.stepY.toDouble(), step.stepZ.toDouble()),
    );
  }

  /// The custom centre of mass of [state] read against [blockGetter], or
  /// `null` when the block has none.
  static Vector3d? centerOfMassOf(BlockGetter blockGetter, BState state) =>
      centersOfMass[state.key]?.getCenterOfMass(blockGetter, state);

  /// The physics collision callback of [state], or `null`.
  static BlockSubLevelCollisionCallback? collisionCallbackOf(BState state) => collisionCallbacks[state.key];

  /// The assembly listener of [state], or `null`.
  static BlockSubLevelAssemblyListener? assemblyListenerOf(BState state) => assemblyListeners[state.key];

  /// Every sail key: the frame, the white sail and the sixteen dyed sails.
  static List<String> get sailBlockKeys => [
    sailFrame,
    ...sailColors.map(dyedSail),
  ];

  /// Registers Create's block contributions.
  ///
  /// Idempotent: the registries are replaced, not appended to, so a reload does
  /// not double-register.
  static void install() {
    if (_installed) return;
    _installed = true;

    // `SailBlockMixin`: lift along the opposite of `facing`, centre of mass at
    // the block centre.
    const sail = SailLiftProvider();
    final sails = sailBlockKeys.where(isSailKey).toList(growable: false);
    registerLiftProvider(sails, sail);
    registerCenterOfMass(sails, sail);

    // The belt's tangent velocity: `BeltBlockMixin`.
    registerCollisionCallback('create:belt', const BeltBlockCallback());

    // The assembly listeners of the blocks that must react to being moved.
    const chainConveyor = ChainConveyorAssemblyListener();
    registerAssemblyListener('create:chain_conveyor', chainConveyor);
    registerAssemblyListener('create:chain_conveyor_terminal', chainConveyor);
    registerAssemblyListener('create:display_link', const DisplayLinkAssemblyListener());
  }

  /// Forgets every registered block contribution and host lookup (tests, plugin
  /// unload).
  static void uninstall() {
    _installed = false;
    liftProviders.clear();
    centersOfMass.clear();
    collisionCallbacks.clear();
    assemblyListeners.clear();
    blockEntityLookup = null;
    beltStateReader = null;
    chainConveyorValidate = null;
    chainConveyorCheckInvalid = null;
    displayLinkTarget = null;
    displayLinkRetarget = null;
  }
}
