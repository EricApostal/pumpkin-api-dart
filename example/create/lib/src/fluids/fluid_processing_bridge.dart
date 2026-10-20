// The two fluid models of the plugin, and the conversion between them.
//
// The fluids module moves `FStack`s around (`fluid_stack.dart`): a fluid, an amount and the
// plugin's fluid `data` — a potion fluid carries its `PotionFluidData` there, since the host's
// `FluidStack` has no component codec (`fluid-registry.wit`). The processing machines hold
// `PFluid`s (`processing/common/stack.dart`): a fluid, an amount and `components`, which is what
// a recipe's `neoforge:components` fluid ingredient is matched against
// (`FluidIngredient.testFluid`). Both carry the same information about a potion, so the
// conversion writes it on both sides: [pFluidOf] as the codec (JSON) components
// (`PotionFluidData.componentEntries`), [fStackOf] as the fluid data.
import '../processing/common/stack.dart';
import 'fluid_stack.dart';
import 'potion_data.dart';

/// The processing `PFluid` of [stack], with the components of a potion fluid.
PFluid pFluidOf(FStack stack) {
  if (stack.isEmpty) return PFluid.empty;
  final data = stack.fluid == FluidKeys.potion
      ? PotionFluidData.decode(stack.data)
      : null;
  return PFluid(
    stack.fluid,
    stack.amount,
    comps: data?.componentEntries() ?? const [],
  );
}

/// The module's `FStack` of [fluid], with the fluid data of a potion's components.
FStack fStackOf(PFluid fluid) {
  if (fluid.isEmpty) return FStack.empty;
  final data = PotionFluidData.fromComponentEntries(fluid.comps);
  return FStack(fluid.key, fluid.amount, data?.encode());
}