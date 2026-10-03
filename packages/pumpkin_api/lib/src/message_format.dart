import 'dart:convert';

/// Pure helpers for chat text: legacy color codes, durations and message
/// templates. Nothing in this file touches the host, so it can be unit tested
/// on the Dart VM.
abstract final class MessageFormat {
  static const _codeChars = '0123456789abcdefklmnorABCDEFKLMNOR';

  /// Translates `&` color codes into the section sign (`§`) that Minecraft's
  /// legacy format uses: `colorize('&aHello &lworld')` is `§aHello §lworld`.
  ///
  /// Only an `&` followed by a valid code character (`0-9 a-f k-o r`) is
  /// translated, so `Fish & chips` stays as it is. `&&` is an escape for a
  /// literal `&`.
  static String colorize(String input) {
    if (!input.contains('&')) return input;
    final out = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (c == '&' && i + 1 < input.length) {
        final next = input[i + 1];
        if (next == '&') {
          out.write('&');
          i++;
          continue;
        }
        if (_codeChars.contains(next)) {
          out.write('§');
          continue;
        }
      }
      out.write(c);
    }
    return out.toString();
  }

  /// Escapes [input] so [colorize] leaves it untouched, for player supplied
  /// text: `&` becomes `&&` and `§` is removed.
  static String escape(String input) =>
      input.replaceAll('§', '').replaceAll('&', '&&');

  /// Removes legacy color codes (both `§x` and `&x`) from [input].
  static String stripColors(String input) {
    final out = StringBuffer();
    final text = colorize(input);
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '§') {
        i++; // Skip the code character too.
        continue;
      }
      out.write(text[i]);
    }
    return out.toString();
  }

  /// [d] in server ticks (20 per second), rounded up.
  static int ticks(Duration d) => (d.inMilliseconds + 49) ~/ 50;

  /// Substitutes placeholders in [template] with [values].
  ///
  /// `{name}` takes the value from a `Map`, `{0}` from a `List` (or from a
  /// `Map` that has the key `'0'`). `{{` and `}}` are literal braces.
  /// Placeholders without a value stay in the output as written.
  static String format(String template, [Object? values]) {
    if (!template.contains('{') && !template.contains('}')) return template;
    final out = StringBuffer();
    var i = 0;
    while (i < template.length) {
      final c = template[i];
      if (c == '{') {
        if (i + 1 < template.length && template[i + 1] == '{') {
          out.write('{');
          i += 2;
          continue;
        }
        final end = template.indexOf('}', i + 1);
        if (end != -1) {
          final key = template.substring(i + 1, end);
          final value = _lookup(key, values);
          out.write(value.found ? '${value.value}' : '{$key}');
          i = end + 1;
          continue;
        }
      } else if (c == '}' && i + 1 < template.length && template[i + 1] == '}') {
        out.write('}');
        i += 2;
        continue;
      }
      out.write(c);
      i++;
    }
    return out.toString();
  }

  static ({bool found, Object? value}) _lookup(String key, Object? values) {
    if (values is Map) {
      if (values.containsKey(key)) return (found: true, value: values[key]);
    } else if (values is List) {
      final index = int.tryParse(key);
      if (index != null && index >= 0 && index < values.length) {
        return (found: true, value: values[index]);
      }
    }
    return (found: false, value: null);
  }
}

/// A message with `{placeholder}` slots, usually obtained from a
/// [MessageCatalog].
///
/// ```dart
/// const MessageTemplate('&aHome {name} set!').format({'name': 'base'});
/// ```
final class MessageTemplate {
  /// The raw template text, with `&` color codes and placeholders.
  final String text;

  /// Creates a template from [text].
  const MessageTemplate(this.text);

  /// Fills the placeholders from a `Map` (`{name}`) or `List` (`{0}`).
  String format([Object? values]) => MessageFormat.format(text, values);

  @override
  String toString() => text;
}

/// Message templates by key: built-in defaults that server owners can
/// override, typically from a JSON file.
///
/// ```dart
/// final messages = MessageCatalog({'home.set': '&aHome {name} set!'});
/// messages['home.set'].format({'name': 'base'}); // '&aHome base set!'
/// sender.sendTemplate(messages, 'home.set', {'name': 'base'});
/// ```
///
/// To load overrides from the plugin's data folder (and write missing keys
/// back so owners can edit them) use `DataFolder.messageCatalog`.
final class MessageCatalog {
  /// The built-in messages.
  final Map<String, String> defaults;

  /// Messages that replace [defaults], for example from a file.
  final Map<String, String> overrides;

  /// Text put before every message formatted with [text] (and sent with
  /// `sendTemplate`), for example `'&8[&6Homes&8] &r'`.
  final String prefix;

  /// Creates a catalog. Entries of [overrides] win over [defaults].
  MessageCatalog(
    Map<String, String> defaults, {
    Map<String, String> overrides = const {},
    this.prefix = '',
  }) : defaults = Map.unmodifiable(defaults),
       overrides = Map.unmodifiable(overrides);

  /// Parses [json] (an object of strings) as the overrides. Missing, invalid
  /// or non-string entries are ignored, so a broken file falls back to the
  /// [defaults].
  factory MessageCatalog.fromJson(
    Map<String, String> defaults,
    String? json, {
    String prefix = '',
  }) {
    final overrides = <String, String>{};
    if (json != null) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            if (e.key is String && e.value is String) {
              overrides[e.key as String] = e.value as String;
            }
          }
        }
      } on FormatException {
        // Ignore, use the defaults.
      }
    }
    return MessageCatalog(defaults, overrides: overrides, prefix: prefix);
  }

  /// Whether [key] has a message.
  bool has(String key) => overrides.containsKey(key) || defaults.containsKey(key);

  /// The template for [key]. An unknown key gives a template that shows the
  /// key itself, so a missing message is visible instead of throwing.
  MessageTemplate operator [](String key) =>
      MessageTemplate(overrides[key] ?? defaults[key] ?? key);

  /// The formatted message for [key], including the [prefix].
  String text(String key, [Object? values]) =>
      '$prefix${this[key].format(values)}';

  /// Every key with its effective text: [defaults] with [overrides] on top.
  Map<String, String> get effective => {...defaults, ...overrides};

  /// The keys of [defaults] that [overrides] doesn't have.
  List<String> get missingKeys =>
      [for (final k in defaults.keys) if (!overrides.containsKey(k)) k];

  /// [effective] as pretty printed JSON, for writing the file.
  String toJson() => const JsonEncoder.withIndent('  ').convert(effective);
}

/// Pure layout of sidebar lines, see `Sidebar`.
abstract final class SidebarLayout {
  /// Turns [lines] (legacy text, `&` codes allowed) into unique score entry
  /// names, since a scoreboard has one score per name: repeated lines get
  /// invisible `§r` suffixes. Empty lines become distinct blanks.
  static List<String> entries(List<String> lines) {
    final seen = <String, int>{};
    final out = <String>[];
    for (final raw in lines) {
      final line = MessageFormat.colorize(raw);
      final n = seen.update(line, (v) => v + 1, ifAbsent: () => 0);
      out.add('$line${'§r' * n}');
    }
    return out;
  }

  /// The score of line [index] of [count]: the first line gets the highest
  /// score, so it is shown at the top.
  static int score(int index, int count) => count - index;
}
