// Key names for `/cc key`, as CC: Tweaked's `keys` API numbers them (GLFW key
// codes).
const Map<String, int> keyCodes = {
  'space': 32,
  'apostrophe': 39,
  'comma': 44,
  'minus': 45,
  'period': 46,
  'slash': 47,
  'semicolon': 59,
  'equals': 61,
  'enter': 257,
  'tab': 258,
  'backspace': 259,
  'insert': 260,
  'delete': 261,
  'right': 262,
  'left': 263,
  'down': 264,
  'up': 265,
  'pageup': 266,
  'pagedown': 267,
  'home': 268,
  'end': 269,
  'escape': 256,
  'leftshift': 340,
  'leftctrl': 341,
  'leftalt': 342,
  'rightshift': 344,
  'rightctrl': 345,
  'rightalt': 346,
};

/// The key code for [name]: a letter or digit, `f1` to `f12`, or one of
/// [keyCodes]. Null if unknown.
int? keyCodeOf(String name) {
  final lower = name.toLowerCase();
  final known = keyCodes[lower];
  if (known != null) return known;
  if (lower.length == 1) {
    final c = lower.codeUnitAt(0);
    if (c >= 97 && c <= 122) return c - 32; // letters: A = 65
    if (c >= 48 && c <= 57) return c;
  }
  final function = RegExp(r'^f(\d{1,2})$').firstMatch(lower);
  if (function != null) {
    final n = int.parse(function.group(1)!);
    if (n >= 1 && n <= 12) return 289 + n;
  }
  return null;
}
