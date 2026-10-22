// A small text component (pure): what display sources produce and display targets
// consume (`MutableComponent`). It keeps literal and translatable parts, colour and
// siblings, renders to the plain string a server shows (`Component.getString`) and to
// the JSON the vanilla codec reads (signs, nixie tubes).
import 'dart:convert';

/// The English texts of the Create lang keys display sources use, to render translatable
/// components on a server without resource packs (`Language` of the server).
const Map<String, String> kCreateEnglish = {
  'create.boiler.heat': 'Heat',
  'create.boiler.idle': 'Idle',
  'create.boiler.lvl': 'Lvl %1\$s',
  'create.boiler.max_lvl': 'Max',
  'create.boiler.passive': 'Passive',
  'create.boiler.per_tick': '%1\$s per Tick',
  'create.boiler.size': 'Size',
  'create.boiler.status': 'Boiler Status:  %1\$s',
  'create.boiler.status_short': 'Boiler:  %1\$s',
  'create.boiler.water': 'Water',
  'create.boiler.size_dots': '....... ',
  'create.boiler.water_dots': '... ',
  'create.boiler.heat_dots': '...... ',
  'create.display_source.boiler.for_boiler_status': 'for Boiler Status',
  'create.display_source.boiler.not_enough_space': 'Not enough space ',
  'create.display_source.scoreboard.objective.deaths': 'Player Deaths',
  'create.display_source.scoreboard.objective_not_found': "'%1\$s' not found",
  'create.display_source.value_list.million': 'm',
  'create.display_source.value_list.thousand': 'k',
  'create.display_source.station_summary.now': 'now',
  'create.display_source.station_summary.minutes': ' min',
  'create.display_source.station_summary.seconds': '%1\$ss',
  'create.generic.unit.rpm': 'RPM',
  'create.generic.unit.stress': 'su',
  'create.generic.unit.buckets': 'B',
  'create.generic.unit.millibuckets': 'mB',
  'create.generic.daytime.am': 'am',
  'create.generic.daytime.pm': 'pm',
  'create.schedule.condition.threshold.items': 'Items',
  'create.schedule.condition.threshold.stacks': 'Stacks',
  'create.schedule.condition.threshold.buckets': 'Buckets',
  'create.display_target.single_line': 'Single Line',
  'create.display_target.page': 'Page %1\$s',
  'create.display_target.line': 'Line %1\$s',
  'create.tooltip.analogStrength': 'Analog Strength: %1\$s/15',
  'create.train.status': '<i> Information about Train: %1\$s',
  'create.train.status.back_on_track': 'Train is back on Track',
  'create.train.status.collision': 'Collision with other Train',
  'create.train.status.collision.where': 'In %1\$s near [%2\$s]',
  'create.train.status.coupling_stress': 'Forced stop due to Stress on Couplings',
  'create.train.status.double_portal': 'A Carriage cannot enter a portal whilst leaving another',
  'create.train.status.end_of_track': 'A Carriage has reached the end of its Track',
  'create.train.status.found_driver': 'A new driver has been found',
  'create.train.status.missing_driver': 'Driver has gone missing',
  'create.train.status.navigation_success': 'Navigation succeeded',
  'create.train.status.no_match': "No station on graph matches '%1\$s'",
  'create.train.status.no_package_target': 'A package in cargo has no postbox that matches its address',
  'create.train.status.no_path': 'No suitable path to the next Scheduled destination could be found',
  'create.train.status.opposite_driver': 'Path requires a driver facing the opposite direction',
  'create.train.status.paused_for_manual': 'Schedule paused for manual controls',
  'create.train.status.track_missing': 'Tracks are missing beneath the Train',
};

/// A mutable text component.
final class Txt {
  /// The literal text, `null` for a translatable component.
  final String? literal;

  /// The lang key of a translatable component.
  final String? translateKey;
  final List<Txt> args;

  /// Colour as 0xRRGGBB, -1 for none.
  int color;

  /// Siblings, appended after this component's own text.
  final List<Txt> siblings = [];

  Txt.literal(String text)
    : literal = text,
      translateKey = null,
      args = const [],
      color = -1;

  Txt.translate(String key, [List<Txt> arguments = const []])
    : literal = null,
      translateKey = key,
      args = arguments,
      color = -1;

  /// `Component.empty()`.
  factory Txt.empty() => Txt.literal('');

