// `FluidNetwork` (pure): layer III of the pipes. Starting from the endpoint that pulls, it
// searches the pipes with complete flows for the endpoints that receive, and every tick moves
// fluid from the source to them.
import '../common/data.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import 'flow_source.dart';
import 'fluid_stack.dart';
import 'fluid_storage.dart';
import 'fluid_world.dart';
import 'pipe_connection.dart';

class FluidNetwork {
  static const int cyclesPerTick = 16;

  final FluidWorld world;
  final BlockFace start;
  final FluidStorage? Function(FluidWorld world) sourceSupplier;

  FluidStorage? source;
  int transferSpeed = 0;
  int pauseBeforePropagation = 0;

  final List<BlockFace> queued = [];
  final List<(BlockFace, PipeConnection)> frontier = [];
  final Set<Pos> visited = {};
  FStack fluid = FStack.empty;
  final List<FlowTarget> targets = [];
  final Map<Pos, PipeNodeView> _cache = {};

  FluidNetwork(this.world, this.start, this.sourceSupplier) {
    reset();
  }

  void tick() {
    if (pauseBeforePropagation > 0) {
      pauseBeforePropagation--;
      return;
    }

    for (var cycle = 0; cycle < cyclesPerTick; cycle++) {
      var shouldContinue = false;

      final stillQueued = <BlockFace>[];
      for (final blockFace in queued) {
        if (!_isPresent(blockFace)) {
          stillQueued.add(blockFace);
          continue;
        }
        final pipeConnection = _get(blockFace);
        if (pipeConnection != null) {
          if (blockFace == start) {
            final inbound = pipeConnection.pressure.get(true) / 2;
            transferSpeed = inbound < 1 ? 1 : inbound.toInt();
          }
          if (!_frontierContains(blockFace, pipeConnection)) frontier.add((blockFace, pipeConnection));
        }
      }
      queued
        ..clear()
        ..addAll(stillQueued);

      final toRemove = <(BlockFace, PipeConnection)>[];
      // The frontier can grow while it is walked (it does not in Java: queued is separate).
      for (final entry in List.of(frontier)) {
        final blockFace = entry.$1;
        final pipeConnection = entry.$2;
        if (!pipeConnection.hasFlow) continue;

        final flow = pipeConnection.flow!;
        if (fluid.isNotEmpty && !flow.fluid.isSameFluid(fluid)) {
          toRemove.add(entry);
          continue;
        }

        if (!flow.inbound) {
          if (pipeConnection.comparePressure() >= 0) toRemove.add(entry);
          continue;
        }
        if (!flow.complete) continue;
        if (fluid.isEmpty) fluid = flow.fluid;

        var canRemove = true;
        for (final side in Direction.values) {
          if (side == blockFace.face) continue;

          final adjacentLocation = BlockFace(blockFace.pos, side);
          final adjacent = _get(adjacentLocation);
          if (adjacent == null) continue;

          if (!adjacent.hasFlow) {
            // Branch could potentially still appear
            if (adjacent.hasPressure && adjacent.pressure.second > 0) canRemove = false;
            continue;
          }

          final outFlow = adjacent.flow!;
          if (outFlow.inbound) {
            if (adjacent.comparePressure() > 0) canRemove = false;
            continue;
          }
          if (!outFlow.complete) {
            canRemove = false;
            continue;
          }

          // Give the pipe end a chance to init connections
          if (adjacent.source == null && !adjacent.determineSource(world, blockFace.pos)) {
            canRemove = false;
            continue;
          }

          if (adjacent.source != null && adjacent.source!.isEndpoint) {
            targets.add(FlowTarget(adjacentLocation, adjacent.source));
            continue;
          }

          if (visited.add(adjacentLocation.connectedPos)) {
            queued.add(adjacentLocation.opposite);
            shouldContinue = true;
          }
        }

        if (canRemove) toRemove.add(entry);
      }
      for (final r in toRemove) {
        frontier.remove(r);
      }

      if (!shouldContinue) break;
    }

    // `if (source == null) source = sourceSupplier.get()`: the handler is kept once found.
    source ??= sourceSupplier(world);
    if (source == null) return;

    _keepPortableFluidInterfaceEngaged();

    if (targets.isEmpty) return;

    for (final target in targets) {
      if (target.source != null && world.gameTime % 40 != 0) continue;
      final pipeConnection = _get(target.face);
      if (pipeConnection == null) continue;
      final fs = pipeConnection.source;
      if (fs != null && fs.isEndpoint) target.source = fs;
    }

    var flowSpeed = transferSpeed;

    // Targets that were filled in the simulation pass already (several faces of one handler).
    final accumulatedFill = <FluidStorage, int>{};

    for (final simulate in const [true, false]) {
      final sourceCap = source;
      if (sourceCap == null) return;

      var transfer = FStack.empty;
      for (var i = 0; i < sourceCap.tanks; i++) {
        final contained = sourceCap.fluidInTank(i);
        if (contained.isEmpty) continue;
        if (!contained.isSameFluid(fluid)) continue;
        final toExtract = contained.withAmount(flowSpeed);
        transfer = sourceCap.drainFluid(toExtract, simulate: simulate);
        break;
      }

      if (transfer.isEmpty) {
        final genericExtract = sourceCap.drain(flowSpeed, simulate: simulate);
        if (genericExtract.isNotEmpty && genericExtract.isSameFluid(fluid)) transfer = genericExtract;
      }

      if (transfer.isEmpty) return;

      if (simulate) flowSpeed = transfer.amount;

      final availableOutputs = List<FlowTarget>.of(targets);
      while (availableOutputs.isNotEmpty && transfer.amount > 0) {
        final dividedTransfer = transfer.amount ~/ availableOutputs.length;
        var remainder = transfer.amount % availableOutputs.length;

        for (final out in List.of(availableOutputs)) {
          var toTransfer = dividedTransfer;
          if (remainder > 0) {
            toTransfer++;
            remainder--;
          }

          if (transfer.isEmpty) break;
          final targetHandler = out.source?.provideHandler(world);
          if (targetHandler == null) {
            availableOutputs.remove(out);
            continue;
          }

          var simulatedTransfer = toTransfer;
          if (simulate) simulatedTransfer += accumulatedFill[targetHandler] ?? 0;

          final divided = transfer.withAmount(simulatedTransfer);
          var fill = targetHandler.fill(divided, simulate: simulate);

          if (simulate) {
            accumulatedFill[targetHandler] = fill;
            fill -= simulatedTransfer - toTransfer;
          }

          transfer = transfer.withAmount(transfer.amount - fill);
          if (fill < simulatedTransfer) availableOutputs.remove(out);
        }
      }

      flowSpeed -= transfer.amount;
      transfer = FStack.empty;
    }
  }

