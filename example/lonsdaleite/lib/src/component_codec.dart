/// Turns the manifest's vanilla-format components into what the host's item
/// registry takes: network bytes per component. The encoding itself is
/// general and lives in `package:pumpkin_api` (`DataComponentCodec`, with the
/// byte format of every component derived from Pumpkin's readers); this file
/// only applies it to a [ItemDefinition] and keeps the log of what was left
/// out.
library;

import 'package:pumpkin_api/pumpkin_api_core.dart';

import 'registrar.dart';

/// An [ItemDefinition] ready for the host, and what was skipped.
final class EncodedItem {
  final ItemRegistration registration;

  /// Components the host cannot read (it has no `DataComponentImpl` reader
  /// for them), left out of the registration.
  final List<SkippedComponent> skipped;

  const EncodedItem(this.registration, this.skipped);
}

/// Encodes the components of [item] for `register-item`.
///
/// Throws a [ComponentEncodeException] naming the item if a component cannot
/// be encoded; components the host cannot read are skipped and reported in
/// [EncodedItem.skipped].
EncodedItem encodeItem(ItemDefinition item, {ComponentRegistries? registries}) {
  final EncodedComponents encoded;
  try {
    encoded = DataComponentCodec.encodeAll(
      item.components,
      registries: registries,
    );
  } on ComponentEncodeException catch (e) {
    throw ComponentEncodeException(e.component, '${item.id}: ${e.message}');
  }
  return EncodedItem(
    ItemRegistration(key: item.id, components: encoded.encoded),
    encoded.skipped,
  );
}

/// What was skipped, by component: component name to (item ids, reason).
/// Used for the log line at load and by the tests, so the list in the docs
/// (`docs/server-logic.md`, README) can be checked against it.
final class SkippedComponentsLog {
  final Map<String, List<String>> _items = {};
  final Map<String, String> _reasons = {};

  void add(String itemId, Iterable<SkippedComponent> skipped) {
    for (final s in skipped) {
      (_items[s.name] ??= []).add(itemId);
      _reasons[s.name] = s.reason;
    }
  }

  bool get isEmpty => _items.isEmpty;

  /// The skipped component names, sorted.
  List<String> get components => _items.keys.toList()..sort();

  /// The ids of the items that carried [component].
  List<String> itemsOf(String component) =>
      List.unmodifiable(_items[component] ?? const []);

  String reasonOf(String component) => _reasons[component] ?? '';

  /// One line per component.
  List<String> describe() => [
    for (final c in components)
      '$c on ${_items[c]!.length} item(s): ${_reasons[c]}',
  ];
}
