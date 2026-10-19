// `OpenPipeEffectHandler` (pure): custom behaviour for fluids spilling out of an open pipe
// (potion effects, milk, water extinguishing fire). The host applies the registered handler; the
// registry is the API other modules fill in.
import '../../common/bounds.dart';
import '../../fluids/fluid_stack.dart';

/// `OpenPipeEffectHandler`.
abstract interface class OpenPipeEffectHandler {
  /// `apply(level, area, fluid)`: [area] is the affected box, [fluid] the spilled fluid.
  void apply(Aabb area, FStack fluid);
}

/// `OpenPipeEffectHandler.REGISTRY`.
abstract final class OpenPipeEffects {
  /// The handler per fluid key.
  static final Map<String, OpenPipeEffectHandler> registry = {};

  /// `REGISTRY.register(fluid, handler)`.
  static void register(String fluidKey, OpenPipeEffectHandler handler) =>
      registry[fluidKey] = handler;

  /// `REGISTRY.get(fluid)`.
  static OpenPipeEffectHandler? of(String fluidKey) => registry[fluidKey];

  /// Removes every registration (tests and reloads).
  static void clear() => registry.clear();
}
