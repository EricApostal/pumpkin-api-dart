// The bell's `Ringing` tag (`AbstractBellBlockEntity`), pure so it can be tested
// without the host. Java writes `ringDirection.name()` (the enum constant, upper
// case) and reads it back with a case-sensitive lookup that falls back to
// `Direction.values()[0]` (`readEnum`).
import '../model/dir.dart';

/// `AbstractBellBlockEntity.write`: `tag.putString("Ringing", ringDirection.name())`.
String ringDirectionNbtName(Dir direction) => direction.name.toUpperCase();

/// `AbstractBellBlockEntity.read`: an unknown or missing name is `Direction.DOWN`.
Dir ringDirectionFromNbtName(String name) {
  for (final d in Dir.values) {
    if (d.name.toUpperCase() == name) return d;
  }
  return Dir.values.first;
}
