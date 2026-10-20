// `PipeConnection`: one face of a pipe (pure). Layer I is the pressure the pumps distribute,
// layer II the flow that starts, reverses or stops according to it, layer III the network that
// moves the fluid from a source to the endpoints.
import '../common/data.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import '../core/nbt.dart';
import 'fluid_network.dart';
import 'fluid_propagator.dart';
import 'fluid_stack.dart';
import 'fluid_world.dart';
import 'flow_source.dart';
import 'nbt_util.dart';
import 'open_ended_pipe.dart';

// DEBUG-FLUID
int _dbgMf = 0;
int _dbgW = 0;

/// `PipeConnection.Flow`.
class Flow {
  bool complete = false;
  bool inbound;
  double progress = 0;
  FStack fluid;

  Flow(this.inbound, this.fluid);
}

class PipeConnection {
  final Direction side;

  // Layer I
  Couple<double> pressure = Couple<double>(0, 0); // [inbound, outward]
  FlowSource? source;
  FlowSource? previousSource;

  // Layer II
  Flow? flow;

  // Layer III (not serialized)
  FluidNetwork? network;

  PipeConnection(this.side);

  /// `getProvidedFluid()`: what a complete inbound flow brings.
  FStack get providedFluid {
    final f = flow;
    if (f == null || !f.inbound || !f.complete) return FStack.empty;
    return f.fluid;
  }

  /// `flipFlowsIfPressureReversed()`.
  bool flipFlowsIfPressureReversed() {
    final f = flow;
    if (f == null) return false;
    final singlePressure = comparePressure() != 0 && (inboundPressure == 0 || outwardPressure == 0);
    if (!singlePressure || (comparePressure() < 0) == f.inbound) return false;
    f.inbound = !f.inbound;
    if (!f.complete) flow = null;
    return true;
  }

  /// `manageSource(world, pos, blockEntity)`.
  void manageSource(FluidWorld world, Pos pos, PipeNodeView node) {
    if (source == null && !determineSource(world, pos)) return;
    source!.manageSource(world, node);
  }

  /// `manageFlows(world, pos, internalFluid, extractionPredicate)`; true when the data changed.
  bool manageFlows(FluidWorld world, Pos pos, FStack internalFluid, bool Function(FStack fluid) extractionPredicate) {
    // DEBUG-FLUID
    _dbgMf++;
    if (_dbgMf % 40 == 0) {
      print('DEBUGFLUID mf pos=${pos.$1},${pos.$2},${pos.$3} side=$side '
          'flow=$hasFlow(${flow?.inbound}/${flow?.complete}) press=$hasPressure '
          'src=${source.runtimeType} internal=${internalFluid.fluid}:${internalFluid.amount}');
    }
    // Only keep the network if it is still valid.
    final retainedNetwork = network;
    network = null;

    // chunk border
    if (source == null && !determineSource(world, pos)) return false;
    final flowSource = source!;

    if (!hasFlow) {
      if (!hasPressure) return false;

      // Try starting a new flow
      final prioritizeInbound = comparePressure() < 0;
      for (final trueFalse in const [true, false]) {
        final inbound = prioritizeInbound == trueFalse;
        if ((inbound ? inboundPressure : outwardPressure) == 0) continue;
        if (_tryStartingNewFlow(inbound, inbound ? flowSource.provideFluid(world, extractionPredicate) : internalFluid)) {
          return true;
        }
      }
      return false;
    }

    // Manage existing flow
    final f = flow!;
    final provided = f.inbound ? flowSource.provideFluid(world, extractionPredicate) : internalFluid;

    // DEBUG-FLUID
    if (pos.$1 == 1 && side == Direction.west) {
      _dbgW++;
      if (_dbgW % 20 == 0) {
        print('DEBUGFLUID west in=${f.inbound} complete=${f.complete} press=$hasPressure '
            'src=${flowSource.runtimeType} provided=${provided.fluid}:${provided.amount} '
            'same=${provided.isSameFluid(f.fluid)} internal=${internalFluid.fluid}:${internalFluid.amount}');
      }
    }

    // Whether the flow is still valid
    if (!hasPressure || provided.isEmpty || !provided.isSameFluid(f.fluid)) {
      flow = null;
      return true;
    }

    // Overwrite existing flow
    if (f.inbound != comparePressure() < 0) {
      final inbound = !f.inbound;
      if (inbound && provided.isNotEmpty || !inbound && internalFluid.isNotEmpty) {
        FluidPropagator.resetAffectedFluidNetworks(world, pos, side);
        _tryStartingNewFlow(inbound, inbound ? flowSource.provideFluid(world, extractionPredicate) : internalFluid);
        return true;
      }
    }

    flowSource.whileFlowPresent(world, f.inbound);

    // DEBUG-FLUID
    if (pos.$1 == 1 && side == Direction.west && _dbgW % 20 == 0) {
      print('DEBUGFLUID west layer3 endpoint=${flowSource.isEndpoint} inbound=${f.inbound} '
          'net=${retainedNetwork != null}');
    }

    if (!flowSource.isEndpoint) return false;
    if (!f.inbound) return false;

    // Layer III
    network = retainedNetwork;
    network ??= FluidNetwork(world, BlockFace(pos, side), (w) => flowSource.provideHandler(w));
    network!.tick();
    return false;
  }

