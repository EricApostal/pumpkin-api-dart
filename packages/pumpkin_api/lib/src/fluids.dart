import 'bindings.g.dart' as generated;
import 'bindings.g.dart';
import 'host_result.dart';

/// A fluid to register (`fluid-registry.wit`), with the vanilla water-like
/// defaults for everything not given.
///
/// ```dart
/// final id = FluidRegistries.register(
///   const FluidSpec(
///     key: 'my_plugin:honey',
///     placement: FluidPlacement(block: 'my_plugin:honey_block', flowing: false),
///     bucketItem: 'my_plugin:honey_bucket',
///     viscosity: 4000,
///   ),
/// );
/// ```
final class FluidSpec {
  /// `namespace:path`, lowercase; the `minecraft` namespace is reserved.
  final String key;

  /// The plugin block that holds the fluid, `null` for a virtual fluid (only in
  /// registries, tanks and buckets).
  final FluidPlacement? placement;

  /// Key of the registered fluid that is the flowing variant of this one.
  final String? flowingVariant;

  /// Key of the registered plugin item that is the bucket of this fluid.
  final String? bucketItem;

  /// Ticks between flow steps, at least 1.
  final int tickRate;

  /// How much the amount drops per block of flow, 1 to 8.
  final int levelDecreasePerBlock;

  /// How far from a hole the fluid looks for a slope, at most 8.
  final int slopeFindDistance;

  final bool canConvertToSource;

  /// Emitted light, 0 to 15.
  final int luminance;

  /// Water is 1000, lava 3000.
  final int density;

  /// In kelvin: water 300, lava 1300.
  final int temperature;

  /// Water is 1000, lava 6000.
  final int viscosity;

  /// Fluid tags the fluid joins, `namespace:path`.
  final List<String> tags;

  const FluidSpec({
    required this.key,
    this.placement,
    this.flowingVariant,
    this.bucketItem,
    this.tickRate = 5,
    this.levelDecreasePerBlock = 1,
    this.slopeFindDistance = 4,
    this.canConvertToSource = false,
    this.luminance = 0,
    this.density = 1000,
    this.temperature = 300,
    this.viscosity = 1000,
    this.tags = const [],
  });

  generated.FluidDefinition toWire() => generated.FluidDefinition(
    key: key,
    placement: placement,
    flowingVariant: flowingVariant,
    bucketItem: bucketItem,
    tickRate: tickRate,
    levelDecreasePerBlock: levelDecreasePerBlock,
    slopeFindDistance: slopeFindDistance,
    canConvertToSource: canConvertToSource,
    luminance: luminance,
    density: density,
    temperature: temperature,
    viscosity: viscosity,
    tags: tags,
  );
}

/// The host's fluid registry. Registration needs
/// [Permissions.registryFluids] and only works while the server loads.
/// Vanilla fluids have the ids `0..vanillaCount`, custom ones follow in
/// registration order. A still fluid and its flowing variant are two entries.
abstract final class FluidRegistries {
  /// Registers [fluid] and returns its id. Register the plugin block and
  /// bucket item first. Throws a [HostException] on failure.
  static int register(FluidSpec fluid) => unwrapHost(
    generated.fluidRegistry.registerFluid(definition: fluid.toWire()),
    'Registering the fluid ${fluid.key}',
  );

  /// Registers the fluid tag [tag] (`mymod:lava_like`) with [entries], fluid keys.
  /// Throws a [HostException] on failure.
  static void registerTag(String tag, List<String> entries) => unwrapHost(
    generated.fluidRegistry.registerFluidTag(tag: tag, entries: entries),
    'Registering the fluid tag $tag',
  );

  /// The id of the fluid [key], vanilla or custom.
  static int? idOf(String key) => generated.fluidRegistry.getFluidId(key: key);

  /// The full key of the fluid [id].
  static String? keyOf(int id) => generated.fluidRegistry.getFluidKey(id: id);

  /// The number of vanilla fluids, which is also the id of the first custom one.
  static int get vanillaCount => generated.fluidRegistry.getVanillaFluidCount();

  /// All custom fluids in id order.
  static List<FluidEntry> get registered => generated.fluidRegistry.getRegisteredFluids();

  /// The fluid a full bucket item holds (1000 mB), or `null`.
  static FluidStack? fromBucket(String itemKey) =>
      generated.fluidRegistry.fluidFromBucket(itemKey: itemKey);

  /// The key of the bucket item of [fluidKey], or `null`.
  static String? bucketFor(String fluidKey) =>
      generated.fluidRegistry.bucketForFluid(fluidKey: fluidKey);
}

/// Reading and changing fluids in a [World].
extension WorldFluids on World {
  /// The fluid at [pos], `null` if the chunk is not loaded.
  FluidState? fluidAt(BlockPos pos) => getFluidState(pos: pos);

  /// Places the source of [fluidKey] at [pos]. Returns whether it was placed.
  bool placeFluid(BlockPos pos, String fluidKey) =>
      tryPlaceFluid(pos: pos, fluidKey: fluidKey);

  /// Takes the fluid at [pos] out of the world (as a bucket does), or `null`
  /// if there is none to take.
  FluidStack? pickupFluid(BlockPos pos) => tryPickupFluid(pos: pos);

  /// Schedules a fluid tick at [pos]. The server has no flow physics for
  /// registered fluids: move them from your tick handler.
  void scheduleFluidFlow(BlockPos pos, {int delayTicks = 5}) =>
      scheduleFluidTick(pos: pos, delay: delayTicks.clamp(0, 255));
}