  /// `CommonComponents.space()`.
  factory Txt.space() => Txt.literal(' ');

  /// `MutableComponent.append`: returns this.
  Txt append(Txt other) {
    siblings.add(other);
    return this;
  }

  /// `append(String)`.
  Txt appendText(String text) => append(Txt.literal(text));

  /// `withStyle(color)`.
  Txt withColor(int rgb) {
    color = rgb;
    return this;
  }

  /// `copy()` / `plainCopy()` with siblings.
  Txt copy() {
    final c = literal != null ? Txt.literal(literal!) : Txt.translate(translateKey!, [for (final a in args) a.copy()]);
    c.color = color;
    for (final s in siblings) {
      c.siblings.add(s.copy());
    }
    return c;
  }

  /// `Component.getString()` of this component without its siblings.
  String get ownPlain {
    if (literal != null) return literal!;
    return _translate(translateKey!, [for (final a in args) a.plain]);
  }

  /// `Component.getString()`: the text with siblings, translations in English.
  String get plain {
    final b = StringBuffer();
    b.write(ownPlain);
    for (final s in siblings) {
      b.write(s.plain);
    }
    return b.toString();
  }

  static String _translate(String key, List<String> args) {
    final template = kCreateEnglish[key];
    if (template == null) return key;
    var i = 0;
    return template.replaceAllMapped(RegExp(r'%(?:(\d+)\$)?([sd%])'), (m) {
      if (m.group(2) == '%') return '%';
      final index = m.group(1) != null ? int.parse(m.group(1)!) - 1 : i++;
      return index >= 0 && index < args.length ? args[index] : '';
    });
  }

  /// The JSON value the vanilla component codec reads (a string for unstyled literals).
  Object toJson() {
    if (literal != null && color == -1 && siblings.isEmpty) return literal!;
    final map = <String, Object?>{};
    if (literal != null) {
      map['text'] = literal;
    } else {
      map['translate'] = translateKey;
      if (args.isNotEmpty) map['with'] = [for (final a in args) a.toJson()];
    }
    if (color != -1) map['color'] = '#${color.toRadixString(16).padLeft(6, '0')}';
    if (siblings.isNotEmpty) map['extra'] = [for (final s in siblings) s.toJson()];
    return map;
  }

  /// [toJson] as text (`ComponentSerialization.CODEC ... .toString()`).
  String toJsonString() => jsonEncode(toJson());

  @override
  String toString() => 'Txt($plain)';
}

/// The plain string of a JSON text component (`Component.getString()`): strings, lists
/// (the first element is the base, the rest siblings) and objects with `text`,
/// `translate`/`with` and `extra`. Anything else (selectors, scores, NBT) contributes nothing.
String plainTextOfJson(Object? json) {
  if (json == null) return '';
  if (json is String) return json;
  if (json is num || json is bool) return '$json';
  if (json is List<Object?>) return json.map(plainTextOfJson).join();
  if (json is Map<String, Object?>) {
    final b = StringBuffer();
    final text = json['text'];
    if (text != null) {
      b.write(plainTextOfJson(text));
    } else if (json['translate'] is String) {
      final args = json['with'];
      b.write(Txt.translate(json['translate']! as String, [
        if (args is List<Object?>) for (final a in args) Txt.literal(plainTextOfJson(a)),
      ]).plain);
    } else if (json['keybind'] is String) {
      b.write(json['keybind']);
    }
    final extra = json['extra'];
    if (extra is List<Object?>) b.write(extra.map(plainTextOfJson).join());
    return b.toString();
  }
  return '';
}

/// Parses [source] as JSON; `null` when it is not valid (`DynamicComponent.getJsonFromString`).
Object? tryParseJson(String source) {
  try {
    return jsonDecode(source);
  } on FormatException {
    return null;
  }
}

/// `LangNumberFormat.format`: at most two decimals, digit grouping with commas.
String formatNumber(double d) {
  if ((d).abs() < 1e-5) d = 0;
  var s = d.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  var sign = '';
  if (s.startsWith('-')) {
    sign = '-';
    s = s.substring(1);
  }
  final dot = s.indexOf('.');
  final whole = dot < 0 ? s : s.substring(0, dot);
  final fraction = dot < 0 ? '' : s.substring(dot);
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '$sign$grouped$fraction';
}
