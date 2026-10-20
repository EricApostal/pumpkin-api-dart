// `dev.ryanhcode.sable.command.argument`: the sub-level selector syntax of the
// `/sable` commands (`@e`, `@n[limit=2,sort=nearest]`, a UUID).
//
// The Java mod plugs a Brigadier `ArgumentType` into the vanilla dispatcher;
// the Dart plugin's command builder only hands handlers the raw text, so the
// same grammar is parsed here, and the resulting [SubLevelTarget] resolves to
// sub-levels when the command runs (the container may change in between).
//
// Pure: no host imports.
import 'dart:math' as math;

import '../../math/bounding_box.dart';
import '../../math/vector.dart';
import '../../model/server_sub_level.dart';
import '../../model/sub_level_container.dart';

/// `argument.sable.*`: the parse errors the Java argument type throws.
enum SubLevelSelectorError {
  singleSubLevelRequired('argument.sable.single_sub_level_required'),
  invalidSelector('argument.sable.invalid_selector'),
  unexpectedEndOfInput('argument.sable.unexpected_end_of_input'),
  invalidUuid('argument.sable.invalid_uuid'),
  cannotFindSubLevel('argument.sable.cannot_find_sub_level'),
  unknownProperty('argument.sable.sub_level.unknown_property'),
  expectedEndOfModifier('argument.sable.sub_level.expected_end_of_modifier'),
  expectedPositiveInteger('argument.sable.sub_level.expected_positive_integer'),
  expectedPositiveDecimal('argument.sable.sub_level.expected_positive_decimal'),
  expectedSorting('argument.sable.sub_level.expected_sorting'),
  expectedPositiveRange('argument.sable.sub_level.expected_positive_range');

  const SubLevelSelectorError(this.translationKey);

  final String translationKey;

  /// The English text the port reports (the Java client translates the key).
  String get message => switch (this) {
    SubLevelSelectorError.singleSubLevelRequired => 'Only one sub-level is allowed here.',
    SubLevelSelectorError.invalidSelector => 'Invalid sub-level selector.',
    SubLevelSelectorError.unexpectedEndOfInput => 'Unexpected end of the sub-level selector.',
    SubLevelSelectorError.invalidUuid => 'That is not a valid sub-level UUID.',
    SubLevelSelectorError.cannotFindSubLevel => 'Could not find that sub-level.',
    SubLevelSelectorError.unknownProperty => 'Unknown sub-level selector property.',
    SubLevelSelectorError.expectedEndOfModifier => 'Expected the end of the selector modifier.',
    SubLevelSelectorError.expectedPositiveInteger => 'Expected a positive whole number.',
    SubLevelSelectorError.expectedPositiveDecimal => 'Expected a positive decimal number.',
    SubLevelSelectorError.expectedSorting => 'Expected "nearest" or "furthest".',
    SubLevelSelectorError.expectedPositiveRange => 'Expected a positive range.',
  };
}

/// A selector parse failure.
final class SubLevelSelectorException implements Exception {
  final SubLevelSelectorError error;

  const SubLevelSelectorException(this.error);

  @override
  String toString() => error.message;
}

/// `SubLevelSelectorType`: the `@`-prefixed selectors.
enum SubLevelSelectorType {
  all('e', 'All sub-levels', false),
  nearest('n', 'The nearest sub-level', true),
  random('r', 'A random sub-level', true),
  viewed('v', 'The sub-level you are looking at', true),
  latest('l', 'The most recently created sub-level', true),
  tracking('t', 'The sub-level you are standing on', true),
  inside('i', 'The sub-level you are inside', true);

  const SubLevelSelectorType(this.selector, this.tooltip, this.single);

  final String selector;
  final String tooltip;
  final bool single;

  /// `of(char)`, or `null`.
  static SubLevelSelectorType? of(String character) {
    for (final type in values) {
      if (type.selector == character) return type;
    }
    return null;
  }
}

/// `SubLevelSelectorModifierType.FilterPriority`: the order modifiers apply in.
enum SelectorFilterPriority { position, filter, sorting, sortingSelection }

