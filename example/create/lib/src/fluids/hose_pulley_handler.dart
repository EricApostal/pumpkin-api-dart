// `HosePulleyFluidHandler` (pure): the hose pulley's fluid handler. It fills and drains an
// internal tank of 1500 mB and, when the hose reaches into fluid, buckets (1000 mB) are placed
// into or taken out of the world through the filling and draining behaviours.
import '../common/pos.dart';
import 'fluid_helper.dart';
import 'fluid_manipulation.dart';
import 'fluid_stack.dart';
import 'fluid_storage.dart';

class HosePulleyFluidHandler implements FluidStorage {
  final SmartFluidTank internalTank;
  final FluidFilling filler;
  final FluidDraining drainer;
  final Pos Function() rootPosGetter;
  final bool Function() predicate;

  HosePulleyFluidHandler(this.internalTank, this.filler, this.drainer, this.rootPosGetter, this.predicate);

  @override
  int get tanks => internalTank.tanks;

  @override
  FStack fluidInTank(int tank) {
    if (internalTank.isEmpty) return drainer.getDrainableFluid(rootPosGetter());
    return internalTank.fluidInTank(tank);
  }

  @override
  int tankCapacity(int tank) => internalTank.tankCapacity(tank);

  @override
  bool isFluidValid(int tank, FStack stack) => internalTank.isFluidValid(tank, stack);

  @override
  int fill(FStack resource, {required bool simulate}) {
    if (resource.isEmpty) return 0;
    final amount = resource.amount;
    final tankFluid = internalTank.fluid;
    final tankAmount = tankFluid.amount;

    if (tankFluid.isNotEmpty && !resource.isSameFluid(tankFluid)) return 0;
    if (!FluidHelper.hasBlockState(resource.fluid)) return 0;

    var diff = amount;
    final totalAmountAfterFill = diff + tankAmount;
    var remaining = amount;
    var deposited = false;

    if (predicate() && totalAmountAfterFill >= 1000) {
      final fluid = resource.fluid;
      final root = rootPosGetter();
      if (filler.tryDeposit(fluid, root, simulate: true)) {
        if (!simulate) {
          if (filler.tryDeposit(fluid, root, simulate: false)) {
            drainer.notifyCounterpartActed();
          } else {
            // the world changed in between; keep what fits instead of voiding it
            final newAmount = internalTank.capacity < tankAmount + 1000 ? internalTank.capacity : tankAmount + 1000;
            internalTank.setFluid(resource.withAmount(newAmount));
            return amount < 1000 ? amount : 1000;
          }
        }
        remaining -= 1000;
        diff -= 1000;
        deposited = true;
      }
    }

    if (diff <= 0) {
      // part of the deposited bucket came from the internal tank
      if (!simulate) {
        final newAmount = tankAmount + diff;
        internalTank.setFluid(newAmount <= 0 ? FStack.empty : tankFluid.withAmount(newAmount));
      }
      return amount;
    }

    var filled = 0;
    if (internalTank.isFluidValid(0, resource)) {
      final room = internalTank.capacity - tankAmount;
      filled = remaining < (room < 0 ? 0 : room) ? remaining : (room < 0 ? 0 : room);
      if (filled > 0 && !simulate) internalTank.setFluid(resource.withAmount(tankAmount + filled));
    }
    return filled + (deposited ? 1000 : 0);
  }

  @override
  FStack drainFluid(FStack resource, {required bool simulate}) {
    if (resource.isEmpty) return FStack.empty;
    return _extract(resource, resource.amount, simulate);
  }

  @override
  FStack drain(int maxDrain, {required bool simulate}) => _extract(null, maxDrain, simulate);

  FStack _extract(FStack? filter, int amount, bool simulate) {
    if (amount <= 0) return FStack.empty;
    final tankFluid = internalTank.fluid;
    final tankAmount = tankFluid.amount;
    if (filter != null && tankFluid.isNotEmpty && !filter.isSameFluid(tankFluid)) return FStack.empty;

    if (tankAmount >= 1000) return _extractFromTank(filter, amount, simulate);

    final pos = rootPosGetter();
    final returned = drainer.getDrainableFluid(pos);
    if (!predicate() || !drainer.pullNext(pos, simulate: true)) return _extractFromTank(filter, amount, simulate);

    if (tankFluid.isNotEmpty && !tankFluid.isSameFluid(returned) || returned.isEmpty) {
      return _extractFromTank(filter, amount, simulate);
    }
    if (filter != null && !filter.isSameFluid(returned)) return FStack.empty;

    final available = 1000 + tankAmount;
    final drained = amount < available ? amount : available;
    final leftover = available - drained;

    if (!simulate) {
      internalTank.setFluid(leftover > 0 ? returned.withAmount(leftover) : FStack.empty);
      drainer.pullNext(pos, simulate: false);
      filler.notifyCounterpartActed();
    }
    return returned.withAmount(drained);
  }

  FStack _extractFromTank(FStack? filter, int amount, bool simulate) {
    final tankFluid = internalTank.fluid;
    if (tankFluid.isEmpty) return FStack.empty;
    if (filter != null && !filter.isSameFluid(tankFluid)) return FStack.empty;
    final extracted = amount < tankFluid.amount ? amount : tankFluid.amount;
    if (extracted <= 0) return FStack.empty;
    if (!simulate) {
      final newAmount = tankFluid.amount - extracted;
      internalTank.setFluid(newAmount <= 0 ? FStack.empty : tankFluid.withAmount(newAmount));
    }
    return tankFluid.withAmount(extracted);
  }
}
