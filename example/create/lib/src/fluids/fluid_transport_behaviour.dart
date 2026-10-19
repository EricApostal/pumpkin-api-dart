// `FluidTransportBehaviour` and its variants (host side): the block entity
// behaviour of pipes and pumps. The connection data and the per-tick logic are
// the pure `PipeNodeMixin`; this file binds it to the block entity and to the
// host world.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/block_state.dart';
import '../api/blocks.dart' show HostBlockGetter;
import '../common/data.dart' show Couple;
import '../common/direction.dart';
import '../common/nbt_convert.dart';
import '../common/pos.dart';
import '../core/block_entity.dart';
import '../core/nbt.dart';
import 'fluid_runtime.dart';
import 'fluid_stack.dart';
import 'fluid_world.dart';
import 'pipe_block_entities.dart';
import 'pipe_blocks.dart';
import 'pipe_node.dart';

/// `FluidTransportBehaviour`.
abstract class FluidTransportBehaviour extends BlockEntityBehaviour
    with PipeNodeMixin {
  static const String type = 'fluid_transport';

  @override
  String get id => type;

  @override
  Pos get nodePos => (owner.pos.x, owner.pos.y, owner.pos.z);

  @override
  FluidWorld? get nodeWorld => FluidsRuntime.instance.levelOf(owner.worldId);

  @override
  BState get nodeState {
    final w = owner.world;
    if (w == null) return BState.air;
    return HostBlockGetter.stateOfId(w.getBlockStateId(pos: owner.pos));
  }

  @override
  void nodeSendData() => owner.sendData();

  @override
  bool get isRemoved => owner.removed;

  @override
  void initialize() {
    super.initialize();
    pipeInitialize();
  }

  @override
  void tick() {
    super.tick();
    pipeTick();
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    pipeRead(valueOfCompound(tag).asCompound, clientPacket: clientPacket);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    final out = <String, NbtValue>{};
    pipeWrite(out, clientPacket: clientPacket);
    for (final entry in out.entries) {
      final value = entry.value;
      if (value.kind == NbtKind.compound)
        tag.putCompound(entry.key, compoundOf(value));
    }
  }
}

/// `FluidPipeBlockEntity.StandardPipeFluidTransportBehaviour`: a six-way pipe.
class StandardPipeTransportBehaviour extends FluidTransportBehaviour {
  @override
  bool canHaveFlowToward(BState state, Direction direction) =>
      (PipeBlocks.isPipe(state) || PipeBlocks.isEncased(state)) &&
      state.flag(direction.serializedName);
}

/// `StraightPipeBlockEntity.StraightPipeFluidTransportBehaviour`: glass pipes and
/// the blocks that only flow along one axis.
class StraightPipeTransportBehaviour extends FluidTransportBehaviour {
  @override
  bool canHaveFlowToward(BState state, Direction direction) =>
      state.axisOf('axis') == direction.axis;
}

/// `SmartFluidPipeBlockEntity.SmartPipeBehaviour`.
class SmartPipeTransportBehaviour extends StraightPipeTransportBehaviour {
  @override
  bool canHaveFlowToward(BState state, Direction direction) =>
      PipeBlocks.smartPipeAxis(state) == direction.axis;

  @override
  bool canPullFluidFrom(FStack fluid, BState state, Direction direction) {
    final filter = (owner as SmartFluidPipeBlockEntity).filterFluid;
    if (fluid.isEmpty) return super.canPullFluidFrom(fluid, state, direction);
    if (filter == null) return super.canPullFluidFrom(fluid, state, direction);
    return FluidKeys.still(filter) == FluidKeys.still(fluid.fluid) &&
        super.canPullFluidFrom(fluid, state, direction);
  }
}

/// `FluidValveBlockEntity.ValvePipeBehaviour`: only pulls while the valve is open.
class ValveTransportBehaviour extends StraightPipeTransportBehaviour {
  @override
  bool canHaveFlowToward(BState state, Direction direction) =>
      PipeBlocks.valvePipeAxis(state) == direction.axis;

  @override
  bool canPullFluidFrom(FStack fluid, BState state, Direction direction) {
    if (!PipeBlocks.valveAllowsPull(state)) return false;
    return super.canPullFluidFrom(fluid, state, direction);
  }
}

/// `PumpBlockEntity.PumpFluidTransferBehaviour`: the pump's own pressure.
class PumpTransportBehaviour extends FluidTransportBehaviour {
  @override
  bool canHaveFlowToward(BState state, Direction direction) =>
      PipeBlocks.pumpFacing(state).axis == direction.axis;

  @override
  void tick() {
    super.tick();
    final pump = owner as PumpBlockEntity;
    final speed = pump.speed.abs();
    final facing = pump.facing;
    final map = interfaces;
    if (map == null) return;
    for (final entry in map.entries) {
      final pull = !(entry.key == facing);
      entry.value.pressure = pull
          ? Couple<double>(speed, 0)
          : Couple<double>(0, speed);
    }
  }
}