/// `SubLevelSelectorModifierType.Modifier`: one `[key=value]` entry.
abstract interface class SelectorModifier {
  /// The most sub-levels this modifier can ever produce.
  int get maxResults;

  /// The priority the modifier runs at.
  SelectorFilterPriority get priority;

  /// Filters, sorts or limits [selected].
  List<ServerSubLevel> apply(List<ServerSubLevel> selected, Vector3d sourcePos);
}

/// A `min..max` double range (`MinMaxBounds.Doubles`).
final class DoubleRange {
  final double? min;
  final double? max;

  const DoubleRange(this.min, this.max);

  /// `MinMaxBounds.Doubles.exactly`.
  const DoubleRange.exactly(double value) : min = value, max = value;

  /// `matches(value)`.
  bool matches(double value) =>
      (min == null || value >= min!) && (max == null || value <= max!);

  /// `matchesSqr(value)`: the range is compared against the squared value.
  bool matchesSqr(double value) {
    if (min != null && value < min! * min!) return false;
    if (max != null && value > max! * max!) return false;
    return true;
  }

  /// `MinMaxBounds.Doubles.fromReader`.
  static DoubleRange parse(String text) {
    final index = text.indexOf('..');
    if (index < 0) {
      final value = double.tryParse(text);
      if (value == null) throw const SubLevelSelectorException(SubLevelSelectorError.expectedPositiveRange);
      return DoubleRange.exactly(value);
    }

    final minText = text.substring(0, index);
    final maxText = text.substring(index + 2);
    final min = minText.isEmpty ? null : double.tryParse(minText);
    final max = maxText.isEmpty ? null : double.tryParse(maxText);
    if ((minText.isNotEmpty && min == null) || (maxText.isNotEmpty && max == null)) {
      throw const SubLevelSelectorException(SubLevelSelectorError.expectedPositiveRange);
    }
    return DoubleRange(min, max);
  }
}

/// `SubLevelTarget`: something a selector resolves to.
abstract interface class SubLevelTarget {
  /// The sub-levels this target selects in [source].
  List<ServerSubLevel> getSubLevels(SubLevelTargetContext source);
}

/// What a target needs to resolve: the container, the source position and the
/// two host-provided lookups.
final class SubLevelTargetContext {
  final SubLevelContainer container;
  final Vector3d sourcePosition;

  /// The sub-level the source is standing on, or `null`.
  final ServerSubLevel? trackingSubLevel;

  /// The sub-level the source is looking at, or `null`.
  final ServerSubLevel? viewedSubLevel;

  /// The source inside a sub-level, or `null`.
  final ServerSubLevel? containingSubLevel;

  /// A random source for `@r`.
  final math.Random random;

  const SubLevelTargetContext({
    required this.container,
    required this.sourcePosition,
    required this.random,
    this.trackingSubLevel,
    this.viewedSubLevel,
    this.containingSubLevel,
  });
}

/// `SubLevelTargetNone`: selects nothing (`static_world`).
final class SubLevelTargetNone implements SubLevelTarget {
  const SubLevelTargetNone();

  @override
  List<ServerSubLevel> getSubLevels(SubLevelTargetContext source) => const [];
}

/// `SubLevelTargetUUID`: selects one sub-level by UUID.
final class SubLevelTargetUuid implements SubLevelTarget {
  final String target;

  const SubLevelTargetUuid(this.target);

  @override
  List<ServerSubLevel> getSubLevels(SubLevelTargetContext source) {
    final subLevel = source.container.getSubLevelById(target);
    if (subLevel is! ServerSubLevel) {
      throw const SubLevelSelectorException(SubLevelSelectorError.cannotFindSubLevel);
    }
    return [subLevel];
  }
}

/// `SubLevelTargetSelector`: a `@`-selector with modifiers.
final class SubLevelTargetSelector implements SubLevelTarget {
  final SubLevelSelectorType type;
  final List<SelectorModifier> modifiers;

  const SubLevelTargetSelector(this.type, this.modifiers);

