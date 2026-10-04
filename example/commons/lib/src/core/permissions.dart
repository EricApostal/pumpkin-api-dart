/// Who has a permission when nobody granted it.
enum PermDefault { everyone, op, nobody }

/// A permission node of the plugin. Nodes are written in full
/// (`commons:...`), registered at load time, and listed in one place per
/// module (`<module>/permissions.dart`).
final class PermNode {
  final String node;
  final String description;
  final PermDefault defaultFor;

  const PermNode(
    this.node,
    this.description, [
    this.defaultFor = PermDefault.everyone,
  ]);

  @override
  String toString() => node;
}
