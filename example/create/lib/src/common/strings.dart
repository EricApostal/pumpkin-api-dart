// StringHelper, DyeHelper and small text utilities (pure).
import 'data.dart';

/// `foundation.utility.StringHelper`.
abstract final class StringHelper {
  /// `snakeCaseToCamelCase`: `crushing_wheel` -> `CrushingWheel`.
  static String snakeCaseToCamelCase(String text) {
    if (text.isEmpty) return text;
    final b = StringBuffer(text.substring(0, 1).toUpperCase());
    for (var i = 1; i < text.length; i++) {
      final j = text.indexOf('_', i);
      if (j == -1) {
        b.write(text.substring(i));
        break;
      }
      b.write(text.substring(i, j).toLowerCase());
      if (j + 1 < text.length) b.write(text.substring(j + 1, j + 2).toUpperCase());
      i = j + 1;
    }
    return b.toString();
  }

  /// `camelCaseToSnakeCase`.
  static String camelCaseToSnakeCase(String text) {
    final b = StringBuffer();
    for (final c in text.codeUnits) {
      if (c >= 65 && c <= 90) {
        b.write('_');
        b.writeCharCode(c + 32);
      } else {
        b.writeCharCode(c);
      }
    }
    final s = b.toString();
    return s.startsWith('_') ? s.substring(1) : s;
  }

  /// `Lang.asId(name)`: lower case id from an enum constant name.
  static String asId(String name) => name.toLowerCase();

  /// `Lang.nameFromId` style: `blaze_burner` -> `Blaze Burner`.
  static String titleFromId(String id) =>
      id.split('_').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
}

/// The 16 dye colors in `DyeColor` order, with Minecraft ids.
const List<String> dyeColors = [
  'white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray',
  'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black',
];

/// `foundation.utility.DyeHelper`: front (bright) and back (dark) RGB colours of a dye.
abstract final class DyeHelper {
  static final Map<String, Couple<int>> _table = {
    'black': Couple(0x45403B, 0x21201F),
    'red': Couple(0xB13937, 0x632737),
    'green': Couple(0x208A46, 0x1D6045),
    'brown': Couple(0xAC855C, 0x68533E),
    'blue': Couple(0x5391E1, 0x504B90),
    'gray': Couple(0x5D666F, 0x313538),
    'light_gray': Couple(0x95969B, 0x707070),
    'purple': Couple(0x9F54AE, 0x63366C),
    'cyan': Couple(0x3EABB4, 0x3C7872),
    'pink': Couple(0xD5A8CB, 0xB86B95),
    'lime': Couple(0xA3DF55, 0x4FB16F),
    'yellow': Couple(0xE6D756, 0xE9AC29),
    'light_blue': Couple(0x69CED2, 0x508AA5),
    'orange': Couple(0xEE9246, 0xD94927),
    'magenta': Couple(0xF062B0, 0xC04488),
    'white': Couple(0xEDEAE5, 0xBBB6B0),
  };

  /// The (bright, dark) colours of the dye [color] (white's if unknown).
  static Couple<int> getDyeColors(String color) => _table[color] ?? _table['white']!;

  /// `addDye` for other mods' colours.
  static void addDye(String color, int bright, int dark) => _table[color] = Couple(bright, dark);

  /// The wool block key of a dye (`minecraft:red_wool`).
  static String getWoolOfDye(String color) => 'minecraft:${_table.containsKey(color) ? color : 'white'}_wool';
}
