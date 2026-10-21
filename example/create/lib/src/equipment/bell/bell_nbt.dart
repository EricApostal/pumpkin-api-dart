// The bell's `Ringing` tag (`AbstractBellBlockEntity`), pure so it can be tested
// without the host. Java writes `ringDirection.name()` (the enum constant, upper
// case) and reads it back with a lookup that falls back to
// `Direction.values()[0]` (`readEnum`).
import '../../conveyance/nbt_names.dart' show enumFromNbtName, enumNbtName;
import '../model/dir.dart';

/// `AbstractBellBlockEntity.write`: `tag.putString("Ringing", ringDirection.name())`.
String ringDirectionNbtName(Dir direction) => enumNbtName(direction.name);

/// `AbstractBellBlockEntity.read`: an unknown or missing name is `Direction.DOWN`.
Dir ringDirectionFromNbtName(String name) => enumFromNbtName(name, Dir.values);