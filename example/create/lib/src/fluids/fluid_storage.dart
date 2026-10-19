// Fluid tanks and handlers (pure): `CreateFluidTank`, `SmartFluidTank`, the creative tank,
// `CombinedTankWrapper` and the `IFluidHandler` contract everything else moves fluids through.
// Create's 26.x transfer API is transactional; the host's handlers are not, so the semantics are
// those of the `fill` / `drain` pairs with `simulate`.
import 'fluid_stack.dart';

/// `IFluidHandler`: tanks holding fluids that can be filled and drained, in millibuckets.
abstract interface class FluidStorage {
  /// `getTanks()`.
  int get tanks;

  /// `getFluidInTank(tank)`.
  FStack fluidInTank(int tank);

  /// `getTankCapacity(tank)`.
  int tankCapacity(int tank);

  /// `isFluidValid(tank, stack)`.
  bool isFluidValid(int tank, FStack stack);

  /// `fill(resource, action)`: returns the amount that was (or would be) filled.
  int fill(FStack resource, {required bool simulate});

  /// `drain(resource, action)`: drains only the fluid of [resource].
  FStack drainFluid(FStack resource, {required bool simulate});

  /// `drain(maxDrain, action)`: drains up to [maxDrain] of whatever fluid is there.
  FStack drain(int maxDrain, {required bool simulate});
}

/// `CreateFluidTank` / vanilla's `FluidTank`: one tank.
class FluidTank implements FluidStorage {
  FStack _fluid = FStack.empty;
  int capacity;
  bool Function(FStack stack) validator;

  FluidTank(this.capacity, {bool Function(FStack stack)? validator}) : validator = validator ?? _any;

  static bool _any(FStack _) => true;

  /// `getFluid()`.
  FStack get fluid => _fluid;

  /// `setFluid`: overwrites the contents without calling [onContentsChanged].
  void setFluid(FStack stack) => rawSet(stack);

  /// Overwrites the contents without any callback.
  void rawSet(FStack stack) => _fluid = stack.isEmpty ? FStack.empty : stack;

  int get fluidAmount => _fluid.amount;
  bool get isEmpty => _fluid.isEmpty;

  /// `getSpace()`.
  int get space => capacity - fluidAmount < 0 ? 0 : capacity - fluidAmount;

  /// Called after the contents changed through `fill` / `drain`.
  void onContentsChanged() {}

  bool isValidStack(FStack stack) => validator(stack);

  @override
  int get tanks => 1;

  @override
  FStack fluidInTank(int tank) => _fluid;

  @override
  int tankCapacity(int tank) => capacity;

  @override
  bool isFluidValid(int tank, FStack stack) => validator(stack);

  @override
  int fill(FStack resource, {required bool simulate}) {
    if (resource.isEmpty || !validator(resource)) return 0;
    if (simulate) {
      if (_fluid.isEmpty) return resource.amount < capacity ? resource.amount : capacity;
      if (!_fluid.isSameFluid(resource)) return 0;
      final room = capacity - _fluid.amount;
      return resource.amount < room ? resource.amount : (room < 0 ? 0 : room);
    }
    if (_fluid.isEmpty) {
      final filled = resource.amount < capacity ? resource.amount : capacity;
      _fluid = resource.withAmount(filled);
      onContentsChanged();
      return filled;
    }
    if (!_fluid.isSameFluid(resource)) return 0;
    var filled = capacity - _fluid.amount;
    if (filled < 0) filled = 0;
    if (resource.amount < filled) filled = resource.amount;
    if (filled > 0) {
      _fluid = _fluid.grow(filled);
      onContentsChanged();
    }
    return filled;
  }

  @override
  FStack drainFluid(FStack resource, {required bool simulate}) {
    if (resource.isEmpty || !resource.isSameFluid(_fluid)) return FStack.empty;
    return drain(resource.amount, simulate: simulate);
  }

  @override
  FStack drain(int maxDrain, {required bool simulate}) {
    var drained = maxDrain;
    if (_fluid.amount < drained) drained = _fluid.amount;
    if (_fluid.isEmpty || drained <= 0) return FStack.empty;
    final stack = _fluid.withAmount(drained);
    if (!simulate) {
      _fluid = _fluid.shrink(drained);
      onContentsChanged();
    }
    return stack;
  }

  @override
  String toString() => '$runtimeType[$_fluid/$capacity]';
}

/// `SmartFluidTank`: calls [updateCallback] with the contents whenever they change.
class SmartFluidTank extends FluidTank {
  final void Function(FStack fluid) updateCallback;

  SmartFluidTank(super.capacity, this.updateCallback, {super.validator});

  @override
  void onContentsChanged() {
    super.onContentsChanged();
    updateCallback(fluid);
  }

  @override
  void setFluid(FStack stack) {
    super.setFluid(stack);
    updateCallback(fluid);
  }
}

/// `CreativeFluidTankBlockEntity.CreativeSmartFluidTank`: voids what is filled and never runs out
/// of the fluid it contains.
class CreativeSmartFluidTank extends SmartFluidTank {
  CreativeSmartFluidTank(super.capacity, super.updateCallback);

  @override
  int get fluidAmount => fluid.isEmpty ? 0 : capacity;

  @override
  int get space => 0;

