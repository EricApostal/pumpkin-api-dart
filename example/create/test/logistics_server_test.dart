// Pure server logic of the logistics module: comparator outputs, package port targets, the
// requester's stored order and the chunking of stock responses.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/logistics/host/state_props.dart';
import 'package:create/src/logistics/model/inventory.dart';
import 'package:create/src/logistics/model/orders.dart';
import 'package:create/src/logistics/model/package.dart';
import 'package:create/src/logistics/model/stack.dart';
import 'package:create/src/logistics/model/stack_wire.dart';
import 'package:create/src/logistics/model/stack_tags.dart';
import 'package:create/src/logistics/port/conveyance_items.dart';
import 'package:create/src/logistics/port/package_port_target.dart';
import 'package:create/src/logistics/port/port_inventories.dart';
import 'package:create/src/logistics/requester/auto_request_data.dart';
import 'package:create/src/protocol/item_stack.dart';
import 'package:create/src/trains/station/global_package_port.dart';
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

    test('a requester placed from a programmed item keeps order and address', () {
      // `StockKeeperCategoryMenu` writes the keeper position absolute (`writeToItem`); a
      // requester placed from that item reads it back relative to itself
      // (`RedstoneRequesterBlock.setPlacedBy`), so the order the block sends points at the keeper
      // it was programmed at.
      const keeper = (12, 65, -3);
      const placed = (20, 63, 40);
      final order = PackageOrderWithCrafts.simple([
        BigStack(LStack.of('minecraft:iron_ingot', 1), 4),
      ]);
      // `RedstoneRequesterBlock.programRequester`: the item is written with
      // `writeToItem(BlockPos.ZERO)`, i.e. the keeper position stays absolute on the item.
      final programmed = AutoRequestData(
        order,
        'factory/1',
        keeper,
        'minecraft:overworld',
        false,
      ).writeToItem((0, 0, 0));
      expect(programmed.targetOffset, keeper);

      final read = programmed.readFromItem(placed, 'minecraft:overworld');
      expect(read.encodedTargetAddress, 'factory/1');
      expect(read.encodedRequest.stacks.single.count, 4);
      expect(read.targetPos(placed), keeper);
      expect(read.isValid, isTrue);

      // A keeper more than 128 blocks away (or in another dimension) is placed anyway, only
      // flagged as not valid (the block still keeps the order).
      final far = programmed.readFromItem((200, 63, 40), 'minecraft:overworld');
      expect(far.isValid, isFalse);
      expect(far.encodedTargetAddress, 'factory/1');
      expect(
        programmed
            .readFromItem(placed, 'minecraft:the_nether')
            .isValid,
        isFalse,
      );
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

  group('station package ports', () {
    test('the addresses of a port come from its packages only', () {
      final port = GlobalPackagePort()..address = 'factory/1';
      port.offlineBuffer
        ..setStackInSlot(0, stackToCTag(
          PackageItem.addAddress(PackageStyles.defaultBox(), 'warehouse/2'),
        ))
        ..setStackInSlot(1, stackToCTag(LStack.of('minecraft:stone', 3)));

      final inventories = PortPackageInventories(
        inventoryAt: (_, _) => null,
        hasDimension: (dimension) => dimension == 'minecraft:overworld',
      );

      expect(
        inventories.packageAddresses('minecraft:overworld', (0, 0, 0), port),
        ['warehouse/2'],
      );
    });

    test('a postbox with an empty buffer adds nothing', () {
      final inventories = PortPackageInventories(
        inventoryAt: (_, _) => OfflineBuffer(3),
        hasDimension: (_) => true,
      );

      expect(
        inventories.packageAddresses(
          'minecraft:overworld',
          (0, 0, 0),
          GlobalPackagePort(),
        ),
        isEmpty,
      );
    });

    test('a station in an unloaded dimension is skipped', () {
      final inventories = PortPackageInventories(
        inventoryAt: (_, _) => null,
        hasDimension: (_) => false,
      );

      expect(
        inventories.packageAddresses(
          'minecraft:the_end',
          (0, 0, 0),
          GlobalPackagePort(),
        ),
        isNull,
      );
    });
  });

  group('face-attached directions', () {
    // `FaceAttachedHorizontalDirectionalBlock.getConnectedDirection`: the direction from the
    // block a face-attached block hangs on towards the block itself. `AllShapes.STOCK_LINK`
    // (`shape(1,0,1,15,5,15).forDirectional()`) is read back with it.
    test('floor is up, ceiling is down, wall is the facing', () {
      expect(
        faceConnectedDirection({'face': 'floor', 'facing': 'north'}),
        Direction.up,
      );
      expect(
        faceConnectedDirection({'face': 'ceiling', 'facing': 'north'}),
        Direction.down,
      );
      expect(
        faceConnectedDirection({'face': 'wall', 'facing': 'west'}),
        Direction.west,
      );
      // The defaults of a state without properties are the block's default state.
      expect(faceConnectedDirection(const {}), Direction.up);
    });

    test('a stock link above a packager hangs on it', () {
      // `PackagerBlockEntity.getLinkPos` / `submitNewArrivals`: for the neighbour in direction
      // `d`, the link is the one whose connected direction is `d`. A link lying on the packager
      // is a `floor` link, and the packager below it is the block it hangs on.
      const link = {'face': 'floor', 'facing': 'north'};
      expect(faceConnectedDirection(link), Direction.up);

      // A link on the wall west of the packager: it hangs on the packager east of it, so it
      // faces away from it (west) and the packager is `west` of the link.
      const wallLink = {'face': 'wall', 'facing': 'west'};
      expect(faceConnectedDirection(wallLink), Direction.west);
    });

    test('a gauge restocks the packager opposite its connected direction', () {
      // `FactoryPanelBlockEntity.lazyTick` / `getRestockedPackager`: the packager of a restocking
      // gauge sits at `connectedDirection.opposite` — below a floor gauge, above a ceiling one.
      expect(
        faceConnectedDirection({'face': 'floor', 'facing': 'north'}).opposite,
        Direction.down,
      );
      expect(
        faceConnectedDirection({'face': 'ceiling', 'facing': 'south'}).opposite,
        Direction.up,
      );
    });
  });

  group('face-attached placement', () {
    test('the direction towards the clicked block comes first', () {
      // `BlockPlaceContext.getNearestLookingDirections` moves the direction towards the clicked
      // block to the front; the rest keep the nearest-look order.
      final order = faceAttachedPlacementOrder((0, -1, 0), Direction.down);
      expect(order.first, Direction.down);
      expect(order.toSet(), Direction.values.toSet());
      final look = Direction.orderedByNearest(0, -1, 0);
      expect(order.sublist(1), look.where((d) => d != Direction.down));

      // Looking straight up at a ceiling: `up` is already first.
      expect(
        faceAttachedPlacementOrder((0, 1, 0), Direction.up),
        Direction.orderedByNearest(0, 1, 0),
      );
    });

    test('a vertical direction is floor/ceiling, a wall blocks faces back', () {
      // `FaceAttachedHorizontalDirectionalBlock.getStateForPlacement`.
      expect(faceAttachedStateProps(Direction.down, Direction.north), (
        face: 'floor',
        facing: 'north',
      ));
      expect(faceAttachedStateProps(Direction.up, Direction.west), (
        face: 'ceiling',
        facing: 'west',
      ));
      expect(faceAttachedStateProps(Direction.east, Direction.north), (
        face: 'wall',
        facing: 'west',
      ));
    });

    test('a link placed on a packager becomes a floor link on it', () {
      // A click on the top face of the packager: the direction from the new block towards the
      // clicked block is `down`, and the player looks down at it (`PackagerLinkBlock`'s
      // `canSurvive` accepts everything, so the first candidate wins).
      final state = faceAttachedStateForPlacement(
        'create:stock_link',
        look: (0, -1, 0),
        yaw: 0,
        towardsClicked: Direction.down,
        canAttach: (_) => true,
        waterlogged: false,
      );
      expect(state?.props, {
        'face': 'floor',
        'facing': 'south',
        'powered': 'false',
        'waterlogged': 'false',
      });
      // `PackagerBlockEntity.getLinkPos` takes the neighbour the link's connected direction
      // points at: the packager the link sits on is `up`, one below the link.
      expect(faceConnectedDirection(state!.props), Direction.up);
    });

    test('a link hung under a ceiling turns its facing around', () {
      // The support is above the link, so the candidate is `up` (`ceiling`) and
      // `PackagerLinkBlock.getStateForPlacement` reverses FACING (yaw 90 is west).
      final state = faceAttachedStateForPlacement(
        'create:stock_link',
        look: (0, 1, 0),
        yaw: 90,
        towardsClicked: Direction.up,
        canAttach: (_) => true,
        waterlogged: false,
        adjust: (state) => state['face'] == 'ceiling'
            ? state.setDir('facing', state.dir('facing')!.opposite)
            : state,
      );
      expect(state?['face'], 'ceiling');
      expect(state?['facing'], 'east');
      // A ceiling link hangs on the block above it.
      expect(faceConnectedDirection(state!.props), Direction.down);
    });

    test('a gauge takes the first direction whose support is solid', () {
      // `FactoryPanelBlock.canAttachLenient`: the neighbour behind the panel, at
      // `connectedDirection.opposite`, is solid. The gauge's own floor flip follows.
      BState? place({
        required Direction towardsClicked,
        required bool solidAbove,
      }) => faceAttachedStateForPlacement(
        'create:factory_gauge',
        look: (0, 1, 0),
        yaw: 0,
        towardsClicked: towardsClicked,
        canAttach: (state) => solidAbove
            ? faceConnectedDirection(state.props) == Direction.down
            : faceConnectedDirection(state.props) == Direction.up,
        waterlogged: false,
        adjust: (state) => state['face'] == 'floor'
            ? state.setDir('facing', state.dir('facing')!.opposite)
            : state,
      );

      // Only the block above is solid: a ceiling gauge, which restocks the packager above it.
      final onCeiling = place(
        towardsClicked: Direction.up,
        solidAbove: true,
      );
      expect(onCeiling?['face'], 'ceiling');
      expect(faceConnectedDirection(onCeiling!.props), Direction.down);
      expect(
        faceConnectedDirection(onCeiling.props).opposite,
        Direction.up,
      );

      // Only the block below is solid: the ceiling candidate is refused and the floor one wins
      // with `FactoryPanelBlock`'s reversed FACING (yaw 0 is south).
      final onFloor = place(
        towardsClicked: Direction.up,
        solidAbove: false,
      );
      expect(onFloor?['face'], 'floor');
      expect(onFloor?['facing'], 'north');
      expect(faceConnectedDirection(onFloor!.props), Direction.up);
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
