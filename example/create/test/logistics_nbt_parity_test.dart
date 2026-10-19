// Pure parity tests for the logistics wire/NBT names. Host NBT (`NbtCompound`) cannot be loaded by
// `dart test`, so these cover the pure models and the JSON maps whose keys must match the Java
// codecs (`PackageOrder.CODEC`, `PackageOrderWithCrafts.CODEC`, `PackageItem.PackageOrderData`,
// `BigItemStack.CODEC`, `RequestPromise.CODEC`, `AutoRequestData.CODEC`, `PackagePortTarget.CODEC`)
// and the package data component names.
import 'package:create/src/logistics/model/network.dart';
import 'package:create/src/logistics/model/orders.dart';
import 'package:create/src/logistics/model/package.dart';
import 'package:create/src/logistics/model/stack.dart';
import 'package:create/src/logistics/port/package_port_target.dart';
import 'package:create/src/logistics/requester/auto_request_data.dart';
import 'package:test/test.dart';

void main() {
  group('package data components', () {
    test('the names match AllDataComponents', () {
      expect(PackageComponents.address, 'create:package_address');
      expect(PackageComponents.contents, 'create:package_contents');
      expect(PackageComponents.orderData, 'create:package_order_data');
      expect(PackageComponents.orderContext, 'create:package_order_context');
      // The order is the JSON of the mappable models; only these four are logical.
      expect(PackageComponents.logical, [
        PackageComponents.contents,
        PackageComponents.address,
        PackageComponents.orderData,
        PackageComponents.orderContext,
      ]);
    });

    test('contents round trip through the nine item container slots', () {
      var box = PackageStyles.defaultBox();
      box = PackageItem.withContents(box, [
        LStack.of('minecraft:stone', 12),
        LStack.empty,
        LStack.of('minecraft:iron_ingot', 3),
      ]);
      final contents = PackageItem.getContents(box);
      expect(contents.slots, PackageItem.slots);
      expect(contents.at(0).key, 'minecraft:stone');
      expect(contents.at(0).count, 12);
      expect(contents.at(1).isEmpty, isTrue);
      expect(contents.at(2).key, 'minecraft:iron_ingot');
      expect(contents.at(2).count, 3);
    });
  });

  group('order models', () {
    test('BigStack uses the Java CODEC keys', () {
      final entry = BigStack(LStack.of('minecraft:stone', 1), 7);
      expect(entry.toMap().keys.toSet(), {'item_stack', 'count'});
      expect(entry.toMap()['count'], 7);
      final decoded = BigStackMapper.fromMap(entry.toMap());
      expect(decoded.count, 7);
      expect(decoded.stack.key, 'minecraft:stone');
    });

    test('PackageOrder uses the entries key', () {
      final order = PackageOrder([BigStack(LStack.of('minecraft:stone'), 4)]);
      expect(order.toMap().keys.toSet(), {'entries'});
      expect(PackageOrderMapper.fromMap(order.toMap()).stacks.single.count, 4);
    });

    test('PackageOrderWithCrafts uses ordered_stacks and ordered_crafts', () {
      final order = PackageOrderWithCrafts(
        PackageOrder([BigStack(LStack.of('minecraft:stone'), 4)]),
        [
          CraftingEntry(
            PackageOrder([BigStack(LStack.of('minecraft:stone'), 1)]),
            2,
          ),
        ],
      );
      expect(order.toMap().keys.toSet(), {'ordered_stacks', 'ordered_crafts'});
      final craft = (order.toMap()['ordered_crafts'] as List).single as Map;
      expect(craft.keys.toSet(), {'pattern', 'count'});
      final decoded = PackageOrderWithCraftsMapper.fromMap(order.toMap());
      expect(decoded.orderedCrafts.single.count, 2);
      expect(decoded.orderedCrafts.single.pattern.stacks.single.count, 1);
    });

    test('the legacy order context is still decoded', () {
      final legacy = PackageOrderWithCrafts.decode({
        'entries': [BigStack(LStack.of('minecraft:stone'), 6).toMap()],
      });
      expect(legacy.orderedStacks.stacks.single.count, 6);
      expect(legacy.orderedCrafts, isEmpty);
    });
  });

  group('PackageOrderData', () {
    test('uses the Java CODEC field names and round trips', () {
      final context = PackageOrderWithCrafts.simple([
        BigStack(LStack.of('minecraft:iron_ingot'), 9),
      ]);
      const data = PackageOrderData(7, 1, true, 2, false);
      final withContext = PackageOrderData(7, 1, true, 2, false, context);
      final map = withContext.toMap();
      expect(map.keys.toSet(), {
        'order_id',
        'link_index',
        'is_final_link',
        'fragment_index',
        'is_final',
        'order_context',
      });
      expect(map['order_id'], 7);
      expect(map['is_final_link'], true);

      final decoded = PackageOrderDataMapper.fromJson(withContext.toJson());
      expect(decoded.orderId, 7);
      expect(decoded.linkIndex, 1);
      expect(decoded.isFinalLink, isTrue);
      expect(decoded.fragmentIndex, 2);
      expect(decoded.isFinal, isFalse);
      expect(decoded.orderContext?.stacks.single.count, 9);

      // A context-free order data has no context (the host NBT writer omits the key entirely).
      expect(data.toMap()['order_context'], isNull);
    });
  });

  group('RequestPromise', () {
    test('uses the Java CODEC field names', () {
      final promise = RequestPromise(
        BigStack(LStack.of('minecraft:stone'), 5),
        12,
      );
      final map = promise.toMap();
      expect(map.keys.toSet(), {'ticks_existed', 'promised_stack'});
      expect(map['ticks_existed'], 12);
      final decoded = RequestPromiseMapper.fromMap(map);
      expect(decoded.ticksExisted, 12);
      expect(decoded.promisedStack.count, 5);
    });
  });

  group('AutoRequestData', () {
    test('uses the Java CODEC field names', () {
      final data = AutoRequestData(
        PackageOrderWithCrafts.simple([
          BigStack(LStack.of('minecraft:stone'), 2),
        ]),
        'factory/1',
        (3, -4, 5),
        'minecraft:overworld',
        true,
      );
      final map = data.toMap();
      expect(map.keys.toSet(), {
        'encoded_request',
        'encoded_target_address',
        'target_offset',
        'target_dim',
        'is_valid',
      });
      final decoded = AutoRequestData.fromMap(map);
      expect(decoded.encodedTargetAddress, 'factory/1');
      expect(decoded.targetOffset, (3, -4, 5));
      expect(decoded.targetDim, 'minecraft:overworld');
      expect(decoded.isValid, isTrue);
      expect(decoded.encodedRequest.stacks.single.count, 2);
    });
  });

  group('PackagePortTarget', () {
    test('uses the Java CODEC field names and type ids', () {
      const target = PackagePortTarget(
        PackagePortTargetType.chainConveyor,
        (2, 0, -1),
        chainPos: 0.25,
        connection: (0, 0, 1),
        flipped: true,
      );
      final map = target.toMap();
      expect(map.keys.toSet(), {
        'type',
        'relative_pos',
        'chain_pos',
        'connection',
        'flipped',
      });
      expect(map['type'], 'create:chain_conveyor');

      final decoded = PackagePortTarget.fromMap(map);
      expect(decoded, isNotNull);
      expect(decoded!.type, PackagePortTargetType.chainConveyor);
      expect(decoded.relativePos, (2, 0, -1));
      expect(decoded.chainPos, 0.25);
      expect(decoded.connection, (0, 0, 1));
      expect(decoded.flipped, isTrue);
    });

    test('the train station target only stores its relative position', () {
      const target = PackagePortTarget(PackagePortTargetType.trainStation, (
        0,
        3,
        0,
      ));
      final map = target.toMap();
      expect(map['type'], 'create:train_station');
      expect(map.containsKey('flipped'), isFalse);
      expect(PackagePortTarget.fromMap(map)!.relativePos, (0, 3, 0));
    });

    test('the old camelCase private form is still read', () {
      final decoded = PackagePortTarget.fromMap({
        'type': 'chain_conveyor',
        'relativePos': [1, 2, 3],
        'chainPos': 0.5,
        'connection': null,
        'flipped': false,
      });
      expect(decoded!.relativePos, (1, 2, 3));
      expect(decoded.chainPos, 0.5);
    });
  });
}
