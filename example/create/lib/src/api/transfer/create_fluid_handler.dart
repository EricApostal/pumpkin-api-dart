// `CreateFluidHandler` (pure): the fill / drain convenience methods Create's fluid code was
// written against, on top of the module's [FluidStorage] contract. The Dart module already uses
// the `simulate` boolean; [FluidAction] keeps the Java call sites readable.
import '../../fluids/fluid_stack.dart';
import '../../fluids/fluid_storage.dart';

/// `CreateFluidHandler.FluidAction`.
enum FluidAction {
  execute,
  simulate;

  /// `FluidAction.execute()`.
  bool get executing => this == FluidAction.execute;

  /// `FluidAction.simulate()`.
  bool get simulating => this == FluidAction.simulate;
}

/// `CreateFluidHandler`: the static helpers of the interface. Any [FluidStorage] is already a
/// Create fluid handler in this port.
abstract final class CreateFluidHandler {
  /// `CreateFluidHandler.of(handler)`: returns the handler itself (Dart has no wrapping needed).
  static FluidStorage of(FluidStorage handler) => handler;

  /// `fill(resource, action)`: the amount that was (or would be) filled.
  static int fill(FluidStorage handler, FStack resource, FluidAction action) =>
      handler.fill(resource, simulate: action.simulating);

  /// `drain(resource, action)`: drains only the fluid of [resource].
  static FStack drain(
    FluidStorage handler,
    FStack resource,
    FluidAction action,
  ) => handler.drainFluid(resource, simulate: action.simulating);

  /// `drain(maxDrain, action)`: drains up to [maxDrain] of whatever fluid is there.
  static FStack drainAny(
    FluidStorage handler,
    int maxDrain,
    FluidAction action,
  ) => handler.drain(maxDrain, simulate: action.simulating);
}

/// The same helpers as extension methods, for code that already has a handler.
extension CreateFluidHandlerOps on FluidStorage {
  /// `CreateFluidHandler.fill(resource, action)`.
  int fillAction(FStack resource, FluidAction action) =>
      fill(resource, simulate: action.simulating);

  /// `CreateFluidHandler.drain(resource, action)`.
  FStack drainAction(FStack resource, FluidAction action) =>
      drainFluid(resource, simulate: action.simulating);

  /// `CreateFluidHandler.drain(maxDrain, action)`.
  FStack drainAnyAction(int maxDrain, FluidAction action) =>
      drain(maxDrain, simulate: action.simulating);
}
