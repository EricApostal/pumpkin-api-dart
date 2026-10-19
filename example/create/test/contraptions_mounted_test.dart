// The cart assembler's outline: `AllShapes.CART_ASSEMBLER` per rail axis, and the shape rules
// that select it, plus the collision shape it gives an entity and the structure
// `MountedContraption` captures from it.
//
// The registered collision shape is the full cube (`CartAssemblerBlock.getCollisionShape`
// without an entity context); the per-entity answer comes from `cartAssemblerCollisionBoxes` and
// needs the host's `entity-collision-shape` hook.
import 'package:pumpkin_api/pumpkin_api_core.dart'
    show BlockBox, BlockShape, BoxesShape;
import 'package:test/test.dart';

import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/core/level.dart';
import 'package:create/src/contraptions/core/structure_info.dart';
import 'package:create/src/contraptions/mounted/mounted_contraption.dart';
import 'package:create/src/contraptions/mounted/mounted_shapes.dart';

/// The boxes of [shape], empty for the shapes that are not a box list.
List<BlockBox> boxesOf(BlockShape shape) =>
    shape is BoxesShape ? shape.boxes : const [];

/// A level over a map of states, with the carts that sit on it.
final class _MapLevel extends ContraptionLevel {
  final Map<Pos, BState> blocks;
  final Map<Pos, List<MinecartRef>> carts;

  _MapLevel(this.blocks, [this.carts = const {}]);

  @override
  String get worldId => 'test:world';

  @override
  ContraptionSettings get settings => DefaultContraptionSettings();

  @override
  BState stateAt(Pos p) => blocks[p] ?? BState.air;

  @override
  bool isLoaded(Pos p) => true;

  @override
  bool isFaceSturdy(Pos p, Direction face) => !stateCollisionEmpty(stateAt(p));

  @override
  List<BlockBox> collisionBoxes(Pos p) => stateCollisionBoxes(stateAt(p));

  @override
  bool supportShapeEmpty(Pos p) => stateCollisionEmpty(stateAt(p));

  @override
  bool canBeReplaced(Pos p) => stateReplaceable(stateAt(p));

  @override
  bool hasTag(Pos p, String tag) => false;

  @override
  bool isWater(Pos p) => false;

  @override
  bool isOutsideBuildHeight(Pos p) => false;

  @override
  int get minY => -64;

  @override
  CapturedBlockEntity? blockEntityAt(Pos p) => null;

  @override
  PushReaction pushReaction(BState state) => PushReaction.normal;

  @override
  bool isUnbreakable(BState state) => false;

  @override
  bool stateHasTag(BState state, String tag) => false;

  @override
  bool stateCollisionEmpty(BState state) => state.isAir;

  @override
  bool stateReplaceable(BState state) => state.isAir;

  @override
  List<BlockBox> stateCollisionBoxes(BState state) =>
      state.isAir ? const [] : const [BlockBox(0, 0, 0, 1, 1, 1)];

  @override
  List<MinecartRef> minecartsAt(Pos pos) => carts[pos] ?? const [];
}

/// Asserts [box] is the `Block.box` cuboid [v] (arguments in 1/16 of a block).
void expectBox(BlockBox box, List<double> v) {
  final actual = [box.minX, box.minY, box.minZ, box.maxX, box.maxY, box.maxZ];
  for (var i = 0; i < 6; i++) {
    expect(
      actual[i],
      closeTo(v[i] / 16, 1e-9),
      reason: 'component $i of $actual is not ${v[i]}/16',
    );
  }
}