  @override
  List<ServerSubLevel> getSubLevels(SubLevelTargetContext source) {
    final container = source.container;
    final bodies = [for (final subLevel in container.getAllSubLevels()) subLevel as ServerSubLevel];

    if (bodies.isEmpty) return const [];

    final collected = switch (type) {
      SubLevelSelectorType.all => [...bodies],
      SubLevelSelectorType.nearest => _nearest(bodies, source.sourcePosition),
      SubLevelSelectorType.random => [bodies[source.random.nextInt(bodies.length)]],
      SubLevelSelectorType.inside =>
        source.containingSubLevel == null ? <ServerSubLevel>[] : [source.containingSubLevel!],
      SubLevelSelectorType.tracking =>
        source.trackingSubLevel == null ? <ServerSubLevel>[] : [source.trackingSubLevel!],
      SubLevelSelectorType.viewed =>
        source.viewedSubLevel == null ? <ServerSubLevel>[] : [source.viewedSubLevel!],
      SubLevelSelectorType.latest => [bodies.last],
    };

    var modified = collected;
    final sorted = [...modifiers]
      ..sort((a, b) => a.priority.index.compareTo(b.priority.index));
    for (final modifier in sorted) {
      modified = modifier.apply(modified, source.sourcePosition);
    }
    return modified;
  }

  static List<ServerSubLevel> _nearest(List<ServerSubLevel> bodies, Vector3d sourcePosition) {
    var closest = double.maxFinite;
    ServerSubLevel? closestSubLevel;
    for (final body in bodies) {
      final distance = body.logicalPose.position().distance(sourcePosition);
      if (distance < closest) {
        closest = distance;
        closestSubLevel = body;
      }
    }
    return closestSubLevel == null ? const [] : [closestSubLevel];
  }
}

/// A filter comparing one numeric property against a range.
final class RangeSelectorModifier implements SelectorModifier {
  final DoubleRange range;
  final double Function(ServerSubLevel subLevel, Vector3d sourcePos) getter;
  final bool squared;

  const RangeSelectorModifier(this.range, this.getter, {this.squared = false});

  @override
  int get maxResults => 1 << 31;

  @override
  SelectorFilterPriority get priority => SelectorFilterPriority.filter;

  @override
  List<ServerSubLevel> apply(List<ServerSubLevel> selected, Vector3d sourcePos) => [
    for (final subLevel in selected)
      if (squared
          ? range.matchesSqr(getter(subLevel, sourcePos))
          : range.matches(getter(subLevel, sourcePos)))
        subLevel,
  ];
}

/// A filter comparing one numeric property against a single value.
final class ValueSelectorModifier implements SelectorModifier {
  final double value;
  final bool Function(ServerSubLevel subLevel, Vector3d sourcePos, double test) predicate;

  const ValueSelectorModifier(this.value, this.predicate);

  @override
  int get maxResults => 1 << 31;

  @override
  SelectorFilterPriority get priority => SelectorFilterPriority.filter;

  @override
  List<ServerSubLevel> apply(List<ServerSubLevel> selected, Vector3d sourcePos) => [
    for (final subLevel in selected)
      if (predicate(subLevel, sourcePos, value)) subLevel,
  ];
}

/// `SubLevelNameFilter`.
final class NameSelectorModifier implements SelectorModifier {
  final String name;

  const NameSelectorModifier(this.name);

  @override
  int get maxResults => 1 << 31;

  @override
  SelectorFilterPriority get priority => SelectorFilterPriority.filter;

  @override
  List<ServerSubLevel> apply(List<ServerSubLevel> selected, Vector3d sourcePos) => [
    for (final subLevel in selected)
      if (subLevel.name == name) subLevel,
  ];
}

/// `SubLevelSortModifier`.
final class SortSelectorModifier implements SelectorModifier {
  /// `nearest` or `furthest`.
  final String sorting;

  const SortSelectorModifier(this.sorting);

  @override
  int get maxResults => 1 << 31;

  @override
  SelectorFilterPriority get priority => SelectorFilterPriority.sorting;

