// `FluidTransportBehaviour` as a mixin (pure): the connections of a pipe and their per-tick
// logic. The block entity behaviour of the host mixes it in; the tests use a plain class.
import '../api/block_state.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import '../core/nbt.dart';
import 'fluid_propagator.dart';
import 'fluid_reactions.dart';
import 'fluid_stack.dart';
import 'fluid_world.dart';
import 'nbt_util.dart';
import 'pipe_connection.dart';

/// `FluidTransportBehaviour.UpdatePhase`.
enum UpdatePhase {
  /// Do not run layer II logic while pumps could still be distributing pressure.
  waitForPumps,

  /// Do not cut any flows until all pipes had a chance to reverse them.
  flipFlows,

  /// Operate normally.
  idle,
}

mixin PipeNodeMixin implements PipeNodeView {
  /// `interfaces`: the connections by side, `null` until created.
  Map<Direction, PipeConnection>? interfaces;
  UpdatePhase phase = UpdatePhase.waitForPumps;

  // -- What the owner provides --------------------------------------------------------------

  /// The position of the owning block entity.
  Pos get nodePos;

  /// The world, `null` while it is unloaded.
  FluidWorld? get nodeWorld;

  /// The block state of the owner.
  BState get nodeState;

  /// `blockEntity.notifyUpdate()` / `sendData()`.
  void nodeSendData();

  @override
  bool get isRemoved;

  @override
  bool get isPumpNode => false;

  /// `canPullFluidFrom(fluid, state, direction)`.
  bool canPullFluidFrom(FStack fluid, BState state, Direction direction) => true;

  @override
  bool canHaveFlowToward(BState state, Direction direction);

  // -- Lifecycle ----------------------------------------------------------------------------

  /// `initialize()`.
  void pipeInitialize() => createConnectionData();

  /// `tick()`.
  void pipeTick() {
    final world = nodeWorld;
    if (world == null) return;
    final pos = nodePos;
    final connections = interfaces;
    if (connections == null) return;
    final values = connections.values.toList();

    // Do not provide a lone pipe connection with its own flow input
    PipeConnection? singleSource;

    if (phase == UpdatePhase.waitForPumps) {
      phase = UpdatePhase.flipFlows;
      return;
    }

    var sendUpdate = false;
    for (final connection in values) {
      sendUpdate |= connection.flipFlowsIfPressureReversed();
      connection.manageSource(world, pos, this);
    }
    if (sendUpdate) nodeSendData();

    if (phase == UpdatePhase.flipFlows) {
      phase = UpdatePhase.idle;
      return;
    }

    var availableFlow = FStack.empty;
    var collidingFlow = FStack.empty;

    for (final connection in values) {
      final fluidInFlow = connection.providedFluid;
      if (fluidInFlow.isEmpty) continue;
      if (availableFlow.isEmpty) {
        singleSource = connection;
        availableFlow = fluidInFlow;
        continue;
      }
      if (availableFlow.isSameFluid(fluidInFlow)) {
        singleSource = null;
        availableFlow = fluidInFlow;
        continue;
      }
      collidingFlow = fluidInFlow;
      break;
    }

    if (collidingFlow.isNotEmpty) {
      FluidReactions.handlePipeFlowCollision(world, pos, availableFlow, collidingFlow);
      return;
    }

    sendUpdate = false;
    for (final connection in values) {
      final internalFluid = !identical(singleSource, connection) ? availableFlow : FStack.empty;
      final side = connection.side;
      sendUpdate |= connection.manageFlows(world, pos, internalFluid, (extracted) => canPullFluidFrom(extracted, nodeState, side));
    }
    if (sendUpdate) nodeSendData();

    for (final connection in values) {
      connection.tickFlowProgress(world, pos);
    }
  }

  // -- NBT ----------------------------------------------------------------------------------

  /// `read(nbt, clientPacket)`.
  void pipeRead(Map<String, NbtValue> nbt, {required bool clientPacket}) {
    final map = interfaces ??= {};
    for (final face in Direction.values) {
      if (nbt.containsKey(face.serializedName)) map.putIfAbsent(face, () => PipeConnection(face));
    }

    // Invalid data (missing/outdated). Defer init to runtime
    if (map.isEmpty) {
      interfaces = null;
      return;
    }

    for (final connection in map.values) {
      final data = nbt.readCompound(connection.side.serializedName);
      connection.deserialize(data ?? const {}, nodePos, clientPacket: clientPacket);
    }
  }

  /// `write(nbt, clientPacket)`: adds the connections to [out].
  void pipeWrite(Map<String, NbtValue> out, {required bool clientPacket}) {
    if (clientPacket) createConnectionData();
    final map = interfaces;
    if (map == null) return;
    for (final connection in map.values) {
      out[connection.side.serializedName] = connection.serialize(clientPacket: clientPacket);
    }
  }

  // -- Queries ------------------------------------------------------------------------------

  @override
  FStack getProvidedOutwardFluid(Direction side) {
    createConnectionData();
    final c = interfaces![side];
    return c == null ? FStack.empty : c.provideOutboundFlow();
  }

  @override
  PipeConnection? getConnection(Direction side) {
    createConnectionData();
    return interfaces![side];
  }

  @override
  bool get hasAnyPressure {
    createConnectionData();
    for (final c in interfaces!.values) {
      if (c.hasPressure) return true;
    }
    return false;
  }

  /// `getFlow(side)`.
  Flow? getFlow(Direction side) {
    createConnectionData();
    return interfaces![side]?.flow;
  }

  @override
  void addPressure(Direction side, bool inbound, double pressure) {
    createConnectionData();
    final c = interfaces![side];
    if (c == null) return;
    c.addPressure(inbound, pressure);
    nodeSendData();
  }

  @override
  void wipePressure() {
    final map = interfaces;
    if (map != null) {
      for (final d in Direction.values) {
        if (!canHaveFlowToward(nodeState, d)) {
          map.remove(d);
        } else {
          map.putIfAbsent(d, () => PipeConnection(d));
        }
      }
    }
    phase = UpdatePhase.waitForPumps;
    createConnectionData();
    for (final c in interfaces!.values) {
      c.wipePressure();
    }
    nodeSendData();
  }

  /// `createConnectionData()`.
  void createConnectionData() {
    if (interfaces != null) return;
    final map = <Direction, PipeConnection>{};
    for (final d in Direction.values) {
      if (canHaveFlowToward(nodeState, d)) map[d] = PipeConnection(d);
    }
    interfaces = map;
  }

  /// Propagates a change of this pipe through the network.
  void propagateChange() {
    final world = nodeWorld;
    if (world != null) FluidPropagator.propagateChangedPipe(world, nodePos, nodeState);
  }
}

/// `FluidTransportBehaviour.interfaceTransfer`: pipes that switch block entities (a pipe becoming
/// a glass pipe) keep their flows across the change.
abstract final class PipeFlowTransfer {
  static final Map<String, Map<Direction, PipeConnection>?> _cache = {};

  static String _key(String worldId, Pos pos) => '$worldId:${posKey(pos)}';

  /// `cacheFlows(world, pos)`.
  static void cacheFlows(String worldId, Pos pos, PipeNodeMixin? node) {
    if (node != null) _cache[_key(worldId, pos)] = node.interfaces;
  }

  /// `loadFlows(world, pos)`.
  static void loadFlows(String worldId, Pos pos, PipeNodeMixin? node) {
    final cached = _cache.remove(_key(worldId, pos));
    if (node != null) node.interfaces = cached;
  }
}
