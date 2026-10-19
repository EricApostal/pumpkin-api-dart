// Nixie tubes as pure logic: the row walk (`NixieTubeBlock.walkNixies`), directions and
// the characters a tube shows (`NixieTubeBlockEntity.updateDisplayedStrings`).
import '../../common/common.dart';

/// The block key of the nixie tube of [color] (`orange` is plain `nixie_tube`).
String nixieBlockKey(String color) => color == 'orange' ? 'create:nixie_tube' : 'create:${color}_nixie_tube';

/// The dye colour names in `DyeColor` order.
const List<String> dyeColorNames = [
  'white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray',
  'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black', //
];

/// The keys of all 16 nixie tube blocks.
final List<String> nixieBlockKeys = [for (final c in dyeColorNames) nixieBlockKey(c)];

/// Whether [key] is a nixie tube block.
bool isNixieKey(String? key) => key != null && key.startsWith('create:') && key.endsWith('nixie_tube');

/// `getLeftNixieDirection`.
Direction leftNixieDirection(Map<String, String> properties) {
  final facing = Direction.byName(properties['facing'] ?? 'north') ?? Direction.north;
  var left = facing.opposite;
  final face = properties['double_face'];
  if (face == 'wall') left = Direction.up;
  if (face == 'wall_reversed') left = Direction.down;
  return left;
}

/// `getRightNixieDirection`.
Direction rightNixieDirection(Map<String, String> properties) => leftNixieDirection(properties).opposite;

/// The tube at a position as the row walk sees it.
typedef NixieAt = ({String key, Map<String, String> properties})? Function(Pos pos);

/// `areNixieBlocksEqual`: both are nixie tubes of the same attachment (colour ignored).
bool areNixieBlocksEqual(({String key, Map<String, String> properties})? a, ({String key, Map<String, String> properties})? b) {
  if (a == null || b == null) return false;
  if (!isNixieKey(a.key) || !isNixieKey(b.key)) return false;
  return a.properties['facing'] == b.properties['facing'] &&
      a.properties['waterlogged'] == b.properties['waterlogged'] &&
      a.properties['double_face'] == b.properties['double_face'];
}

/// `walkNixies` (without the ComputerCraft rule): the positions of the row of [start], from its
/// left end to its right end, with their index. Empty when [start] is not a nixie tube.
List<(Pos, int)> walkNixies(Pos start, NixieAt at) {
  final state = at(start);
  if (state == null || !isNixieKey(state.key)) return const [];

  final left = leftNixieDirection(state.properties);
  final right = left.opposite;

  var current = start;
  while (true) {
    final next = current.relative(left);
    if (!areNixieBlocksEqual(at(next), state)) break;
    current = next;
  }

  final row = <(Pos, int)>[];
  var index = 0;
  while (true) {
    row.add((current, index));
    final next = current.relative(right);
    if (!areNixieBlocksEqual(at(next), state)) break;
    current = next;
    index++;
  }
  return row;
}

/// `charOrEmpty`.
String charOrEmpty(String string, int index) => string.length <= index ? ' ' : string.substring(index, index + 1);

/// `updateDisplayedStrings`: the two characters of the tube. [customText] is the resolved
/// text when a custom text is set.
(String, String) displayedStrings({String? customText, required int nixieIndex, required int redstoneStrength}) {
  if (customText != null) return (charOrEmpty(customText, nixieIndex * 2), charOrEmpty(customText, nixieIndex * 2 + 1));
  return (redstoneStrength < 10 ? '0' : '1', '${redstoneStrength % 10}');
}

/// The `DyeColor` a dye item key stands for (`minecraft:red_dye`), `null` if it is not a dye.
String? dyeColorOfItem(String itemKey) {
  const suffix = '_dye';
  if (!itemKey.startsWith('minecraft:') || !itemKey.endsWith(suffix)) return null;
  final name = itemKey.substring('minecraft:'.length, itemKey.length - suffix.length);
  return dyeColorNames.contains(name) ? name : null;
}