  @override
  List<ServerSubLevel> apply(List<ServerSubLevel> selected, Vector3d sourcePos) {
    final distances = {
      for (final subLevel in selected)
        subLevel: subLevel.logicalPose.position().distanceSquared(sourcePos),
    };
    selected.sort((a, b) {
      final da = distances[a]!, db = distances[b]!;
      return sorting == 'furthest' ? db.compareTo(da) : da.compareTo(db);
    });
    return selected;
  }
}

/// `SubLevelLimitFilter`.
final class LimitSelectorModifier implements SelectorModifier {
  final int limit;

  const LimitSelectorModifier(this.limit);

  @override
  int get maxResults => limit;

  @override
  SelectorFilterPriority get priority => SelectorFilterPriority.sortingSelection;

  @override
  List<ServerSubLevel> apply(List<ServerSubLevel> selected, Vector3d sourcePos) =>
      selected.length > limit ? selected.sublist(0, limit) : selected;
}

/// The modifier registry (`SubLevelSelectorModifierType.registerModifiers`).
abstract final class SubLevelSelectorModifiers {
  static final Map<String, SelectorModifier Function(String value)> _parsers = {};

  /// Registers [name]; throws when it is already registered.
  static void register(String name, SelectorModifier Function(String value) parser) {
    if (_parsers.containsKey(name)) {
      throw ArgumentError('Modifier type $name already registered');
    }
    _parsers[name] = parser;
  }

  /// The parser of [name], or `null`.
  static SelectorModifier Function(String value)? parserOf(String name) => _parsers[name];

  /// All registered names, for tab completion.
  static Iterable<String> get names => _parsers.keys;

  /// Forgets every registered modifier.
  static void clearRegistry() => _parsers.clear();

  /// Registers the default modifiers.
  static void registerModifiers() {
    if (_parsers.isNotEmpty) return;

    void range(String name, bool positive, double Function(ServerSubLevel, Vector3d) getter, {bool squared = false}) {
      register(name, (value) {
        final parsed = DoubleRange.parse(value);
        if (positive && ((parsed.min != null && parsed.min! < 0) || (parsed.max != null && parsed.max! < 0))) {
          throw const SubLevelSelectorException(SubLevelSelectorError.expectedPositiveRange);
        }
        return RangeSelectorModifier(parsed, getter, squared: squared);
      });
    }

    void delta(String name, double Function(ServerSubLevel, Vector3d) getter) {
      register(name, (value) {
        final parsed = double.tryParse(value);
        if (parsed == null) {
          throw const SubLevelSelectorException(SubLevelSelectorError.expectedPositiveDecimal);
        }
        return ValueSelectorModifier(parsed, (subLevel, sourcePos, test) {
          final d = getter(subLevel, sourcePos);
          return test < 0 ? (d < 0 && d > test) : (d > 0 && d < test);
        });
      });
    }

    range('distance', true, (s, p) => s.logicalPose.position().distanceSquared(p), squared: true);
    range('x', false, (s, p) => s.logicalPose.position().x);
    range('y', false, (s, p) => s.logicalPose.position().y);
    range('z', false, (s, p) => s.logicalPose.position().z);

    delta('dx', (s, p) => s.logicalPose.position().x - p.x);
    delta('dy', (s, p) => s.logicalPose.position().y - p.y);
    delta('dz', (s, p) => s.logicalPose.position().z - p.z);

    range('vx', false, (s, p) => s.latestLinearVelocity.x);
    range('vy', false, (s, p) => s.latestLinearVelocity.y);
    range('vz', false, (s, p) => s.latestLinearVelocity.z);
    range('speed', true, (s, p) => s.latestLinearVelocity.lengthSquared, squared: true);

    range('mass', true, (s, p) => s.getMassTracker().getInverseMass() == 0 ? 0 : 1 / s.getMassTracker().getInverseMass());
    range('volume', true, (s, p) => s.getPlot().getBoundingBox().volume().toDouble());
    range('width', true, (s, p) => s.getPlot().getBoundingBox().width().toDouble());
    range('height', true, (s, p) => s.getPlot().getBoundingBox().height().toDouble());
    range('length', true, (s, p) => s.getPlot().getBoundingBox().length().toDouble());

    register('name', (value) => NameSelectorModifier(value));

    register('sort', (value) {
      if (value != 'nearest' && value != 'furthest') {
        throw const SubLevelSelectorException(SubLevelSelectorError.expectedSorting);
      }
      return SortSelectorModifier(value);
    });

    register('limit', (value) {
      final limit = int.tryParse(value);
      if (limit == null || limit < 0) {
        throw const SubLevelSelectorException(SubLevelSelectorError.expectedPositiveInteger);
      }
      return LimitSelectorModifier(limit);
    });
  }
}