  bool _frontierContains(BlockFace face, PipeConnection connection) {
    for (final e in frontier) {
      if (e.$1 == face && identical(e.$2, connection)) return true;
    }
    return false;
  }

  /// `keepPortableFluidInterfaceEngaged()`.
  void _keepPortableFluidInterfaceEngaged() {
    final s = source;
    if (s is KeepAliveFluidStorage && frontier.isNotEmpty) s.keepAlive();
  }

  /// `reset()`.
  void reset() {
    frontier.clear();
    visited.clear();
    targets.clear();
    queued.clear();
    fluid = FStack.empty;
    queued.add(start);
    pauseBeforePropagation = 2;
  }

  PipeConnection? _get(BlockFace location) {
    final transfer = _getFluidTransfer(location.pos);
    if (transfer == null) return null;
    return transfer.getConnection(location.face);
  }

  bool _isPresent(BlockFace location) => world.isLoaded(location.pos);

  PipeNodeView? _getFluidTransfer(Pos pos) {
    var behaviour = _cache[pos];
    if (behaviour != null && behaviour.isRemoved) behaviour = null;
    if (behaviour == null) {
      behaviour = world.pipeAt(pos);
      if (behaviour != null) _cache[pos] = behaviour;
    }
    return behaviour;
  }
}

class FlowTarget {
  final BlockFace face;
  FlowSource? source;

  FlowTarget(this.face, this.source);
}