  bool _tryStartingNewFlow(bool inbound, FStack providedFluid) {
    if (providedFluid.isEmpty) return false;
    flow = Flow(inbound, providedFluid);
    return true;
  }

  /// `determineSource(world, pos)`: false at a chunk border.
  bool determineSource(FluidWorld world, Pos pos) {
    final relative = pos.relative(side);
    if (!world.isLoaded(relative)) return false;

    final location = BlockFace(pos, side);
    if (FluidPropagator.isOpenEnd(world, pos, side)) {
      final prev = previousSource;
      source = prev is OpenEndedPipe ? prev : OpenEndedPipe(location);
      return true;
    }

    if (FluidPropagator.hasFluidCapability(world, location.connectedPos, side.opposite)) {
      source = FluidHandlerSource(location);
      return true;
    }

    final behaviour = world.pipeAt(relative);
    source = behaviour == null ? BlockedSource(location) : OtherPipeSource(location);
    return true;
  }

  /// `tickFlowProgress(world, pos)` (the server part; particles are the client's).
  void tickFlowProgress(FluidWorld world, Pos pos) {
    final f = flow;
    if (f == null) return;
    if (f.fluid.isEmpty) return;

    final p = pressure.get(f.inbound);
    final clamped = (p / 128).clamp(0.0, 1.0);
    final flowSpeed = 1 / 32 + clamped * 31 / 32;
    f.progress = f.progress + flowSpeed > 1 ? 1 : f.progress + flowSpeed;
    if (f.progress >= 1) f.complete = true;
  }

  /// `serializeNBT`: the data of this face under its name.
  NbtValue serialize({required bool clientPacket}) {
    final data = <String, NbtValue>{};
    if (hasPressure) {
      data['Pressure'] = NbtValue.list([NbtValue.float(inboundPressure), NbtValue.float(outwardPressure)]);
    }
    final s = source;
    if (s is OpenEndedPipe) data['OpenEnd'] = s.serializeNbt();
    final f = flow;
    if (f != null) {
      final flowData = <String, NbtValue>{'Fluid': FluidNbt.write(f.fluid), 'In': NbtValue.byte(f.inbound ? 1 : 0)};
      if (!f.complete) {
        flowData['Progress'] = NbtValue.compound({
          'Speed': NbtValue.float(0),
          'Target': NbtValue.float(1),
          'Value': NbtValue.float(f.progress),
        });
      }
      data['Flow'] = NbtValue.compound(flowData);
    }
    return NbtValue.compound(data);
  }

  /// `deserializeNBT`.
  void deserialize(Map<String, NbtValue> connectionData, Pos blockEntityPos, {required bool clientPacket}) {
    final pressureData = connectionData.readList('Pressure');
    if (pressureData != null && pressureData.length >= 2) {
      pressure = Couple<double>(
        (pressureData[0].value as num).toDouble(),
        (pressureData[1].value as num).toDouble(),
      );
    } else {
      pressure = Couple<double>(0, 0);
    }

    source = null;
    final openEnd = connectionData.readCompound('OpenEnd');
    if (openEnd != null) source = OpenEndedPipe.fromNbt(openEnd, blockEntityPos, side);

    final flowData = connectionData.readCompound('Flow');
    if (flowData != null) {
      final fluid = FluidNbt.read(flowData['Fluid']);
      final inbound = flowData.readBool('In');
      final f = flow ??= Flow(inbound, fluid);
      f.fluid = fluid;
      f.inbound = inbound;
      final progress = flowData.readCompound('Progress');
      f.complete = progress == null;
      if (progress != null) {
        f.progress = progress.readDouble('Value') ?? 0;
      } else {
        f.progress = 1;
      }
    } else {
      flow = null;
    }
  }

  /// `comparePressure()`: zero if outward == inbound, positive if outward > inbound.
  double comparePressure() => outwardPressure - inboundPressure;

  /// `wipePressure()`.
  void wipePressure() {
    pressure = Couple<double>(0, 0);
    if (source != null) previousSource = source;
    source = null;
    resetNetwork();
  }

  /// `provideOutboundFlow()`.
  FStack provideOutboundFlow() {
    final f = flow;
    if (f == null || !f.complete || f.inbound) return FStack.empty;
    return f.fluid;
  }

  /// `addPressure(inbound, pressure)`.
  void addPressure(bool inbound, double amount) {
    pressure = inbound ? Couple<double>(pressure.first + amount, pressure.second) : Couple<double>(pressure.first, pressure.second + amount);
  }

  bool get hasPressure => inboundPressure != 0 || outwardPressure != 0;

  double get outwardPressure => pressure.second;
  double get inboundPressure => pressure.first;

  bool get hasFlow => flow != null;
  bool get hasNetwork => network != null;

  /// `hasOpenEnd()`.
  bool get hasOpenEnd => source is OpenEndedPipe;

  /// `resetNetwork()`.
  void resetNetwork() => network?.reset();
}
