import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/processing/arm/arm_model.dart';
import 'package:create/src/processing/common/stack.dart';
import 'package:create/src/processing/crafter/crafter_model.dart';
import 'package:create/src/processing/crafter/crafter_recipe.dart';
import 'package:create/src/processing/deployer/deployer_item_handler.dart';
import 'package:create/src/processing/recipe/ingredient.dart';
import 'package:create/src/processing/recipe/output.dart';
import 'package:create/src/processing/recipe/recipe.dart';
import 'package:test/test.dart';

/// A crafter node for the chain tests.
final class _FakeCrafter implements CrafterNode {
  @override
  final Pos crafterPos;
  @override
  final BState crafterState;
  @override
  ConnectedInput input = ConnectedInput();
  @override
  CrafterPhase phase = CrafterPhase.idle;
  @override
  bool hasCraftingItem = false;
  bool began = false;
  bool ejected = false;

  _FakeCrafter(
    this.crafterPos, {
    String facing = 'north',
    String pointing = 'up',
  }) : crafterState = BState(crafterBlockKey, {
         'facing': facing,
         'pointing': pointing,
       });

  @override
  bool get hasCraftingItemOrCover => hasCraftingItem;

  @override
  void begin() => began = true;

  @override
  void continueIfAllPrecedingFinished() {}

  @override
  void eject() => ejected = true;
}

final class _FakeWorld implements CrafterWorld {
  final Map<Pos, _FakeCrafter> crafters;

  _FakeWorld(this.crafters);

  @override
  BState stateAt(Pos pos) => crafters[pos]?.crafterState ?? BState.air;

  @override
  bool isLoaded(Pos pos) => true;

  @override
  CrafterNode? crafterAt(Pos pos) => crafters[pos];
}

const _tags = MapTagLookup();

MechanicalCraftingRecipe _recipe({bool mirrored = false}) =>
    MechanicalCraftingRecipe(
      id: 'test:recipe',
      pattern: const ['XX', 'X '],
      key: const {'X': Ingredient.item('minecraft:iron_ingot')},
      result: const ProcessingOutput('minecraft:iron_block'),
      acceptMirrored: mirrored,
    );

