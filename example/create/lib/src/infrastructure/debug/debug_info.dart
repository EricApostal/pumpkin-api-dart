// `DebugInfoSection`, `InfoEntry` and `ServerDebugInfoPacket.printInfo` (pure).

/// Supplies one value of the debug report. May throw: the report then shows the error.
typedef InfoProvider = String? Function(String? playerName);

/// An element of a debug section.
sealed class InfoElement {
  const InfoElement();

  /// Prints the element, one line per call of [lineConsumer].
  void print(int depth, String? playerName, void Function(String line) lineConsumer);
}

/// `InfoEntry`: `name: value`.
final class InfoEntry extends InfoElement {
  final String name;
  final InfoProvider provider;

  const InfoEntry(this.name, this.provider);

  /// `new InfoEntry(name, info)`.
  factory InfoEntry.constant(String name, String info) => InfoEntry(name, (_) => info);

  /// `InfoProvider.getInfoSafe`.
  String _value(String? player) {
    try {
      return '${provider(player)}';
    } on Object catch (e, s) {
      final b = StringBuffer('Error getting information! $e');
      for (final line in '$s'.split('\n').take(8)) {
        b.write('\n\t$line');
      }
      return b.toString();
    }
  }

  @override
  void print(int depth, String? playerName, void Function(String line) lineConsumer) {
    final value = _value(playerName);
    final indent = '\t' * depth;
    if (value.contains('\n')) {
      final lines = value.split('\n');
      final lineStart = '$name: ';
      lineConsumer(indent + lineStart + lines.first);
      final extraIndent = ' ' * lineStart.length;
      for (var i = 1; i < lines.length; i++) {
        lineConsumer(indent + extraIndent + lines[i]);
      }
    } else {
      lineConsumer('$indent$name: $value');
    }
  }
}

/// `DebugInfoSection`: a named group of elements.
final class DebugInfoSection extends InfoElement {
  final String name;
  final List<InfoElement> elements;

  const DebugInfoSection(this.name, this.elements);

  static DebugInfoSectionBuilder builder(String name) => DebugInfoSectionBuilder._(null, name);

  @override
  void print(int depth, String? playerName, void Function(String line) lineConsumer) {
    lineConsumer('${'\t' * depth}$name:');
    for (final e in elements) {
      e.print(depth + 1, playerName, lineConsumer);
    }
  }
}

/// `DebugInfoSection.Builder`.
final class DebugInfoSectionBuilder {
  final DebugInfoSectionBuilder? _parent;
  final String _name;
  final List<InfoElement> _elements = [];

  DebugInfoSectionBuilder._(this._parent, this._name);

  DebugInfoSectionBuilder put(String key, Object value) {
    if (value is String) {
      _elements.add(InfoEntry.constant(key, value));
    } else if (value is InfoProvider) {
      _elements.add(InfoEntry(key, value));
    } else if (value is String Function()) {
      _elements.add(InfoEntry(key, (_) => value()));
    } else {
      throw ArgumentError('Expected a String, an InfoProvider or a String Function()');
    }
    return this;
  }

  DebugInfoSectionBuilder putElement(InfoElement e) {
    _elements.add(e);
    return this;
  }

  DebugInfoSectionBuilder putAll(Iterable<InfoElement> elements) {
    _elements.addAll(elements);
    return this;
  }

  DebugInfoSectionBuilder section(String name) => DebugInfoSectionBuilder._(this, name);

  DebugInfoSectionBuilder finishSection() {
    final parent = _parent ?? (throw StateError('Cannot finish the root section'));
    parent._elements.add(build());
    return parent;
  }

  DebugInfoSection build() => DebugInfoSection(_name, List.unmodifiable(_elements));
}

/// The markdown report of `ServerDebugInfoPacket.printInfo(side, ...)`.
String printDebugInfo(String side, String? playerName, List<DebugInfoSection> sections) {
  final out = StringBuffer();
  out
    ..write('<details>\n')
    ..write('<summary>$side Info</summary>\n\n')
    ..write('```\n');
  for (var i = 0; i < sections.length; i++) {
    if (i != 0) out.write('\n');
    sections[i].print(0, playerName, (line) => out.write('$line\n'));
  }
  out
    ..write('```\n\n')
    ..write('</details>\n');
  return out.toString();
}
