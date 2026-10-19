// `VirtualFluid` (pure): a fluid without a block or bucket (potion, tea). The
// host registers it as a registry / tank / bucket fluid when the [FluidSpec] has
// no placement.
import 'package:pumpkin_api/pumpkin_api.dart';

/// A virtual fluid: a still key, its flowing key and the tags it joins.
final class VirtualFluid {
  final String still;
  final String flowing;
  final List<String> tags;

  const VirtualFluid({
    required this.still,
    required this.flowing,
    this.tags = const [],
  });

  /// The registration of the flowing variant (registered first).
  FluidSpec flowingSpec() => FluidSpec(key: flowing);

  /// The registration of the still fluid, which names the flowing one.
  FluidSpec stillSpec() =>
      FluidSpec(key: still, flowingVariant: flowing, tags: tags);
}