/// `SubLevelArgumentType`: parses a selector and resolves it.
abstract final class SubLevelArgumentType {
  /// `static_world`: selects nothing.
  static const String staticWorld = 'static_world';

  /// `singleSubLevel()`: one sub-level, no static world.
  static const SubLevelArgumentParser singleSubLevel = SubLevelArgumentParser(allowStaticLevel: false, allowMultiple: false);

  /// `subLevels()`: any number, no static world.
  static const SubLevelArgumentParser subLevels = SubLevelArgumentParser(allowStaticLevel: false, allowMultiple: true);

  /// `subLevelsOrLevel()`: any number, `static_world` allowed.
  static const SubLevelArgumentParser subLevelsOrLevel = SubLevelArgumentParser(allowStaticLevel: true, allowMultiple: true);
}

/// One configured selector parser.
final class SubLevelArgumentParser {
  final bool allowStaticLevel;
  final bool allowMultiple;

  const SubLevelArgumentParser({required this.allowStaticLevel, required this.allowMultiple});

  /// `parse(reader)`.
  SubLevelTarget parse(String text) {
    SubLevelSelectorModifiers.registerModifiers();
    final reader = _SelectorReader(text);

    if (allowStaticLevel && reader.peekWord() == SubLevelArgumentType.staticWorld) {
      reader.skip(SubLevelArgumentType.staticWorld.length);
      return const SubLevelTargetNone();
    }

    if (!reader.canRead) {
      throw const SubLevelSelectorException(SubLevelSelectorError.invalidSelector);
    }

    if (reader.peek == '@') {
      reader.skip(1);
      return _parseSelector(reader);
    }
    return _parseUuid(reader);
  }

  SubLevelTarget _parseSelector(_SelectorReader reader) {
    if (!reader.canRead) {
      throw const SubLevelSelectorException(SubLevelSelectorError.invalidSelector);
    }

    final selectorType = SubLevelSelectorType.of(reader.read());
    if (selectorType == null) {
      throw const SubLevelSelectorException(SubLevelSelectorError.invalidSelector);
    }

    var maximumResults = 1 << 31;
    if (selectorType.single) maximumResults = 1;

    final modifiers = _parseSelectorArguments(reader);
    for (final modifier in modifiers) {
      maximumResults = math.min(maximumResults, modifier.maxResults);
    }

    if (maximumResults > 1 && !allowMultiple) {
      throw const SubLevelSelectorException(SubLevelSelectorError.singleSubLevelRequired);
    }

    return SubLevelTargetSelector(selectorType, modifiers);
  }

  List<SelectorModifier> _parseSelectorArguments(_SelectorReader reader) {
    final modifiers = <SelectorModifier>[];
    if (!reader.canRead || reader.peek != '[') return modifiers;

    reader.skip(1);
    while (reader.canRead && reader.peek != ']') {
      if (reader.peek == ',') reader.skip(1);

      final propertyName = reader.readUntil('=');
      if (!reader.canRead || reader.peek != '=') {
        throw const SubLevelSelectorException(SubLevelSelectorError.unexpectedEndOfInput);
      }
      reader.skip(1);

      final parser = SubLevelSelectorModifiers.parserOf(propertyName);
      if (parser == null) {
        throw const SubLevelSelectorException(SubLevelSelectorError.unknownProperty);
      }

      // The value runs to the next `,` or `]`; quoted values may contain both.
      final value = reader.readValue();
      modifiers.add(parser(value));
    }

    if (reader.canRead && reader.peek == ']') {
      reader.skip(1);
    } else {
      throw const SubLevelSelectorException(SubLevelSelectorError.unexpectedEndOfInput);
    }

    return modifiers;
  }

