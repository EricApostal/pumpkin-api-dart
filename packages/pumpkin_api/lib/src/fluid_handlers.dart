import 'bindings.g.dart' as generated;
import 'bindings.g.dart';
import 'host_result.dart';

/// Moving fluids into and out of tanks (`fluid-handler.wit`): plugin block
/// entities with tanks, cauldrons, fluid blocks and fluid containing items.
/// Amounts are millibuckets, a bucket holds 1000. Needs the `containers`
/// permission ([Permissions.containers]).
///
/// ```dart
/// final tank = FluidHandlers.at(world, pos);
/// final drained = tank?.drain(maxAmount: 250, simulate: false);
/// if (drained != null) FluidHandlers.at(world, other)?.fill(drained, simulate: false);
/// ```
abstract final class FluidHandlers {
  /// The fluid handler of the block at [pos] seen from [side], or `null` if the
  /// chunk is not loaded, the block holds no fluid and takes none, or the
  /// plugin lacks the `containers` permission. A handler keeps working after
  /// the block is gone: ask again when the block may have changed.
  static FluidHandler? at(World world, BlockPos pos, {BlockDirection? side}) =>
      generated.fluidHandler.getFluidHandler(targetWorld: world, pos: pos, side: side);

  /// The fluid handler of [stack] (one tank), or `null` if the item holds no
  /// fluid. It changes the stack it was made for.
  static ItemFluidHandler? ofItem(ItemStack stack) =>
      generated.fluidHandler.getItemFluidHandler(stack: stack);

  /// Gives the plugin block entity at [pos] [tanks] tanks (at most 256) of
  /// [capacity] millibuckets each, or resizes the ones it has. Throws a
  /// [HostException] if there is no plugin block entity there, or shrinking
  /// would drop a tank that is not empty.
  static void registerTank(World world, BlockPos pos, {required int tanks, required int capacity}) =>
      unwrapHost(
        generated.fluidHandler.registerPluginTank(
          targetWorld: world,
          pos: pos,
          tankCount: tanks,
          capacityPerTank: capacity,
        ),
        'Registering the tanks at (${pos.x}, ${pos.y}, ${pos.z})',
      );

  /// Takes the tanks away from the plugin block entity at [pos] and returns the
  /// fluids that were in them. Throws a [HostException] if there is no such
  /// entity.
  static List<FluidStack> unregisterTank(World world, BlockPos pos) => unwrapHost(
    generated.fluidHandler.unregisterPluginTank(targetWorld: world, pos: pos),
    'Removing the tanks at (${pos.x}, ${pos.y}, ${pos.z})',
  );

  /// Makes the registered item [itemKey] a fluid container of [capacity]
  /// millibuckets that takes [allowedFluids] (any fluid if empty). The fluid is
  /// kept in the custom data of the stack. Throws a [HostException] for an
  /// unknown item or fluid.
  static void registerContainerItem(
    String itemKey, {
    required int capacity,
    List<String> allowedFluids = const [],
  }) => unwrapHost(
    generated.fluidHandler.registerFluidContainerItem(
      itemKey: itemKey,
      capacity: capacity,
      allowedFluids: allowedFluids,
    ),
    'Registering the fluid container item $itemKey',
  );
}

/// Fluid handlers and tanks of a [World].
extension WorldFluidHandlers on World {
  /// See [FluidHandlers.at].
  FluidHandler? fluidHandlerAt(BlockPos pos, {BlockDirection? side}) =>
      FluidHandlers.at(this, pos, side: side);

  /// See [FluidHandlers.registerTank].
  void registerTank(BlockPos pos, {required int tanks, required int capacity}) =>
      FluidHandlers.registerTank(this, pos, tanks: tanks, capacity: capacity);

  /// See [FluidHandlers.unregisterTank].
  List<FluidStack> unregisterTank(BlockPos pos) => FluidHandlers.unregisterTank(this, pos);
}

/// The fluid handler of an item stack.
extension ItemStackFluidHandler on ItemStack {
  /// See [FluidHandlers.ofItem].
  ItemFluidHandler? get fluidHandler => FluidHandlers.ofItem(this);
}

/// Conveniences for [FluidHandler].
extension FluidHandlerApi on FluidHandler {
  /// All tanks as `(tank, fluid)`, `fluid` being `null` for an empty tank.
  List<(int, FluidStack?)> get tanks => [
    for (var i = 0; i < tankCount(); i++) (i, getFluid(tank: i)),
  ];

  /// The total millibuckets of [fluidKey] over all tanks.
  int amountOf(String fluidKey) {
    var total = 0;
    for (var i = 0; i < tankCount(); i++) {
      final stack = getFluid(tank: i);
      if (stack != null && stack.fluid == fluidKey) total += stack.amount;
    }
    return total;
  }

  /// Moves up to [maxAmount] millibuckets (of [fluidKey] only, if given) from
  /// this handler into [target]. The transfer is simulated first, so only what
  /// fits is taken. Returns the amount that moved.
  int transferTo(FluidHandler target, int maxAmount, {String? fluidKey}) {
    final offer = fluidKey == null
        ? drain(maxAmount: maxAmount, simulate: true)
        : drainFluid(fluidKey: fluidKey, maxAmount: maxAmount, simulate: true);
    if (offer == null || offer.amount == 0) return 0;
    final fits = target.fill(stack: offer, simulate: true);
    if (fits == 0) return 0;
    final taken = fluidKey == null
        ? drain(maxAmount: fits, simulate: false)
        : drainFluid(fluidKey: fluidKey, maxAmount: fits, simulate: false);
    if (taken == null) return 0;
    return target.fill(stack: taken, simulate: false);
  }
}
