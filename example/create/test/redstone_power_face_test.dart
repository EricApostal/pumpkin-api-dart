// The redstone power event convention: the host hands a custom block `e.face`, the side of the
// block that touches the reader, while vanilla `getSignal`/`getDirectSignal` receive the side of
// the reader. The two are opposite; every handler that compares a state direction against the
// vanilla `side` must go through [powerEventSide].
//
// Evidence for the convention:
//  * the host, `dynamic.rs` (`redstone_power`): `let face = args.direction.opposite();`, and that
//    same `face` is both passed to `plugin_redstone.face_power(...)` and put in the
//    `CustomBlockRedstonePowerEvent`; `redstone/mod.rs` passes the neighbour `side` as
//    `args.direction`;
//  * the host API doc of `setBlockRedstoneOutputFace` (`bindings.g.dart`): "the side of the
//    block that touches the neighbour";
//  * three faithful vanilla ports that read the same event field: `lever.rs`,
//    `abstract_redstone_gate.rs` and `lectern.rs` all compare `get_direction()`/`get_facing()`
//    with `args.direction` directly, i.e. with the side the power is read from.
import 'package:create/src/api/observable.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/conveyance/belt/transported_item.dart';
import 'package:create/src/conveyance/behaviours/belt_interfaces.dart';
import 'package:create/src/conveyance/items/item_data.dart';
import 'package:create/src/conveyance/observable_probes.dart';
import 'package:create/src/redstone/lamp_logic.dart';
import 'package:create/src/redstone/power_face.dart';
import 'package:test/test.dart';

/// A belt segment: the item handler the probe reads.
class _FakeBelt implements TransportedItemStackHandler {
  final List<TransportedItemStack> items = [];

  @override
  void handleCenteredProcessingOnAllItems(
    double maxDistanceFromCenter,
    ItemProcessor processFunction,
  ) {
    for (final item in items) {
      processFunction(item);
    }
  }

  @override
  void handleProcessingOnAllItems(ItemProcessor processFunction) =>
      handleCenteredProcessingOnAllItems(.51, processFunction);

  @override
  void handleProcessingOnItem(TransportedItemStack item, TransportedResult result) {}

  @override
  Vec3 getWorldPositionOf(TransportedItemStack transported) => (0.0, 0.0, 0.0);
}

/// The filter the observer applies.
class _Filter implements ObserverFilter {
  _Filter(this.key);

  final String? key;

  @override
  bool get isEmpty => key == null;

  @override
  bool testItem(String itemKey) => key == null || key == itemKey;

  @override
  bool testFluid(String fluidKey) => key == null || key == fluidKey;
}

