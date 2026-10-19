// Train names are text components (pure): the JSON form they are saved in
// (`ComponentSerialization.CODEC` -> JSON string) and its reader.
import '../../redstone/support/text.dart' show Txt, tryParseJson;

/// `componentToJson(component)`.
String componentToJson(Txt component) => component.toJsonString();

/// `componentFromJson(json)`: a literal, translatable or list component; anything unreadable is
/// the empty component.
Txt componentFromJson(String json) {
  final value = tryParseJson(json);
  if (value == null && json.trim() != 'null') {
    // not JSON: a plain name
    return json.isEmpty ? Txt.literal('') : Txt.literal(json);
  }
  return txtFromJsonValue(value);
}

/// The component of a decoded JSON value.
Txt txtFromJsonValue(Object? value) {
  if (value is String) return Txt.literal(value);
  if (value is num || value is bool) return Txt.literal('$value');
  if (value is List<Object?>) {
    if (value.isEmpty) return Txt.literal('');
    final first = txtFromJsonValue(value.first);
    for (final e in value.skip(1)) {
      first.append(txtFromJsonValue(e));
    }
    return first;
  }
  if (value is Map<String, Object?>) {
    final Txt t;
    if (value['text'] != null) {
      t = Txt.literal('${value['text']}');
    } else if (value['translate'] is String) {
      final with_ = value['with'];
      t = Txt.translate(value['translate']! as String, [
        if (with_ is List<Object?>) for (final a in with_) txtFromJsonValue(a),
      ]);
    } else {
      t = Txt.literal('');
    }
    final color = value['color'];
    if (color is String && color.startsWith('#') && color.length == 7) {
      t.color = int.tryParse(color.substring(1), radix: 16) ?? -1;
    }
    final extra = value['extra'];
    if (extra is List<Object?>) {
      for (final e in extra) {
        t.append(txtFromJsonValue(e));
      }
    }
    return t;
  }
  return Txt.literal('');
}
