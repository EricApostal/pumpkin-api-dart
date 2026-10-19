// Pure rules of the item transfer path: which unpacking handler a target block gets, and how the
// default handler decides whether a package's contents fit (the simulate pass of
// `PackagerBlockEntity.unwrapBox`).
import 'package:create/src/logistics/model/inventory.dart';
import 'package:create/src/logistics/model/orders.dart';
import 'package:create/src/logistics/model/stack.dart';
import 'package:create/src/logistics/packager/unpacking.dart';
import 'package:test/test.dart';

MemoryInv _inv(int slots, {int limit = 64}) =>
    MemoryInv(slots, limit: limit, validator: (slot, stack) => true);

final class _ProbeHandler implements UnpackingHandler {
  const _ProbeHandler();

  @override
  Future<bool> unpack(
    ItemInv target,
    List<LStack> items, {
    required bool simulate,
    UnpackTarget? where,
  }) async => true;
}

void main() {
  group('unpacking handler selection', () {
    test('registered blocks get their own handler', () {
      expect(
        UnpackingHandlers.of('create:creative_crate'),
        same(UnpackingHandlers.voiding),
      );
      // The handlers that need the target block entity register on module load.
      const probe = _ProbeHandler();
      UnpackingHandlers.register('create:basin', probe);
      expect(UnpackingHandlers.of('create:basin'), same(probe));
    });

    test('everything else falls back to the default handler', () {
      expect(
        UnpackingHandlers.of('minecraft:chest'),
        same(UnpackingHandlers.defaultHandler),
      );
      expect(
        UnpackingHandlers.of('create:item_vault'),
        same(UnpackingHandlers.defaultHandler),
      );
    });
  });

  group('default unpacking', () {
    test('a box that fits completely is accepted', () async {
      final inv = _inv(2);
      final items = [LStack.of('minecraft:stone', 64), LStack.of('minecraft:dirt', 32)];
      expect(
        await UnpackingHandlers.defaultHandler.unpack(inv, items, simulate: true),
        isTrue,
      );
      // The simulate pass reports the leftover in the list it was given.
      expect(items.every((s) => s.isEmpty), isTrue);
      // Nothing was written.
      expect(inv.at(0).isEmpty, isTrue);
      expect(inv.at(1).isEmpty, isTrue);
    });

    test('a box with an item that does not fit is rejected', () async {
      final inv = _inv(1);
      final items = [LStack.of('minecraft:stone', 64), LStack.of('minecraft:dirt', 64)];
      expect(
        await UnpackingHandlers.defaultHandler.unpack(inv, items, simulate: true),
        isFalse,
      );
    });

    test('partial space in a matching slot is filled, the rest does not fit', () async {
      final inv = _inv(1)..stacks[0] = LStack.of('minecraft:stone', 48);
      final items = [LStack.of('minecraft:stone', 32)];
      expect(
        await UnpackingHandlers.defaultHandler.unpack(inv, items, simulate: true),
        isFalse,
      );
      expect(items.single.count, 16);
    });

    test('the real pass inserts stacked and reports success', () async {
      final inv = _inv(2);
      final items = [LStack.of('minecraft:stone', 64), LStack.of('minecraft:dirt', 32)];
      expect(
        await UnpackingHandlers.defaultHandler.unpack(inv, items, simulate: false),
        isTrue,
      );
      expect(inv.at(0).count, 64);
      expect(inv.at(1).key, 'minecraft:dirt');
      expect(inv.at(1).count, 32);
    });
  });

  group('order context', () {
    test('a single recipe is the crafting information', () {
      final order = PackageOrderWithCrafts.singleRecipe([
        BigStack(LStack.of('minecraft:oak_planks', 1), 4),
      ]);
      expect(PackageOrderWithCrafts.hasCraftingInformation(order), isTrue);
      expect(order.craftingInformation.single.count, 4);
    });

    test('no crafts means no crafting information', () {
      final order = PackageOrderWithCrafts.simple([
        BigStack(LStack.of('minecraft:stone', 1), 1),
      ]);
      expect(PackageOrderWithCrafts.hasCraftingInformation(order), isFalse);
      expect(PackageOrderWithCrafts.hasCraftingInformation(null), isFalse);
    });
  });
}