void main() {
  group('power event side', () {
    test('the vanilla side is the side of the reader, opposite the block face', () {
      for (final face in Direction.values) {
        expect(
          powerEventSide(face),
          face.opposite,
          reason: 'e.face touches the reader, vanilla `side` points back at it',
        );
      }
    });

    test('a reader on the north face asks with the south side', () {
      // The reader sits north of the block, so the block face touching it is north and the
      // reader's own side of the block is south.
      expect(powerEventSide(Direction.north), Direction.south);
      expect(powerEventSide(Direction.down), Direction.up);
    });
  });

  group('redstone contact getSignal', () {
    // `RedstoneContactBlock.java:132`: `POWERED && side != FACING.getOpposite() ? 15 : 0`, where
    // vanilla's `side` is the direction from the reader to the contact and `e.face` is the
    // direction from the contact to the reader.
    const facing = Direction.north;

    test('powers the exposed face, not the face it is mounted on', () {
      // The mount (the block the contact was clicked against) is to the north, so the exposed
      // face is the south one. A reader south of the contact reads that face: e.face = south.
      expect(
        redstoneContactSignal(
          powered: true,
          facing: facing,
          side: powerEventSide(Direction.south),
        ),
        15,
        reason: 'the exposed face powers',
      );
      // A reader north of the contact (the mount side): e.face = north.
      expect(
        redstoneContactSignal(
          powered: true,
          facing: facing,
          side: powerEventSide(Direction.north),
        ),
        0,
        reason: 'the mount is never powered',
      );
    });

    test('the reading is inverted if e.face is passed through raw', () {
      // What the broken code did: `side: e.face`. The exposed face then gets nothing and the
      // mount is powered, the exact inversion this test pins down.
      expect(redstoneContactSignal(powered: true, facing: facing, side: Direction.south), 0);
      expect(redstoneContactSignal(powered: true, facing: facing, side: Direction.north), 15);
    });
  });

  group('sites that compare a state direction with the vanilla side', () {
    // Desk bell `getDirectSignal`: `getConnectedDirection(state) == side`, and the bell's
    // connected direction is its `facing` (`DeskBellBlock.java:123`).
    bool deskBellDirectSignal(Direction facing, Direction eventFace) =>
        facing == powerEventSide(eventFace);

    // Smart observer `getSignal` (`SmartObserverBlock.java:102`): nothing towards the side
    // opposite the observed block.
    int observerSignal(Direction target, Direction eventFace) =>
        powerEventSide(eventFace) != target.opposite ? 15 : 0;

    // Threshold switch `getSignal` (`ThresholdSwitchBlock.java:66`).
    int thresholdSignal(Direction target, Direction eventFace) =>
        powerEventSide(eventFace) == target.opposite ? 0 : 15;

    // Redstone link `getDirectSignal` (`RedstoneLinkBlock.java:145`): `side != FACING`.
    bool linkDirectSignal(Direction facing, Direction eventFace) =>
        powerEventSide(eventFace) == facing;

    // `LecternBlock.getDirectSignal` (`LecternBlock.java:185`): `direction == UP`.
    bool lecternDirectSignal(Direction eventFace) => powerEventSide(eventFace) == Direction.up;

    test('the desk bell answers the side it is connected to', () {
      // Java: `getConnectedDirection(state) == side`. `side` is the direction from the reader to
      // the bell, so the bell answers a reader on the side `FACING` points away from: e.face is
      // `FACING.getOpposite()`.
      expect(deskBellDirectSignal(Direction.north, Direction.south), isTrue);
      expect(deskBellDirectSignal(Direction.north, Direction.north), isFalse);
    });

    test('the observer gives nothing towards the observed block', () {
      const target = Direction.north;
      // The observer looks north: the block it watches is on its north side, so a reader there
      // reads the observer's north face (e.face = north) and must get nothing.
      expect(observerSignal(target, Direction.north), 0);
      // Any other reader is powered, e.g. one behind the observer (e.face = south).
      expect(observerSignal(target, Direction.south), 15);
      expect(observerSignal(target, Direction.up), 15);
    });

    test('the threshold switch gives nothing towards the observed block', () {
      const target = Direction.north;
      expect(thresholdSignal(target, Direction.north), 0);
      expect(thresholdSignal(target, Direction.south), 15);
    });

    test('the redstone link gives strong power only towards its facing', () {
      // Java: `side != FACING -> 0`; `side` is the direction from the reader to the link, so the
      // link's `e.face` towards that reader is `FACING.getOpposite()`.
      expect(linkDirectSignal(Direction.west, Direction.east), isTrue);
      expect(linkDirectSignal(Direction.west, Direction.west), isFalse);
    });

    test('the lectern controller gives strong power on the vanilla UP side only', () {
      // `LecternBlock.getDirectSignal`: `direction == Direction.UP`, and `direction` is the
      // direction from the reader to the lectern, so the lectern's face towards that reader is
      // its down face.
      expect(lecternDirectSignal(Direction.down), isTrue);
      expect(lecternDirectSignal(Direction.up), isFalse);
      expect(lecternDirectSignal(Direction.north), isFalse);
    });
  });

  group('observable probes', () {
    test('an observer sees the item on a belt it faces', () {
      final belt = _FakeBelt()..items.add(TransportedItemStack(const ItemValue('minecraft:iron_ingot', 1)));
      final probe = BeltObservableProbe(lookup: (worldId, pos) => belt);
      const pos = (0, 0, 0);

      expect(probe.canObserve('minecraft:overworld', pos), isTrue);
      expect(probe.detect('minecraft:overworld', pos, _Filter('minecraft:iron_ingot')), isTrue);
      expect(probe.detect('minecraft:overworld', pos, _Filter('minecraft:gold_ingot')), isFalse);
      // No filter accepts anything on the belt.
      expect(probe.detect('minecraft:overworld', pos, _Filter(null)), isTrue);
    });

    test('an empty belt does not power the observer', () {
      final belt = _FakeBelt();
      final probe = BeltObservableProbe(lookup: (worldId, pos) => belt);
      expect(probe.detect('minecraft:overworld', const (0, 0, 0), _Filter(null)), isFalse);
    });

    test('a block that is not a belt is not handled by the belt probe', () {
      final probe = BeltObservableProbe(lookup: (worldId, pos) => null);
      expect(probe.detect('minecraft:overworld', const (0, 0, 0), _Filter(null)), isNull);
      expect(probe.canObserve('minecraft:overworld', const (0, 0, 0)), isFalse);
    });
  });
}