void main() {
  group('mechanical crafter grid', () {
    test('mergeOnto shifts towards the pointing', () {
      final source = GroupedItems.single(
        const PStack('minecraft:iron_ingot', 1),
      );
      final target = GroupedItems();

      source.mergeOnto(target, CrafterPointing.left);

      expect(target.grid[(1, 0)]?.key, 'minecraft:iron_ingot');
      expect(target.onlyEmptyItems, isFalse);
    });

    test('crafting input uses the top row first', () {
      final items = GroupedItems({
        (0, 0): const PStack('minecraft:iron_ingot', 1),
        (0, 1): const PStack('minecraft:stone', 1),
        (1, 1): const PStack('minecraft:stone', 1),
      });

      final input = craftingInputOf(items);

      expect(input.width, 2);
      expect(input.height, 2);
      // Row 0 is the largest y.
      expect(input.cellAt(0, 0).key, 'minecraft:stone');
      expect(input.cellAt(1, 0).key, 'minecraft:stone');
      expect(input.cellAt(0, 1).key, 'minecraft:iron_ingot');
      expect(input.cellAt(1, 1).isEmpty, isTrue);
      expect(input.rows, [
        ['minecraft:stone', 'minecraft:stone'],
        ['minecraft:iron_ingot', null],
      ]);
    });

    test('mechanical recipe matches the pattern', () {
      final items = GroupedItems({
        (0, 1): const PStack('minecraft:iron_ingot', 1),
        (1, 1): const PStack('minecraft:iron_ingot', 1),
        (0, 0): const PStack('minecraft:iron_ingot', 1),
      });

      expect(mechanicalCraftingMatches(_recipe(), items, _tags), isTrue);
    });

    test('mirroring is only accepted when the recipe allows it', () {
      // The pattern mirrored horizontally: ['XX', ' X'].
      final items = GroupedItems({
        (0, 1): const PStack('minecraft:iron_ingot', 1),
        (1, 1): const PStack('minecraft:iron_ingot', 1),
        (1, 0): const PStack('minecraft:iron_ingot', 1),
      });

      expect(mechanicalCraftingMatches(_recipe(), items, _tags), isFalse);
      expect(
        mechanicalCraftingMatches(_recipe(mirrored: true), items, _tags),
        isTrue,
      );
    });

    test('a wrong item does not match', () {
      final items = GroupedItems({
        (0, 1): const PStack('minecraft:iron_ingot', 1),
        (1, 1): const PStack('minecraft:stone', 1),
        (0, 0): const PStack('minecraft:iron_ingot', 1),
      });

      expect(mechanicalCraftingMatches(_recipe(), items, _tags), isFalse);
    });
  });

  group('mechanical crafter chain', () {
    test('the target direction follows the pointing', () {
      expect(
        crafterTargetDirection(
          BState(crafterBlockKey, {'facing': 'north', 'pointing': 'up'}),
        ),
        Direction.up,
      );
      expect(
        crafterTargetDirection(
          BState(crafterBlockKey, {'facing': 'north', 'pointing': 'down'}),
        ),
        Direction.down,
      );
    });

    test('a crafter points at the crafter above it', () {
      final a = _FakeCrafter((0, 0, 0));
      final b = _FakeCrafter((0, 1, 0));
      final world = _FakeWorld({a.crafterPos: a, b.crafterPos: b});

      expect(targetingCrafter(world, a), same(b));
      expect(precedingCrafters(world, b).single, same(a));
      expect(allCraftersOfChainIf(world, a, (_) => true), [a, b]);
    });

    test('a chain of all empty crafters is refused', () {
      final a = _FakeCrafter((0, 0, 0));
      final b = _FakeCrafter((0, 1, 0));
      final world = _FakeWorld({a.crafterPos: a, b.crafterPos: b});

      expect(allCraftersOfChainIf(world, a, (n) => n.hasCraftingItem), isNull);

      a.hasCraftingItem = true;
      expect(allCraftersOfChainIf(world, a, (n) => n.hasCraftingItem), isNull);

      b.hasCraftingItem = true;
      expect(allCraftersOfChainIf(world, a, (n) => n.hasCraftingItem), [a, b]);
    });
  });

  group('deployer item handler', () {
    test('the last slot is the held item', () {
      final overflow = <PStack>[const PStack('minecraft:stone', 3)];
      var held = const PStack('minecraft:iron_ingot', 2);
      final handler = DeployerItemHandler(
        overflow: overflow,
        getHeld: () => held,
        setHeld: (stack) => held = stack,
        validator: (_) => true,
        onChanged: () {},
      );

      expect(handler.slots, 2);
      expect(handler.stackIn(0).key, 'minecraft:stone');
      expect(handler.stackIn(1).key, 'minecraft:iron_ingot');

      final remainder = handler.insert(
        1,
        const PStack('minecraft:iron_ingot', 5),
      );
      expect(remainder.isEmpty, isTrue);
      expect(held.count, 7);

      final taken = handler.extract(0, 2);
      expect(taken.count, 2);
      expect(overflow.single.count, 1);
    });

    test('an empty hand takes a whole stack', () {
      var held = PStack.empty;
      final handler = DeployerItemHandler(
        overflow: [],
        getHeld: () => held,
        setHeld: (stack) => held = stack,
        validator: (_) => true,
        onChanged: () {},
      );

      final remainder = handler.insert(0, const PStack('minecraft:stone', 100));
      expect(held.count, 64);
      expect(remainder.count, 36);
    });

    test('the filter refuses items', () {
      var held = PStack.empty;
      final handler = DeployerItemHandler(
        overflow: [],
        getHeld: () => held,
        setHeld: (stack) => held = stack,
        validator: (stack) => stack.key == 'minecraft:stone',
        onChanged: () {},
      );

      expect(handler.insert(0, const PStack('minecraft:dirt', 1)).count, 1);
      expect(held.isEmpty, isTrue);
    });
  });

  group('arm selection', () {
    test('round robin continues after the last index', () {
      expect(armScanStart(ArmSelectionMode.roundRobin, 1), 2);
      expect(armScanStart(ArmSelectionMode.forcedRoundRobin, 1), 2);
      expect(armScanStart(ArmSelectionMode.preferFirst, 1), 0);
    });

    test('forced round robin scans one index, the others scan all', () {
      expect(armScanRange(ArmSelectionMode.forcedRoundRobin, 1, 5), 3);
      expect(armScanRange(ArmSelectionMode.roundRobin, 1, 5), 5);
      expect(armScanRange(ArmSelectionMode.forcedRoundRobin, 4, 5), 5);
    });

    test('modes cycle between deposit and take', () {
      expect(ArmPointMode.deposit.cycled, ArmPointMode.take);
      expect(ArmPointMode.take.cycled, ArmPointMode.deposit);
      expect(ArmPointMode.fromJavaName('TAKE'), ArmPointMode.take);
      expect(ArmPointMode.fromJavaName('DEPOSIT'), ArmPointMode.deposit);
    });
  });
}
