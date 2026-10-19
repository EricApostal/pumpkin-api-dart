// [TagLookup] over the host's tag queries (`Tags`).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../recipe/ingredient.dart';

/// Tag membership from the host, cached per (item, tag): tags only change on a datapack
/// reload, which clears the cache ([clear]).
final class HostTagLookup implements TagLookup {
  final Map<(String, String), bool> _items = {};
  final Map<(String, String), bool> _blocks = {};
  final Map<(String, String), bool> _fluids = {};

  HostTagLookup();

  /// Forgets the cache (datapack reload / tags updated).
  void clear() {
    _items.clear();
    _blocks.clear();
    _fluids.clear();
  }

  @override
  bool itemHasTag(String itemKey, String tag) => _items.putIfAbsent((itemKey, tag), () => Tags.item(itemKey, tag));

  @override
  bool blockHasTag(String blockKey, String tag) =>
      _blocks.putIfAbsent((blockKey, tag), () => Tags.block(blockKey, tag));

  @override
  bool fluidHasTag(String fluidKey, String tag) =>
      _fluids.putIfAbsent((fluidKey, tag), () => Tags.fluid(fluidKey, tag));
}