void main() {
  group('cart assembler shape', () {
    test('is AllShapes.CART_ASSEMBLER for a north-south rail', () {
      expect(cartAssemblerShapeNorthSouth, hasLength(2));
      expectBox(cartAssemblerShapeNorthSouth[0], [0, 12, 0, 16, 16, 16]);
      expectBox(cartAssemblerShapeNorthSouth[1], [-2, 0, 1, 18, 14, 15]);
    });

    test('is the same shape turned a quarter turn for an east-west rail', () {
      expect(cartAssemblerShapeEastWest, hasLength(2));
      expectBox(cartAssemblerShapeEastWest[0], [0, 12, 0, 16, 16, 16]);
      expectBox(cartAssemblerShapeEastWest[1], [1, 0, -2, 15, 14, 18]);
    });

    test('the frame overhangs across the track, not along it', () {
      final ns = cartAssemblerShapeNorthSouth[1];
      final ew = cartAssemblerShapeEastWest[1];
      // North-south: 2/16 beyond both x faces and 1/16 clear of both z faces.
      expect(ns.minX, closeTo(-2 / 16, 1e-9));
      expect(ns.maxX, closeTo(18 / 16, 1e-9));
      expect(ns.minZ, closeTo(1 / 16, 1e-9));
      expect(ns.maxZ, closeTo(15 / 16, 1e-9));
      // East-west: the axes swap.
      expect(ew.minX, closeTo(1 / 16, 1e-9));
      expect(ew.maxX, closeTo(15 / 16, 1e-9));
      expect(ew.minZ, closeTo(-2 / 16, 1e-9));
      expect(ew.maxZ, closeTo(18 / 16, 1e-9));
    });

    test('the rules pick the outline from the shape property', () {
      final rules = cartAssemblerShapeRules();
      expect(rules, hasLength(2));

      final ns = rules.firstWhere((r) => r.when['shape'] == 'north_south');
      final ew = rules.firstWhere((r) => r.when['shape'] == 'east_west');
      expect(ns.when, {'shape': 'north_south'});
      expect(ew.when, {'shape': 'east_west'});
      expect(boxesOf(ns.selectionShape!), cartAssemblerShapeNorthSouth);
      expect(boxesOf(ew.selectionShape!), cartAssemblerShapeEastWest);
      // `CartAssemblerBlock.getCollisionShape` needs the colliding entity, so the rules leave
      // the collision to the block's static shape (the full cube).
      expect(ns.collisionShape, isNull);
      expect(ew.collisionShape, isNull);
    });
  });

  group('cart assembler collision', () {
    test('is CART_ASSEMBLER_PLAYER_COLLISION for a player', () {
      expect(cartAssemblerPlayerCollisionNorthSouth, hasLength(1));
      expectBox(cartAssemblerPlayerCollisionNorthSouth.single, [0, 0, 1, 16, 16, 15]);
      expect(cartAssemblerPlayerCollisionEastWest, hasLength(1));
      expectBox(cartAssemblerPlayerCollisionEastWest.single, [1, 0, 0, 15, 16, 16]);
    });

    test('a minecart gets no boxes, so it rides through the assembler', () {
      for (final shape in ['north_south', 'east_west', null]) {
        expect(
          cartAssemblerCollisionBoxes(shape, CartAssemblerCollider.minecart),
          isEmpty,
          reason: 'a cart must not be stopped on a $shape rail',
        );
      }
    });

    test('a player gets the player shape for the rail axis', () {
      expect(
        cartAssemblerCollisionBoxes(
          'north_south',
          CartAssemblerCollider.player,
        ),
        cartAssemblerPlayerCollisionNorthSouth,
      );
      expect(
        cartAssemblerCollisionBoxes('east_west', CartAssemblerCollider.player),
        cartAssemblerPlayerCollisionEastWest,
      );
      // `getRailAxis` treats anything but `north_south` as the east-west rail.
      expect(
        cartAssemblerCollisionBoxes(null, CartAssemblerCollider.player),
        cartAssemblerPlayerCollisionEastWest,
      );
    });

    test('every other entity gets the full block', () {
      for (final shape in ['north_south', 'east_west', null]) {
        expect(
          cartAssemblerCollisionBoxes(shape, CartAssemblerCollider.other),
          const [BlockBox.unit],
        );
      }
    });

    test('every minecart type counts as a minecart, a player as a player', () {
      for (final type in minecartEntityTypes) {
        expect(
          cartAssemblerColliderFor(type),
          CartAssemblerCollider.minecart,
          reason: type,
        );
      }
      expect(
        minecartEntityTypes,
        containsAll(const [
          'minecraft:minecart',
          'minecraft:chest_minecart',
          'minecraft:furnace_minecart',
          'minecraft:hopper_minecart',
          'minecraft:tnt_minecart',
          'minecraft:command_block_minecart',
          'minecraft:spawner_minecart',
        ]),
      );
      expect(
        cartAssemblerColliderFor('minecraft:player'),
        CartAssemblerCollider.player,
      );
      for (final type in ['minecraft:zombie', 'minecraft:armor_stand', 'minecraft:item']) {
        expect(
          cartAssemblerColliderFor(type),
          CartAssemblerCollider.other,
          reason: type,
        );
      }
    });

    // The body of `cartAssemblerBehavior().onEntityCollisionShape`: the event gives the block
    // state index and the entity type key.
    test('the entity collision handler lets a minecart through', () {
      for (final shape in ['north_south', 'east_west']) {
        for (final type in minecartEntityTypes) {
          expect(
            cartAssemblerCollisionForEntity(shape, type),
            isEmpty,
            reason: '$type on a $shape rail must pass through the assembler',
          );
        }
      }
    });

    test('the entity collision handler keeps a player on the player shape', () {
      expect(
        cartAssemblerCollisionForEntity('north_south', 'minecraft:player'),
        cartAssemblerPlayerCollisionNorthSouth,
      );
      expect(
        cartAssemblerCollisionForEntity('east_west', 'minecraft:player'),
        cartAssemblerPlayerCollisionEastWest,
      );
      // Every other entity still collides with the whole block.
      expect(
        cartAssemblerCollisionForEntity('north_south', 'minecraft:zombie'),
        const [BlockBox.unit],
      );
    });
  });

  group('mounted contraption assembly', () {
    const assemblerNorthSouth = BState('create:cart_assembler', {
      'shape': 'north_south',
      'rail_type': 'rail',
      'powered': 'false',
      'backwards': 'false',
      'waterlogged': 'false',
    });
    const stone = BState('minecraft:stone');

    test('captures the structure above the assembler and swaps it for the anchor', () async {
      final level = _MapLevel({
        (0, 0, 0): assemblerNorthSouth,
        (0, 1, 0): stone,
      });
      final contraption = MountedContraption();

      expect(await contraption.assemble(level, (0, 0, 0)), isTrue);
      expect(contraption.anchor, (0, 0, 0));
      expect(contraption.blocks.keys, containsAll([(0, 0, 0), (0, 1, 0)]));

      // `AllBlocks.MINECART_ANCHOR ... setValue(HORIZONTAL_AXIS, axis)`: a north-south rail
      // gives `Axis.Z`.
      final anchor = contraption.blocks[(0, 0, 0)]!.state;
      expect(anchor.key, minecartAnchorKey);
      expect(anchor['axis'], 'z');
      expect(contraption.blocks[(0, 1, 0)]!.state.key, 'minecraft:stone');
    });

    test('an east-west rail makes an x anchor', () async {
      final level = _MapLevel({
        (0, 0, 0): assemblerNorthSouth.setValue('shape', 'east_west'),
        (0, 1, 0): stone,
      });
      final contraption = MountedContraption();

      expect(await contraption.assemble(level, (0, 0, 0)), isTrue);
      expect(contraption.blocks[(0, 0, 0)]!.state['axis'], 'x');
    });

    test('a lone assembler is not a structure', () async {
      final level = _MapLevel({(0, 0, 0): assemblerNorthSouth});
      final contraption = MountedContraption();

      // `blocks.size() == 1` after the anchor swap: nothing above the assembler.
      expect(await contraption.assemble(level, (0, 0, 0)), isFalse);
    });

    test('a second assembler needs a cart that can be assembled', () async {
      // The slime block drags the stone, the stone drags the assembler below it.
      final blocks = {
        (0, 0, 0): assemblerNorthSouth,
        (0, 1, 0): const BState('minecraft:slime_block'),
        (1, 1, 0): stone,
        (1, 0, 0): assemblerNorthSouth,
      };

      // `testSecondaryCartAssembler`: no cart on the second assembler, it cannot join and the
      // assembly fails with `unmovableBlock`.
      final without = MountedContraption();
      await expectLater(
        without.assemble(_MapLevel(blocks), (0, 0, 0)),
        throwsA(isA<AssemblyException>()),
      );

      // With a cart that can be assembled on it, it joins as another anchor.
      final withCart = MountedContraption();
      final cart = const MinecartRef(
        7,
        'uuid-7',
        'minecraft:minecart',
        true,
        (1.5, 0.0, 0.5),
      );
      final level = _MapLevel(blocks, {
        (1, 0, 0): [cart],
      });
      expect(await withCart.assemble(level, (0, 0, 0)), isTrue);
      expect(withCart.blocks[(1, 0, 0)]!.state.key, minecartAnchorKey);
    });
  });
}
