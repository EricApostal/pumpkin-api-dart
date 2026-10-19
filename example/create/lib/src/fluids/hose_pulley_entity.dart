// `HosePulleyBlockEntity` (host side): the kinetic hose pulley. Its hose
// reaches down while it turns; the filling and draining searches are the pure
// `FluidFilling` / `FluidDraining`, the handler is the pure
// `HosePulleyFluidHandler`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../common/nbt_convert.dart';
import '../common/pos.dart';
import '../core/nbt.dart';
import '../kinetics/kinetic_block_entity.dart';
import '../kinetics/settings.dart' show convertToLinear;
import 'fluid_host.dart';
import 'fluid_manipulation.dart';
import 'fluid_runtime.dart';
import 'fluid_stack.dart';
import 'fluid_storage.dart';
import 'fluid_world.dart';
import 'hose_pulley_handler.dart';
import 'nbt_util.dart';

/// `HosePulleyBlockEntity`.
class HosePulleyBlockEntity extends KineticBlockEntity
    implements FluidCapable, ManipulationHost {
  HosePulleyBlockEntity(super.worldId, super.pos) {
    internalTank = SmartFluidTank(1500, _onTankContentsChanged);
    drainer = FluidDraining(this);
    filler = FluidFilling(this);
    handler = HosePulleyFluidHandler(
      internalTank,
      filler,
      drainer,
      () => rootPos,
      () => !isMoving,
    );
  }

  late final SmartFluidTank internalTank;
  late final FluidDraining drainer;
  late final FluidFilling filler;
  late final HosePulleyFluidHandler handler;

  /// `offset`: how far the hose reaches down, in blocks.
  double offset = 0;

  /// `isMoving`.
  bool isMoving = true;

  bool infinite = false;

  Pos get posOf => (this.pos.x, this.pos.y, this.pos.z);

  /// `worldPosition.below((int) Math.ceil(offset))`.
  Pos get rootPos => posOf.belowBy(offset.ceil());

  /// `getMovementSpeed()` (server side).
  double get movementSpeed => convertToLinear(speed);

  @override
  FluidWorld? get fluidWorld => FluidsRuntime.instance.levelOf(worldId);

  @override
  Pos get hostPos => posOf;

  @override
  void award(String advancement) =>
      FluidsRuntime.instance.award(worldId, posOf, advancement);

  @override
  FluidStorage? get fluidHandler => handler;

  void _onTankContentsChanged(FStack contents) {}

  @override
  void sendData() {
    infinite = filler.isInfinite || drainer.isInfinite;
    super.sendData();
  }

  @override
  void onSpeedChanged(double previousSpeed) {
    isMoving = true;
    if (speed == 0) {
      offset = offset.roundToDouble();
      isMoving = false;
    }

    final level = fluidWorld;
    if (isMoving && level != null) {
      final newOffset = offset + movementSpeed;
      if (newOffset < 0) isMoving = false;
      if (!level.canBeReplaced(posOf.belowBy(newOffset.ceil()))) {
        isMoving = false;
      }
      if (isMoving) {
        drainer.reset();
        filler.reset();
      }
    }

    super.onSpeedChanged(previousSpeed);
  }

  @override
  void tick() {
    super.tick();
    final level = fluidWorld;
    if (level == null) return;

    var newOffset = offset + movementSpeed;
    if (newOffset < 0) {
      newOffset = 0;
      isMoving = false;
    }
    if (!level.canBeReplaced(posOf.belowBy(newOffset.ceil()))) {
      newOffset = newOffset.truncateToDouble();
      isMoving = false;
    }
    if (speed == 0) isMoving = false;

    offset = newOffset;
    filler.tick();
    drainer.tick();
  }

  @override
  void lazyTick() {
    super.lazyTick();
    final level = fluidWorld;
    if (level == null) return;
    if (isMoving) return;

    final ceil = (offset + movementSpeed).ceil();
    if (movementSpeed > 0 && level.canBeReplaced(posOf.belowBy(ceil))) {
      isMoving = true;
      drainer.reset();
      filler.reset();
      return;
    }
    sendData();
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putDouble('Offset', offset);
    tag.putCompound('Tank', compoundOf(FluidNbt.write(internalTank.fluid)));

    final fillerNbt = <String, NbtValue>{};
    filler.write(fillerNbt);
    if (fillerNbt.isNotEmpty) {
      tag.putCompound('Filler', compoundOf(NbtValue.compound(fillerNbt)));
    }
    final drainerNbt = <String, NbtValue>{};
    drainer.write(drainerNbt);
    if (drainerNbt.isNotEmpty) {
      tag.putCompound('Drainer', compoundOf(NbtValue.compound(drainerNbt)));
    }

    super.write(tag, clientPacket: clientPacket);
    if (clientPacket) tag.putBool('Infinite', infinite);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    offset = tag.getDouble('Offset') ?? 0;
    final tankTag = tag.getCompound('Tank');
    if (tankTag != null) {
      internalTank.rawSet(FluidNbt.read(valueOfCompound(tankTag)));
    }
    final fillerTag = tag.getCompound('Filler');
    if (fillerTag != null) filler.read(valueOfCompound(fillerTag).asCompound);
    final drainerTag = tag.getCompound('Drainer');
    if (drainerTag != null) {
      drainer.read(valueOfCompound(drainerTag).asCompound);
    }

    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) infinite = tag.getBool('Infinite') ?? false;
  }
}
