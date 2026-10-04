/// Orders [items] so that each comes after the items it depends on.
///
/// Generic (instead of taking `Module`) so it stays free of server bindings and
/// can be unit tested. Throws a [StateError] for unknown dependencies, cycles
/// and duplicate names. Items without dependencies keep their order.
List<T> loadOrder<T>(
  List<T> items, {
  required String Function(T item) name,
  required List<String> Function(T item) dependsOn,
}) {
  final byName = {for (final item in items) name(item): item};
  if (byName.length != items.length) {
    throw StateError('Two modules have the same name.');
  }
  final ordered = <T>[];
  final done = <String>{};
  final visiting = <String>{};

  void visit(T item) {
    final itemName = name(item);
    if (done.contains(itemName)) return;
    if (!visiting.add(itemName)) {
      throw StateError('Modules depend on each other in a cycle at $itemName.');
    }
    for (final dependency in dependsOn(item)) {
      final other = byName[dependency];
      if (other == null) {
        throw StateError('$itemName depends on unknown module $dependency.');
      }
      visit(other);
    }
    visiting.remove(itemName);
    done.add(itemName);
    ordered.add(item);
  }

  items.forEach(visit);
  return ordered;
}