  /// `setContainedFluid`: the tank is always full of this fluid.
  void setContainedFluid(FStack stack) {
    rawSet(stack.isEmpty ? FStack.empty : stack.withAmount(capacity));
    onContentsChanged();
  }

  @override
  int fill(FStack resource, {required bool simulate}) => resource.isEmpty ? 0 : resource.amount;

  @override
  FStack drainFluid(FStack resource, {required bool simulate}) {
    if (resource.isEmpty || !resource.isSameFluid(fluid)) return FStack.empty;
    return drain(resource.amount, simulate: simulate);
  }

  @override
  FStack drain(int maxDrain, {required bool simulate}) {
    if (fluid.isEmpty || maxDrain <= 0) return FStack.empty;
    return fluid.withAmount(maxDrain < fluid.amount ? maxDrain : fluid.amount);
  }
}

/// `CombinedTankWrapper`: several handlers as one.
class CombinedTankWrapper implements FluidStorage {
  final List<FluidStorage> handlers;
  bool enforceVariety = false;

  CombinedTankWrapper(this.handlers);

  CombinedTankWrapper enforceVarietyOn() {
    enforceVariety = true;
    return this;
  }

  @override
  int get tanks => handlers.fold(0, (n, h) => n + h.tanks);

  (FluidStorage, int)? _locate(int tank) {
    var t = tank;
    for (final h in handlers) {
      if (t < h.tanks) return (h, t);
      t -= h.tanks;
    }
    return null;
  }

  @override
  FStack fluidInTank(int tank) {
    final loc = _locate(tank);
    return loc == null ? FStack.empty : loc.$1.fluidInTank(loc.$2);
  }

  @override
  int tankCapacity(int tank) {
    final loc = _locate(tank);
    return loc == null ? 0 : loc.$1.tankCapacity(loc.$2);
  }

  @override
  bool isFluidValid(int tank, FStack stack) {
    final loc = _locate(tank);
    return loc != null && loc.$1.isFluidValid(loc.$2, stack);
  }

  @override
  int fill(FStack resource, {required bool simulate}) {
    if (resource.isEmpty) return 0;
    var filled = 0;
    var remaining = resource;
    var fittingHandlerFound = false;
    outer:
    for (final searchPass in const [true, false]) {
      for (final handler in handlers) {
        for (var i = 0; i < handler.tanks; i++) {
          if (searchPass && handler.fluidInTank(i).isSameFluid(remaining)) fittingHandlerFound = true;
        }
        if (searchPass && !fittingHandlerFound) continue;
        final filledIntoCurrent = handler.fill(remaining, simulate: simulate);
        remaining = remaining.shrink(filledIntoCurrent);
        filled += filledIntoCurrent;
        if (remaining.isEmpty || fittingHandlerFound && (enforceVariety || filledIntoCurrent != 0)) break outer;
      }
    }
    return filled;
  }

  @override
  FStack drainFluid(FStack resource, {required bool simulate}) {
    if (resource.isEmpty) return FStack.empty;
    var drained = FStack.empty;
    var remaining = resource;
    for (final handler in handlers) {
      final fromCurrent = handler.drainFluid(remaining, simulate: simulate);
      remaining = remaining.shrink(fromCurrent.amount);
      if (fromCurrent.isNotEmpty && (drained.isEmpty || fromCurrent.isSameFluid(drained))) {
        drained = fromCurrent.withAmount(fromCurrent.amount + drained.amount);
      }
      if (remaining.isEmpty) break;
    }
    return drained;
  }

  @override
  FStack drain(int maxDrain, {required bool simulate}) {
    var drained = FStack.empty;
    var left = maxDrain;
    for (final handler in handlers) {
      final fromCurrent = handler.drain(left, simulate: simulate);
      left -= fromCurrent.amount;
      if (fromCurrent.isNotEmpty && (drained.isEmpty || fromCurrent.isSameFluid(drained))) {
        drained = fromCurrent.withAmount(fromCurrent.amount + drained.amount);
      }
      if (left <= 0) break;
    }
    return drained;
  }
}

/// A handler without any tank (`new CreateFluidTank(0)`): fills and drains nothing.
final class EmptyFluidStorage implements FluidStorage {
  const EmptyFluidStorage();

  @override
  int get tanks => 1;
  @override
  FStack fluidInTank(int tank) => FStack.empty;
  @override
  int tankCapacity(int tank) => 0;
  @override
  bool isFluidValid(int tank, FStack stack) => true;
  @override
  int fill(FStack resource, {required bool simulate}) => 0;
  @override
  FStack drainFluid(FStack resource, {required bool simulate}) => FStack.empty;
  @override
  FStack drain(int maxDrain, {required bool simulate}) => FStack.empty;
}

/// `ItemFluidHandler` over a mutable list of tanks, used by the item side of the transfer code
/// (the fluid inside an item, [FluidItemContainer]).
abstract interface class FluidItemContainer implements FluidStorage {
  /// The item the handler works on, after the changes (`getContainer()`), as an item key.
  String get containerItem;
}

/// A handler that must be kept engaged while a pipe network pulls from it (the portable fluid
/// interface of contraptions): `InterfaceFluidHandler.keepAlive`.
abstract interface class KeepAliveFluidStorage implements FluidStorage {
  void keepAlive();
}
