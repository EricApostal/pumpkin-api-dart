// The identifier contract between Sable and Create's block entity store.
//
// The listeners and the physics step name their level by `SableLevel.dimensionId` — the dimension
// key, `minecraft:overworld` — while Create's `BlockEntityStore` is keyed by `World.getId()`, the
// world id, which is the folder name (`world`). The compat layer therefore hands the lookup a
// dimension key and requires the installed lookup to resolve it (`CreateHostCompat.install` takes
// `worldIdOf` for exactly that). Passing it straight through to the store silently finds nothing,
// which is the bug class this test pins: it asserts the value the listeners pass, and that a world
// id is a different string.
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:sable/src/compat/create/create_block_hooks.dart';
import 'package:sable/src/compat/create/create_blocks.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final lookups = <(String, Pos)>[];
  setUp(() {
    lookups.clear();
    CreateCompatBlocks.blockEntityLookup = (identifier, pos) {
      lookups.add((identifier, pos));
      return null;
    };
  });
  tearDown(() {
    CreateCompatBlocks.blockEntityLookup = null;
    CreateCompatBlocks.chainConveyorValidate = null;
    CreateCompatBlocks.chainConveyorCheckInvalid = null;
  });

  test('the chain conveyor listener names the level by its dimension id', () {
    final level = FakeLevel('minecraft:overworld');
    const listener = ChainConveyorAssemblyListener();

    listener.beforeMove(level, level, BState.air, (1, 2, 3), (4, 5, 6));
    listener.afterMove(level, level, BState.air, (1, 2, 3), (4, 5, 6));

    expect(lookups.map((e) => e.$1), ['minecraft:overworld', 'minecraft:overworld']);
    expect(lookups.first.$1, isNot('world'));
  });

  test('the display link listener names both levels by their dimension id', () {
    final from = FakeLevel('minecraft:overworld');
    final to = FakeLevel('minecraft:the_nether');
    const listener = DisplayLinkAssemblyListener();

    listener.afterMove(from, to, BState.air, (1, 2, 3), (4, 5, 6));

    expect(lookups.map((e) => e.$1), ['minecraft:overworld', 'minecraft:the_nether']);
  });

  test('a dimension key is not a world id', () {
    // The two strings the host reports for the overworld. The store is keyed by the second.
    expect(FakeLevel('minecraft:overworld').dimensionId, isNot('world'));
  });
}