  SubLevelTarget _parseUuid(_SelectorReader reader) {
    final value = reader.readWord();
    if (!_isUuid(value)) {
      throw const SubLevelSelectorException(SubLevelSelectorError.invalidUuid);
    }
    return SubLevelTargetUuid(value);
  }

  static bool _isUuid(String value) =>
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(value);
}

/// The two helpers the Java argument type exposes to command bodies.
extension SubLevelTargetResolution on SubLevelTarget {
  /// `getSubLevels`: the selected sub-levels.
  List<ServerSubLevel> resolve(SubLevelTargetContext context) => getSubLevels(context);

  /// `getSingleSubLevel`: exactly one sub-level, or a failure.
  ServerSubLevel resolveSingle(SubLevelTargetContext context) {
    final subLevels = getSubLevels(context);
    if (subLevels.length > 1) {
      throw const SubLevelSelectorException(SubLevelSelectorError.singleSubLevelRequired);
    }
    if (subLevels.isEmpty) {
      throw const SubLevelSelectorException(SubLevelSelectorError.cannotFindSubLevel);
    }
    return subLevels.first;
  }
}

/// A minimal reader with Brigadier's cursor semantics.
final class _SelectorReader {
  final String _text;
  int _cursor = 0;

  _SelectorReader(this._text);

  bool get canRead => _cursor < _text.length;

  String get peek => _text[_cursor];

  void skip([int count = 1]) => _cursor += count;

  String read() => _text[_cursor++];

  /// Reads up to (not including) [character].
  String readUntil(String character) {
    final start = _cursor;
    while (canRead && peek != character) {
      _cursor++;
    }
    if (_cursor == start) {
      throw const SubLevelSelectorException(SubLevelSelectorError.unexpectedEndOfInput);
    }
    return _text.substring(start, _cursor);
  }

  /// Reads the next whitespace-delimited word.
  String readWord() {
    final start = _cursor;
    while (canRead && peek != ' ') {
      _cursor++;
    }
    return _text.substring(start, _cursor);
  }

  /// The next whitespace-delimited word without consuming it.
  String peekWord() {
    final start = _cursor;
    while (_cursor < _text.length && _text[_cursor] != ' ') {
      _cursor++;
    }
    final word = _text.substring(start, _cursor);
    _cursor = start;
    return word;
  }

  /// Reads a modifier value: quoted, or up to the next `,` / `]`.
  String readValue() {
    if (canRead && peek == '"') {
      skip(1);
      final buffer = StringBuffer();
      var escaped = false;
      while (canRead && (escaped || peek != '"')) {
        if (!escaped && peek == r'\') {
          escaped = true;
          skip(1);
        } else {
          buffer.write(read());
          escaped = false;
        }
      }
      if (canRead) {
        skip(1);
      } else {
        throw const SubLevelSelectorException(SubLevelSelectorError.unexpectedEndOfInput);
      }
      return buffer.toString();
    }

    final start = _cursor;
    while (canRead && peek != ',' && peek != ']') {
      _cursor++;
    }
    return _text.substring(start, _cursor);
  }
}

/// `Sable.HELPER.getContaining` for a selector source.
ServerSubLevel? containingSubLevelOf(SubLevelContainer container, Vector3d position) {
  final subLevel = container.getPlot(position.x.floor() >> 4, position.z.floor() >> 4)?.getSubLevel();
  return subLevel is ServerSubLevel ? subLevel : null;
}

/// A helper the selector uses to read a sub-level's bounding box.
BoundingBox3ic plotBoundsOf(ServerSubLevel subLevel) => subLevel.getPlot().getBoundingBox();
