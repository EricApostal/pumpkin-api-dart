// `dev.ryanhcode.sable.api.physics.PhysicsPipelineProvider`: the service that
// hands each level a physics pipeline.
//
// Java discovers providers through `ServiceLoader` and picks the one with the
// highest `@LoadPriority` (`PhysicsPipelineProvider.java:27-41`). A Dart plugin
// cannot use `ServiceLoader`, so providers register themselves here; the
// selection rule is the same, and the default (`1000`) is the Java default.
//
// `StaticPhysicsPipelineProvider` (`physics/impl/none`) registers with priority
// `900`, so it is the fallback: it is chosen only when no real solver is
// registered. That is the Java arrangement — the rapier provider carries the
// default `1000`.
//
// Pure: no host imports.
import '../host/sub_level_host.dart';
import 'physics_pipeline.dart';

/// A provider of physics pipelines for levels
/// (`dev.ryanhcode.sable.api.physics.PhysicsPipelineProvider`).
abstract interface class PhysicsPipelineProvider {
  /// `@LoadPriority.value()`: the highest-priority provider available is used.
  /// The Java default is `1000`.
  int get loadPriority => 1000;

  /// `createPipeline(level)`: a new pipeline for [level].
  PhysicsPipeline createPipeline(SableLevel level);
}

/// The registered providers, and the selection rule.
///
/// This replaces the Java `PhysicsPipelineProvider.INSTANCE` singleton: a
/// `ServiceLoader` scans the classpath, which a Dart plugin cannot do, so each
/// provider registers at load time instead.
abstract final class PhysicsPipelineProviders {
  static final List<PhysicsPipelineProvider> _registered = [];

  /// Registers [provider]. Registering the same instance twice is a no-op.
  static void register(PhysicsPipelineProvider provider) {
    if (!_registered.contains(provider)) _registered.add(provider);
  }

  /// Unregisters [provider].
  static void unregister(PhysicsPipelineProvider provider) => _registered.remove(provider);

  /// Forgets every provider (tests, shutdown).
  static void clear() => _registered.clear();

  /// The registered providers, in registration order.
  static List<PhysicsPipelineProvider> get registered => List.unmodifiable(_registered);

  /// The provider with the highest [PhysicsPipelineProvider.loadPriority].
  ///
  /// `PhysicsPipelineProvider.java:31-39` compares with
  /// `Comparator.comparingInt(...)` inside `Stream.max`, which keeps the first
  /// of equal priorities; registration order breaks a tie here too.
  ///
  /// Throws a [StateError] when nothing is registered, like the Java
  /// `orElseThrow`.
  static PhysicsPipelineProvider resolve() {
    PhysicsPipelineProvider? best;
    for (final provider in _registered) {
      if (best == null || provider.loadPriority > best.loadPriority) {
        best = provider;
      }
    }
    if (best == null) {
      throw StateError(
        'Failed to find any physics pipeline providers: register one, or '
        'register StaticPhysicsPipelineProvider for the no-op fallback',
      );
    }
    return best;
  }

  /// `PhysicsPipelineProvider.INSTANCE.createPipeline(level)`.
  static PhysicsPipeline createPipeline(SableLevel level) => resolve().createPipeline(level);
}
