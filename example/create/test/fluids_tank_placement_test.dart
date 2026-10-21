// `FluidTankItem.tryMultiPlace`: a tank placed on the top or bottom of a wider tank places the
// whole layer of the same footprint (`FluidTankItem.java:66-121`). The geometry is pure
// (`lib/src/fluids/tank_placement.dart`) so it runs on the VM.
import 'package:create/src/common/pos.dart';
import 'package:create/src/fluids/tank_placement.dart';
import 'package:test/test.dart';

/// Runs the placement with [tanks] as the existing tank blocks and [blocked] as positions that
/// cannot be replaced. The placed tank itself is always a tank, as it is when the event fires.
List<Pos>? place({
  required Pos pos,
  required TankExtent? below,
  required TankExtent? above,
  Set<Pos> tanks = const {},
  Set<Pos> blocked = const {},
}) => tankLayerTargets(
  pos: pos,
  below: below,
  above: above,
  isTank: tanks.contains,
  canBeReplaced: (p) => !blocked.contains(p),
);

/// The four blocks of a 2x2 tank whose controller corner is [corner] at its bottom layer.
Set<Pos> layer(Pos corner, {int y = 0}) => {
  for (var x = 0; x < 2; x++)
    for (var z = 0; z < 2; z++) (corner.$1 + x, y, corner.$3 + z),
};

const Pos origin = (0, 0, 0);

void main() {
  group('a tank placed on a wider tank places a layer', () {
    test('on the far corner of a 2x2, not just over the controller', () {
      // The click is on the (1, 1) column, so the new tank is at (1, 1, 1) - not at the
      // controller's corner (0, 1, 0). Java still places the whole layer.
      final targets = place(
        pos: (1, 1, 1),
        below: (controller: origin, width: 2, height: 1),
        above: null,
        tanks: {...layer(origin), const (1, 1, 1)},
      );

      expect(targets, const [(0, 1, 0), (0, 1, 1), (1, 1, 0)]);
    });

    test('over the controller column too', () {
      final targets = place(
        pos: (0, 1, 0),
        below: (controller: origin, width: 2, height: 1),
        above: null,
        tanks: {...layer(origin), const (0, 1, 0)},
      );

      expect(targets, const [(0, 1, 1), (1, 1, 0), (1, 1, 1)]);
    });

    test('under a 2x2, on its bottom plane', () {
      final targets = place(
        pos: (1, -1, 1),
        below: null,
        above: (controller: origin, width: 2, height: 1),
        tanks: {...layer(origin), const (1, -1, 1)},
      );

      expect(targets, const [(0, -1, 0), (0, -1, 1), (1, -1, 0)]);
    });

    test('above the top of a tall tank', () {
      // A 2x2 tank 3 blocks tall: its top plane is at y = 0 + 3, not at y = 1.
      final targets = place(
        pos: (1, 3, 0),
        below: (controller: origin, width: 2, height: 3),
        above: null,
        tanks: {
          for (var y = 0; y < 3; y++) ...layer(origin, y: y),
          const (1, 3, 0),
        },
      );

      expect(targets, const [(0, 3, 0), (0, 3, 1), (1, 3, 1)]);
    });

    test('a 3x3 layer has nine positions', () {
      final targets = place(
        pos: (2, 1, 2),
        below: (controller: origin, width: 3, height: 1),
        above: null,
        tanks: {
          for (var x = 0; x < 3; x++)
            for (var z = 0; z < 3; z++) (x, 0, z),
          const (2, 1, 2),
        },
      );

      expect(targets, hasLength(8));
      expect(targets, isNot(contains(const (2, 1, 2))));
      expect(
        targets,
        everyElement(
          predicate<Pos>(
            (p) =>
                p.$2 == 1 &&
                p.$1 >= 0 &&
                p.$1 < 3 &&
                p.$3 >= 0 &&
                p.$3 < 3,
          ),
        ),
      );
    });

    test('a 1 wide tank below does not hide a wide tank above', () {
      // `width == 1` skips *that* multiblock, it does not end the search: Java would reach the
      // wide tank for the face that points at it, and without the face the only multiblock that
      // can be extended here is the wide one.
      final targets = place(
        pos: (0, -1, 0),
        below: (controller: (0, -2, 0), width: 1, height: 1),
        above: (controller: origin, width: 2, height: 1),
        tanks: {const (0, -2, 0), ...layer(origin), const (0, -1, 0)},
      );

      expect(targets, const [(0, -1, 1), (1, -1, 0), (1, -1, 1)]);
    });

    test('a complete layer places nothing', () {
      final targets = place(
        pos: (1, 1, 1),
        below: (controller: origin, width: 2, height: 1),
        above: null,
        tanks: {...layer(origin), ...layer(origin, y: 1)},
      );

      expect(targets, isEmpty);
    });
  });

  group('a placement that does not extend a tank', () {
    test('a 1 wide tank', () {
      expect(
        place(
          pos: (0, 1, 0),
          below: (controller: origin, width: 1, height: 1),
          above: null,
          tanks: {origin, const (0, 1, 0)},
        ),
        isNull,
      );
    });

    test('no tank on either side', () {
      expect(
        place(pos: (0, 1, 0), below: null, above: null),
        isNull,
      );
    });

    test('a tank two layers above the top plane', () {
      expect(
        place(
          pos: (0, 2, 0),
          below: (controller: origin, width: 2, height: 1),
          above: null,
          tanks: {...layer(origin), const (0, 2, 0)},
        ),
        isNull,
      );
    });

    test('a side placement beside the top layer', () {
      // Clicking the east face of the (1, 0, 1) tank puts the new one at (2, 0, 1): the same
      // y as the tank below's top plane, but outside the footprint. Java rejects it because
      // the clicked face is not vertical.
      expect(
        place(
          pos: (2, 0, 1),
          below: (controller: origin, width: 2, height: 1),
          above: null,
          tanks: {...layer(origin), const (2, 0, 1)},
        ),
        isNull,
      );
    });

    test('a side placement at the top plane level', () {
      // The same, one level up: the block below (2, 0, 1) is not part of the 2x2, so there is
      // no multiblock whose plane this is.
      expect(
        place(
          pos: (2, 1, 1),
          below: (controller: origin, width: 2, height: 1),
          above: null,
          tanks: {...layer(origin), const (2, 1, 1)},
        ),
        isNull,
      );
    });

    test('one position that cannot be replaced cancels the layer', () {
      // Java returns on the first blocked position instead of skipping it.
      expect(
        place(
          pos: (1, 1, 1),
          below: (controller: origin, width: 2, height: 1),
          above: null,
          tanks: {...layer(origin), const (1, 1, 1)},
          blocked: const {(0, 1, 1)},
        ),
        isNull,
      );
    });
  });

  test('a tank both below and above is extended from the lower one', () {
    // A one-block gap between two tanks: the placed event carries no face, so the tank below
    // wins (Java would follow the clicked face).
    final targets = place(
      pos: (0, 1, 0),
      below: (controller: origin, width: 2, height: 1),
      above: (controller: (0, 2, 0), width: 2, height: 1),
      tanks: {
        ...layer(origin),
        ...layer(origin, y: 2),
        const (0, 1, 0),
      },
    );

    expect(targets, const [(0, 1, 1), (1, 1, 0), (1, 1, 1)]);
  });
}
