// Argument parsing helpers of the /create and /catnip commands (pure).
import '../../common/common.dart';

/// Thrown for an argument that cannot be parsed; the message is shown to the sender.
final class ArgumentParseException implements Exception {
  final String message;

  const ArgumentParseException(this.message);

  @override
  String toString() => message;
}

final RegExp _uuidPattern = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Whether [s] is a canonical UUID (`UuidArgument.uuid()`).
bool isUuid(String s) => _uuidPattern.hasMatch(s);

/// `UuidArgument.getUuid`: the lower case canonical form.
String parseUuid(String s) {
  if (!isUuid(s)) throw ArgumentParseException('Invalid UUID `$s`');
  return s.toLowerCase();
}

/// `train.id.toString().substring(0, 5)`.
String shortId(String uuid) => uuid.length <= 5 ? uuid : uuid.substring(0, 5);

/// How a command names an entity: the host cannot hand entity selectors to plugins, so an entity
/// is given by UUID or, for players, by name.
sealed class EntityRef {
  const EntityRef();

  factory EntityRef.parse(String s) {
    if (isUuid(s)) return EntityUuid(s.toLowerCase());
    if (s.isEmpty || s.contains(RegExp(r'\s')) || s.startsWith('@')) {
      throw ArgumentParseException(
        'Entity selectors are not supported here, give a player name or an entity UUID (got `$s`)',
      );
    }
    return PlayerName(s);
  }
}

final class EntityUuid extends EntityRef {
  final String uuid;

  const EntityUuid(this.uuid);
}

final class PlayerName extends EntityRef {
  final String name;

  const PlayerName(this.name);
}

/// Catnip's `ConfigSide`, in ordinal order (the wire format is the ordinal).
enum CatnipConfigSide {
  client,
  common,
  server;

  static CatnipConfigSide? byName(String s) {
    for (final v in values) {
      if (v.name == s.toLowerCase()) return v;
    }
    return null;
  }
}

/// Catnip's `ConfigId`: `create:server`.
final class CatnipConfigId {
  final String modId;
  final CatnipConfigSide side;

  const CatnipConfigId(this.modId, this.side);

  static final RegExp _modId = RegExp(r'^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_]*)*$');

  static bool isValidModId(String s) => _modId.hasMatch(s);

  /// Parses `modid:side`.
  factory CatnipConfigId.parse(String s) {
    final i = s.indexOf(':');
    if (i <= 0 || i == s.length - 1) throw ArgumentParseException('Invalid config `$s`, expected `<mod>:<client|common|server>`');
    final mod = s.substring(0, i);
    final side = CatnipConfigSide.byName(s.substring(i + 1));
    if (!isValidModId(mod)) throw ArgumentParseException('Invalid mod ID: $mod');
    if (side == null) throw ArgumentParseException('Unknown config side `${s.substring(i + 1)}`');
    return CatnipConfigId(mod, side);
  }

  @override
  bool operator ==(Object other) => other is CatnipConfigId && other.modId == modId && other.side == side;

  @override
  int get hashCode => Object.hash(modId, side);

  @override
  String toString() => '$modId:${side.name}';
}

/// Catnip's `ConfigPath`: components of `[a-zA-Z0-9_-]`, joined with periods for display.
final class CatnipConfigPath {
  final List<String> components;

  CatnipConfigPath(Iterable<String> components) : components = List.unmodifiable(components) {
    if (this.components.isEmpty) throw ArgumentParseException('Cannot create an empty ConfigPath');
    for (final c in this.components) {
      if (c.isEmpty || !_component.hasMatch(c)) throw ArgumentParseException('Invalid component: $c');
    }
  }

  static final RegExp _component = RegExp(r'^[a-zA-Z0-9_-]+$');

  /// Parses `kinetics.encasedFan.fanPushDistance`.
  factory CatnipConfigPath.parse(String s) => CatnipConfigPath(s.split('.'));

  /// The dotted path inside the toml.
  String get dotted => components.join('.');

  @override
  bool operator ==(Object other) => other is CatnipConfigPath && other.dotted == dotted;

  @override
  int get hashCode => dotted.hashCode;

  @override
  String toString() => dotted;
}

/// A `WrappedConfigValue` (the value of a `catnip:set_config_values` change).
sealed class WrappedConfigValue {
  const WrappedConfigValue();

  /// The variant names of `WrappedConfigValue.Type`, in ordinal order.
  static const List<String> types = ['BOOL', 'INT', 'FLOAT', 'DOUBLE', 'STRING', 'ENUM'];
}

final class WrappedBool extends WrappedConfigValue {
  final bool value;
  const WrappedBool(this.value);
}

final class WrappedInt extends WrappedConfigValue {
  final int value;
  const WrappedInt(this.value);
}

final class WrappedFloat extends WrappedConfigValue {
  final double value;
  const WrappedFloat(this.value);
}

final class WrappedDouble extends WrappedConfigValue {
  final double value;
  const WrappedDouble(this.value);
}

final class WrappedString extends WrappedConfigValue {
  final String value;
  const WrappedString(this.value);
}

final class WrappedEnum extends WrappedConfigValue {
  final int ordinal;
  const WrappedEnum(this.ordinal);
}

/// Builds the wrapped value of a payload variant (`PayloadVariant(variant, value)`).
WrappedConfigValue? wrapPayloadVariant(String variant, Object? value) => switch (variant) {
  'BOOL' when value is bool => WrappedBool(value),
  'INT' when value is int => WrappedInt(value),
  'FLOAT' when value is num => WrappedFloat(value.toDouble()),
  'DOUBLE' when value is num => WrappedDouble(value.toDouble()),
  'STRING' when value is String => WrappedString(value),
  'ENUM' when value is int => WrappedEnum(value),
  _ => null,
};

/// `ConfigHelper.parseConfigValue`: the text typed in `/catnip config <config> <path> set <value>`
/// as the type of the existing value; `null` when it does not parse.
Object? parseConfigText(Object reference, String text, {List<String>? enumValues}) {
  switch (reference) {
    case bool():
      return text == 'true' ? true : (text == 'false' ? false : null);
    case int():
      return int.tryParse(text);
    case double():
      return double.tryParse(text);
    case String():
      if (enumValues != null) {
        for (final v in enumValues) {
          if (v == text) return v;
        }
        return null;
      }
      return text;
  }
  return null;
}

/// `PassengerCommand`'s guard: a rider cannot sit on itself.
bool isSameEntity(String a, String b) => a == b;

/// `BlockPos.toShortString()` style `x, y, z`.
String shortPos(Pos p) => '${p.$1}, ${p.$2}, ${p.$3}';
