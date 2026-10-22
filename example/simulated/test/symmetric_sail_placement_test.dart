// The symmetric sail's placement rules: where the next sail of a sheet goes
// (`SymmetricSailPlacementHelper.getOffset`) and which items count as sails.
import 'package:create/src/api/block_state.dart';
import 'package:simulated/src/content/blocks/symmetric_sail/symmetric_sail_placement.dart';
import 'package:test/test.dart';

const sailY = BState('simulated:white_symmetric_sail', {'axis': 'y'});

void main() {
  group('isSymmetricSailItem', () {
    test('is the item of a sail block', () {
      expect(isSymmetricSailItem('simulated:white_symmetric_sail'), isTrue);
      expect(isSymmetricSailItem('simulated:red_symmetric_sail'), isTrue);
      expect(isSymmetricSailItem('create:white_sail'), isFalse);
      expect(isSymmetricSailItem('minecraft:stone'), isFalse);
    });
  });

  group('symmetricSailOffset', () {
    test('puts the next sail against the clicked side of the sheet', () {
      final level = MapBlockGetter(blocks: {(4, 100, 4): sailY});
      // A click near the north edge of a `y` sail (its sheet is horizontal, so the
      // row grows in the `x`/`z` plane).
      final offset = symmetricSailOffset(
        level: level,
        state: sailY,
        pos: (4, 100, 4),
        hit: (4.5, 101, 4.1),
      );
      expect(offset.isSuccessful, isTrue);
      expect(offset.pos, (4, 100, 3));
      expect(
        offset.transform(BState('simulated:white_symmetric_sail')).props['axis'],
        'y',
        reason: 'the new sail keeps the clicked sail\'s axis',
      );
    });

    test('never places along the sail\'s own axis', () {
      final level = MapBlockGetter(blocks: {(4, 100, 4): sailY});
      // Straight above the sail: that is the axis it lies on, so the helper refuses.
      final offset = symmetricSailOffset(
        level: level,
        state: sailY,
        pos: (4, 100, 4),
        hit: (4.5, 101.0, 4.5),
      );
      expect(
        offset.isSuccessful,
        isTrue,
        reason: 'the ordered directions still put a horizontal neighbour first',
      );
      expect(offset.pos.$2, 100, reason: 'the next sail stays in the sheet');
    });

    test('skips a neighbour that cannot be replaced', () {
      final level = MapBlockGetter(blocks: {
        (4, 100, 4): sailY,
        (4, 100, 3): BState('minecraft:stone'),
      });
      final offset = symmetricSailOffset(
        level: level,
        state: sailY,
        pos: (4, 100, 4),
        hit: (4.5, 101, 4.1),
      );
      expect(offset.isSuccessful, isTrue);
      expect(offset.pos, isNot((4, 100, 3)), reason: 'stone is not replaceable');
    });

    test('fails when the clicked block has no axis', () {
      final offset = symmetricSailOffset(
        level: MapBlockGetter(),
        state: BState('minecraft:air'),
        pos: (0, 0, 0),
        hit: (0, 0, 0),
      );
      expect(offset.isSuccessful, isFalse);
    });

    test('a `z` sail grows along `x` and keeps its axis', () {
      const sailZ = BState('simulated:white_symmetric_sail', {'axis': 'z'});
      final level = MapBlockGetter(blocks: {(4, 100, 4): sailZ});
      // Near the east edge.
      final offset = symmetricSailOffset(
        level: level,
        state: sailZ,
        pos: (4, 100, 4),
        hit: (4.9, 100.5, 4.5),
      );
      expect(offset.isSuccessful, isTrue);
      expect(offset.pos, (5, 100, 4));
      expect(
        offset.transform(BState('simulated:white_symmetric_sail')).props['axis'],
        'z',
      );
    });
  });
}