// `ContraptionType` (pure): the registry of contraption kinds. The Java base class reads a `Type`
// key from NBT and constructs the matching subclass; the actuator modules register their kinds
// here (`ContraptionTypes.register('create:piston', PistonContraption.new)`).
import 'contraption.dart';

/// Creates an empty contraption of a kind.
typedef ContraptionFactory = Contraption Function();

/// `ContraptionType`: one registered kind of contraption.
final class ContraptionType {
  /// The registry key, `create:piston`.
  final String id;
  final ContraptionFactory create;

  const ContraptionType(this.id, this.create);
}

/// `ContraptionType.REGISTRY`.
abstract final class ContraptionTypes {
  static final Map<String, ContraptionType> _types = {};

  /// The kind used for contraptions saved without a `Type` (and the default of the base class).
  static const String genericId = 'create:generic';

  static void register(String id, ContraptionFactory factory) =>
      _types[id] = ContraptionType(id, factory);

  static void registerAll(Map<String, ContraptionFactory> factories) {
    for (final e in factories.entries) {
      register(e.key, e.value);
    }
  }

  static ContraptionType? byId(String id) => _types[id];

  /// `ContraptionType.fromType`: an unknown (or empty) id gives the generic contraption.
  static Contraption fromType(String id) {
    final type = _types[id];
    return type != null ? type.create() : Contraption();
  }

  static void clear() => _types.clear();
}
