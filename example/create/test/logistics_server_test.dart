// Pure server logic of the logistics module: comparator outputs, package port targets, the
// requester's stored order and the chunking of stock responses.
import 'package:create/src/logistics/model/inventory.dart';
import 'package:create/src/logistics/model/orders.dart';
import 'package:create/src/logistics/model/package.dart';
import 'package:create/src/logistics/model/stack.dart';
import 'package:create/src/logistics/model/stack_wire.dart';
import 'package:create/src/logistics/port/conveyance_items.dart';
import 'package:create/src/logistics/port/package_port_target.dart';
import 'package:create/src/logistics/requester/auto_request_data.dart';
import 'package:create/src/protocol/item_stack.dart';
import 'package:test/test.dart';

StackWire _wire() => StackWire(
  items: ItemIdResolver.vanilla(),
  componentIdOf: (_) => null,
  componentNameOf: (_) => null,
);

void main() {
  group('comparator output', () {
    test('an empty inventory has no signal', () {
      expect(calcRedstoneFromInventory(const []), 0);
      expect(calcRedstoneFromInventory(List.filled(18, LStack.empty)), 0);
    });

    test('a single filled slot still gives one', () {
      final slots = List<LStack>.filled(18, LStack.empty);
      slots[0] = LStack.of('minecraft:stone', 64);
      expect(calcRedstoneFromInventory(slots), 1);
    });

    test('a completely full inventory gives fifteen', () {
      final slots = List<LStack>.filled(18, LStack.of('minecraft:stone', 64));
      expect(calcRedstoneFromInventory(slots), 15);
    });

    test('slots with a zero limit do not count', () {
      expect(
        calcRedstoneFromInventory([
          LStack.of('minecraft:stone', 64),
        ], slotLimit: 0),
        0,
      );
    });
  });

  group('package port targets', () {
    test('chain conveyor targets round trip and only support frogports', () {
      const target = PackagePortTarget(
        PackagePortTargetType.chainConveyor,
        (2, 0, -1),
        chainPos: 0.25,
        connection: (0, 0, 1),
        flipped: true,
      );
      final decoded = PackagePortTarget.fromMap(target.toMap());
      expect(decoded, isNotNull);
      expect(decoded!.type, PackagePortTargetType.chainConveyor);
      expect(decoded.relativePos, (2, 0, -1));
      expect(decoded.chainPos, 0.25);
      expect(decoded.connection, (0, 0, 1));
      expect(decoded.flipped, isTrue);
      expect(decoded.canSupport('create:package_frogport'), isTrue);
      expect(decoded.canSupport('create:white_postbox'), isFalse);
    });

    test('train station targets only support postboxes', () {
      const target = PackagePortTarget(PackagePortTargetType.trainStation, (
        0,
        3,
        0,
      ));
      expect(target.canSupport('create:white_postbox'), isTrue);
      expect(target.canSupport('create:package_frogport'), isFalse);
    });

    test('an unknown target type is rejected', () {
      expect(PackagePortTarget.fromMap({'type': 'other'}), isNull);
    });
  });

  group('auto request data', () {
    test('the order and address survive the stream encoding', () {
      final order = PackageOrderWithCrafts.simple([
        BigStack(LStack.of('minecraft:stone'), 5),
        BigStack(LStack.of('minecraft:iron_ingot'), 2),
      ]);
      final data = AutoRequestData(
        order,
        'factory/1',
        (12, 65, -3),
        'minecraft:overworld',
        true,
      );
      final wire = _wire();
      final decoded = AutoRequestData.decode(data.encode(wire), wire);
      expect(decoded, isNotNull);
      expect(decoded!.encodedTargetAddress, 'factory/1');
      expect(decoded.targetOffset, (12, 65, -3));
      expect(decoded.targetDim, 'minecraft:overworld');
      expect(decoded.isValid, isTrue);
      expect(decoded.encodedRequest.stacks, hasLength(2));
      expect(decoded.encodedRequest.stacks.first.count, 5);
    });

    test('writeToItem offsets by the placement position', () {
      final data = AutoRequestData(
        PackageOrderWithCrafts.empty(),
        'main',
        (2, 3, 4),
        'minecraft:overworld',
        false,
      );
      final written = data.writeToItem((10, 20, 30));
      expect(written.targetOffset, (12, 23, 34));

      final read = written.readFromItem((10, 20, 30), 'minecraft:overworld');
      expect(read.targetOffset, (2, 3, 4));
      expect(read.isValid, isTrue);
      expect(read.targetPos((10, 20, 30)), (12, 23, 34));
    });
  });

  group('conveyance conversion', () {
    test('a package keeps its address and contents', () {
      final wire = _wire();
      var box = PackageItem.addAddress(PackageStyles.defaultBox(), 'factory/1');
      box = PackageItem.withContents(box, [
        LStack.of('minecraft:stone', 7),
        LStack.of('minecraft:iron_ingot', 2),
      ]);

      final value = toItemValue(box, wire);
      expect(value.key, box.key);
      expect(value.count, box.count);

      final back = fromItemValue(value, wire);
      expect(PackageItem.getAddress(back), 'factory/1');
      final contents = PackageItem.contentsList(back);
      expect(contents, hasLength(2));
      expect(contents.firstWhere((s) => s.key == 'minecraft:stone').count, 7);
    });

    test('a plain stack keeps its components', () {
      final wire = _wire();
      final stack = LStack.of(
        'minecraft:stone',
        3,
      ).withComp('create:filter_items_respect_nbt', [1]);
      final back = fromItemValue(toItemValue(stack, wire), wire);
      expect(back.key, 'minecraft:stone');
      expect(back.count, 3);
      expect(back.compBytes('create:filter_items_respect_nbt'), [1]);
    });
  });

  group('stock response chunking', () {
    test('an empty summary is one final empty chunk', () {
      final chunks = InventorySummary().divideForResponse();
      expect(chunks, hasLength(1));
      expect(chunks.single.$1, isTrue);
      expect(chunks.single.$2, isEmpty);
    });

    test('more than a hundred entries split with only the last final', () {
      final summary = InventorySummary();
      for (var i = 0; i < 250; i++) {
        summary.add(LStack.of('minecraft:stone', 1), i + 1);
      }
      // Distinct item keys collapse into one entry per item, so use distinct keys.
      final distinct = InventorySummary();
      for (var i = 0; i < 250; i++) {
        distinct.add(LStack.of('test:item_$i'), 1);
      }
      expect(summary.getStacks(), hasLength(1));

      final chunks = distinct.divideForResponse();
      expect(chunks, hasLength(3));
      expect(chunks[0].$1, isFalse);
      expect(chunks[0].$2, hasLength(100));
      expect(chunks[1].$1, isFalse);
      expect(chunks[1].$2, hasLength(100));
      expect(chunks[2].$1, isTrue);
      expect(chunks[2].$2, hasLength(50));
    });
  });
}
