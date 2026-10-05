// Minecraft resource locations ("identifiers"), as the NeoForge payloads carry
// them. Binding-free.

/// The namespace used when an identifier has none.
const String defaultNamespace = 'minecraft';

final RegExp _namespaceChars = RegExp(r'^[a-z0-9_.-]+$');
final RegExp _pathChars = RegExp(r'^[a-z0-9_./-]+$');

/// Whether [text] is a valid identifier, with or without namespace.
bool isValidIdentifier(String text) {
  try {
    normalizeIdentifier(text);
    return true;
  } on FormatException {
    return false;
  }
}

/// Parses [text] like Minecraft's `Identifier.parse` and returns the canonical
/// `namespace:path` form (an identifier without a colon gets the `minecraft`
/// namespace). Throws a [FormatException] if the characters are not allowed:
/// namespaces are `[a-z0-9_.-]`, paths additionally allow `/`.
String normalizeIdentifier(String text) {
  final colon = text.indexOf(':');
  final namespace = colon < 0 ? defaultNamespace : text.substring(0, colon);
  final path = colon < 0 ? text : text.substring(colon + 1);
  // An empty namespace before the colon means the default one as well.
  final ns = namespace.isEmpty ? defaultNamespace : namespace;
  if (!_namespaceChars.hasMatch(ns)) {
    throw FormatException('Invalid identifier namespace', text);
  }
  if (path.isEmpty || !_pathChars.hasMatch(path)) {
    throw FormatException('Invalid identifier path', text);
  }
  return '$ns:$path';
}

/// The namespace of a canonical identifier.
String namespaceOf(String identifier) =>
    identifier.substring(0, identifier.indexOf(':'));

/// The path of a canonical identifier.
String pathOf(String identifier) =>
    identifier.substring(identifier.indexOf(':') + 1);
