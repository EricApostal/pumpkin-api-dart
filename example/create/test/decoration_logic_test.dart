import 'package:test/test.dart';

import 'package:create/src/api/block_state.dart';
import 'package:create/src/api/placement.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/decoration/bracket.dart';
import 'package:create/src/decoration/connected_pillar.dart';
import 'package:create/src/decoration/copycat.dart';
import 'package:create/src/decoration/door.dart';
import 'package:create/src/decoration/girder.dart';
import 'package:create/src/decoration/misc_blocks.dart';
import 'package:create/src/decoration/vanilla_blocks.dart';
import 'package:create/src/decoration/whistle.dart';

const pillar = 'create:granite_pillar';

BState pillarState(String axis, {Map<String, String> extra = const {}}) =>
    BState(pillar, {'axis': axis, 'north': 'false', 'east': 'false', 'south': 'false', 'west': 'false', ...extra});

MapBlockGetter world([Map<Pos, BState>? blocks]) => MapBlockGetter(blocks: blocks);

void main() {
  group('BState', () {
    test('setValue ignores unknown properties and equality is by value', () {
      const s = BState('minecraft:oak_stairs', {'facing': 'north', 'half': 'bottom'});
      expect(s.setValue('shape', 'straight'), same(s));
      expect(s.setValue('facing', 'south')['facing'], 'south');
      expect(s == const BState('minecraft:oak_stairs', {'half': 'bottom', 'facing': 'north'}), isTrue);
      expect(s.dir('facing'), Direction.north);
    });
  });

  group('connected pillar', () {
    test('connection properties by axis', () {
      expect(pillarConnectionProperty(Axis.y, Direction.east), 'east');
      expect(pillarConnectionProperty(Axis.y, Direction.up), isNull);
      expect(pillarConnectionProperty(Axis.x, Direction.up), 'east');
      expect(pillarConnectionProperty(Axis.x, Direction.down), 'west');
      expect(pillarConnectionProperty(Axis.z, Direction.east), 'north');
      expect(pillarConnectionProperty(Axis.z, Direction.west), 'south');
      expect(pillarConnectionProperty(Axis.z, Direction.up), 'west');
      expect(pillarConnectionProperty(Axis.z, Direction.down), 'east');
    });

    test('a single pillar connects nowhere', () {
      final level = world({(0, 64, 0): pillarState('y')});
      final s = pillarUpdateColumn(level, (0, 64, 0), pillarState('y'));
      expect(s.props.entries.where((e) => e.key != 'axis' && e.value == 'true'), isEmpty);
    });

    test('two columns side by side connect on the shared side only when they have the same height', () {
      final blocks = <Pos, BState>{
        for (var y = 64; y < 67; y++) (0, y, 0): pillarState('y'),
        for (var y = 64; y < 67; y++) (1, y, 0): pillarState('y'),
      };
      final level = world(blocks);
      var s = pillarUpdateColumn(level, (0, 65, 0), pillarState('y'));
      expect(s.flag('east'), isTrue);
      expect(s.flag('west'), isFalse);
      // Make the neighbour column shorter: the connection breaks.
      blocks.remove((1, 66, 0));
      s = pillarUpdateColumn(world(blocks), (0, 65, 0), pillarState('y'));
      expect(s.flag('east'), isFalse);
    });

    test('updateShape adopts the neighbour along the axis and copies the facing side', () {
      final neighbour = pillarState('y', extra: {'east': 'true'});
      expect(pillarUpdateShape(pillarState('y'), Direction.up, neighbour), neighbour);
      final other = pillarState('y', extra: {'west': 'true'});
      expect(pillarUpdateShape(pillarState('y'), Direction.east, other).flag('east'), isTrue);
      expect(pillarUpdateShape(pillarState('y', extra: {'east': 'true'}), Direction.east, BState.air).flag('east'), isFalse);
    });

    test('placement axis continues the pillar it is placed against', () {
      final against = pillarState('x');
      expect(pillarPlacementAxis(clickedFace: Direction.up, placedOn: against, selfKey: pillar), 'x');
      expect(pillarPlacementAxis(clickedFace: Direction.up, placedOn: against, selfKey: pillar, sneaking: true), 'y');
      expect(pillarPlacementAxis(clickedFace: Direction.north, selfKey: pillar), 'z');
    });
  });

  group('bars and panes', () {
    const pane = BState('create:framed_glass_pane', {
      'north': 'false',
      'east': 'false',
      'south': 'false',
      'west': 'false',
      'waterlogged': 'false',
    });

    test('attach to solid faces, other panes and walls, not to air or leaves', () {
      final level = MapBlockGetter(
        blocks: {
          (1, 64, 0): const BState('minecraft:stone'),
          (-1, 64, 0): pane,
          (0, 64, 1): const BState('minecraft:cobblestone_wall', {'up': 'true', 'north': 'none'}),
          (0, 64, -1): const BState('minecraft:oak_leaves'),
        },
        fullBlocks: {'minecraft:stone', 'minecraft:oak_leaves'},
        tags: {'minecraft:leaves': {'minecraft:oak_leaves'}},
      );
      final s = barsStateForPlacement(level, (0, 64, 0), pane);
      expect(s.flag('east'), isTrue);
      expect(s.flag('west'), isTrue);
      expect(s.flag('south'), isTrue);
      expect(s.flag('north'), isFalse);
    });

    test('updateShape only reacts to horizontal neighbours', () {
      final level = MapBlockGetter(blocks: {(1, 64, 0): const BState('minecraft:stone')});
      expect(barsUpdateShape(level, (0, 64, 0), pane, Direction.east).flag('east'), isTrue);
      expect(barsUpdateShape(level, (0, 64, 0), pane, Direction.up), pane);
    });
  });

  group('walls', () {
    const wall = BState('create:cut_granite_wall', {
      'up': 'true',
      'north': 'none',
      'east': 'none',
      'south': 'none',
      'west': 'none',
      'waterlogged': 'false',
    });

    test('a lone wall keeps its post and no arms', () {
      final s = wallStateForPlacement(world(), (0, 64, 0), wall);
      expect(s.flag('up'), isTrue);
      expect(s['north'], 'none');
    });

    test('connects low to a solid block and raises the post at corners', () {
      final level = world({(0, 64, -1): const BState('minecraft:stone'), (1, 64, 0): const BState('minecraft:stone')});
      final s = wallStateForPlacement(level, (0, 64, 0), wall);
      expect(s['north'], 'low');
      expect(s['east'], 'low');
      expect(s['south'], 'none');
      expect(s.flag('up'), isTrue); // a corner keeps the post
    });

    test('a straight wall under nothing has no post; under a block the arms are tall', () {
      final straight = world({(0, 64, -1): const BState('minecraft:stone'), (0, 64, 1): const BState('minecraft:stone')});
      var s = wallStateForPlacement(straight, (0, 64, 0), wall);
      expect(s['north'], 'low');
      expect(s['south'], 'low');
      expect(s.flag('up'), isFalse);
      final covered = world({
        (0, 64, -1): const BState('minecraft:stone'),
        (0, 64, 1): const BState('minecraft:stone'),
        (0, 65, 0): const BState('minecraft:stone'),
      });
      s = wallStateForPlacement(covered, (0, 64, 0), wall);
      expect(s['north'], 'tall');
      expect(s['south'], 'tall');
    });
  });

  group('rectCovered', () {
    test('union of rectangles covers a test rectangle', () {
      expect(rectCovered((0.4, 0.4, 0.6, 0.6), [(0, 0, 1, 1)]), isTrue);
      expect(rectCovered((0.4, 0.4, 0.6, 0.6), [(0, 0, 0.5, 1), (0.5, 0, 1, 1)]), isTrue);
      expect(rectCovered((0.4, 0.4, 0.6, 0.6), [(0, 0, 0.5, 1)]), isFalse);
      expect(rectCovered((0.4, 0.4, 0.6, 0.6), const []), isFalse);
    });
  });

  group('stairs', () {
    BState stair(Direction facing, {String half = 'bottom', String shape = 'straight'}) => BState('create:cut_granite_stairs', {
      'facing': facing.serializedName,
      'half': half,
      'shape': shape,
      'waterlogged': 'false',
    });

    test('stairs connect around corners', () {
      // A stair facing north with a stair behind it (north) facing east: outer shape.
      final level = world({(0, 64, -1): stair(Direction.east)});
      expect(stairsShapeOf(level, (0, 64, 0), stair(Direction.north)), 'outer_right');
      final west = world({(0, 64, -1): stair(Direction.west)});
      expect(stairsShapeOf(west, (0, 64, 0), stair(Direction.north)), 'outer_left');
      // A stair in front (south) facing east: inner shape.
      final front = world({(0, 64, 1): stair(Direction.east)});
      expect(stairsShapeOf(front, (0, 64, 0), stair(Direction.north)), 'inner_right');
      // Different halves do not connect.
      final top = world({(0, 64, -1): stair(Direction.east, half: 'top')});
      expect(stairsShapeOf(top, (0, 64, 0), stair(Direction.north)), 'straight');
    });

    test('slab merging rules', () {
      expect(slabCanBeReplaced('bottom', clickedFace: Direction.up, cursorY: 0.5), isTrue);
      expect(slabCanBeReplaced('bottom', clickedFace: Direction.north, cursorY: 0.7), isTrue);
      expect(slabCanBeReplaced('bottom', clickedFace: Direction.north, cursorY: 0.3), isFalse);
      expect(slabCanBeReplaced('top', clickedFace: Direction.down, cursorY: 0.9), isTrue);
      expect(slabCanBeReplaced('top', clickedFace: Direction.west, cursorY: 0.3), isTrue);
      expect(slabCanBeReplaced('double', clickedFace: Direction.up, cursorY: 0.9), isFalse);
      expect(slabPlacementType(clickedFace: Direction.down, cursorY: 0.2), 'top');
      expect(slabPlacementType(clickedFace: Direction.east, cursorY: 0.9), 'top');
      expect(slabPlacementType(clickedFace: Direction.up, cursorY: 0.9), 'bottom');
    });
  });

  group('girder', () {
    BracketFacingLookup none = (_) => null;
    const girder = BState(girderKey, {
      'axis': 'y',
      'bottom': 'false',
      'top': 'false',
      'waterlogged': 'false',
      'x': 'false',
      'z': 'false',
    });

    test('placing on a side face makes a beam along that axis', () {
      final s = girderStateForPlacement(world(), none, (0, 64, 0), girder, Direction.east, inWater: false);
      expect(s.flag('x'), isTrue);
      expect(s['axis'], 'x');
      expect(s.flag('z'), isFalse);
    });

    test('a beam connects to a girder beam of the same axis and to solid blocks on its ends only', () {
      final level = world({(1, 64, 0): girder.setFlag('x', true).setValue('axis', 'x'), (-1, 64, 0): const BState('minecraft:stone')});
      var s = girderStateForPlacement(level, none, (0, 64, 0), girder, Direction.east, inWater: false);
      expect(s.flag('x'), isTrue);
      // A beam along z next to a stone on its x side does not connect there...
      final zBeam = girder.setFlag('z', true).setValue('axis', 'z');
      final stoneOnly = world({(-1, 64, 0): const BState('minecraft:stone')});
      expect(girderUpdateShape(stoneOnly, none, (0, 64, 0), zBeam, Direction.west).flag('x'), isFalse);
      // A connection that already exists is kept while there is something solid on that side.
      expect(girderUpdateShape(stoneOnly, none, (0, 64, 0), zBeam.setFlag('x', true), Direction.west).flag('x'), isTrue);
      expect(girderUpdateShape(world(), none, (0, 64, 0), zBeam.setFlag('x', true), Direction.west).flag('x'), isFalse);
      // ... but a neighbouring beam along x pulls it in (`sideState.getValue(updateProperty)`).
      s = girderUpdateShape(level, none, (0, 64, 0), zBeam, Direction.west);
      expect(s.flag('x'), isTrue);
    });

    test('a vertical pole attaches to a girder above and a wall below', () {
      final level = world({(0, 65, 0): girder, (0, 63, 0): const BState('minecraft:cobblestone_wall', {'up': 'true'})});
      final s = girderUpdateState(level, none, (0, 64, 0), girder.setValue('axis', 'x').setFlag('x', true), Direction.up);
      expect(s.flag('top'), isTrue);
      final down = girderUpdateState(level, none, (0, 64, 0), girder.setValue('axis', 'x').setFlag('x', true), Direction.down);
      expect(down.flag('bottom'), isTrue);
    });

    test('brackets and nixie tubes count as attachments', () {
      final brackets = (Pos p) => p == (1, 64, 0) ? Direction.east : null;
      final s = girderUpdateState(world(), brackets, (0, 64, 0), girder.setValue('axis', 'z').setFlag('z', true), Direction.east);
      expect(s.flag('x'), isTrue);
      final nixie = BState('create:nixie_tube', {'double_face': 'ceiling', 'facing': 'north'});
      expect(nixieTubeFacing(nixie), Direction.down);
      expect(nixieTubeFacing(const BState('create:nixie_tube', {'double_face': 'wall', 'facing': 'east'})), Direction.east);
    });

    test('encased shaft conversions', () {
      final encased = const BState(girderEncasedShaftKey, {'axis': 'x', 'bottom': 'true', 'top': 'false', 'waterlogged': 'true'});
      final back = girderFromEncasedShaft(encased, girder);
      expect(back.flag('z'), isTrue);
      expect(back['axis'], 'z');
      expect(back.flag('bottom'), isTrue);
      expect(back.flag('waterlogged'), isTrue);
      final enc = girderEncaseShaft(girder.setFlag('x', true), encased.setValue('axis', 'x'), Direction.north);
      expect(enc['axis'], 'z');
    });

    test('placement helper extends a beam along its axis up to the range', () {
      final beam = girder.setFlag('x', true).setValue('axis', 'x');
      final level = world({(0, 64, 0): beam, (1, 64, 0): beam, (2, 64, 0): beam});
      final offset = girderPlacementOffset(
        level: level,
        state: beam,
        pos: (0, 64, 0),
        hit: (0.9, 64.5, 0.5),
        range: 12,
      );
      expect(offset.success, isTrue);
      expect(offset.pos, (3, 64, 0));
      // Too long on the east side: it continues on the west side instead.
      final limited = girderPlacementOffset(level: level, state: beam, pos: (0, 64, 0), hit: (0.9, 64.5, 0.5), range: 2);
      expect(limited.pos, (-1, 64, 0));
      final blocked = world({...level.blocks, (-1, 64, 0): const BState('minecraft:stone')});
      expect(girderPlacementOffset(level: blocked, state: beam, pos: (0, 64, 0), hit: (0.9, 64.5, 0.5), range: 2).success, isFalse);
    });

    test('wrench click toggles the top connection of a beam', () {
      final beam = girder.setFlag('x', true).setValue('axis', 'x');
      final level = world({(0, 64, 0): beam});
      final changes = girderWrenchClick(level, (0, 64, 0), (0.5, 64.9, 0.5))!;
      expect(changes.single.$1, (0, 64, 0));
      expect(changes.single.$2.flag('top'), isTrue);
    });
  });

  group('brackets', () {
    const bracket = BState(woodenBracketKey, {'axis_along_first': 'true', 'facing': 'north', 'type': 'pipe'});

    test('suitable bracket orientation', () {
      final b = suitableBracket(bracket, Axis.x, Direction.up, BracketType.shaft)!;
      expect(b['type'], 'shaft');
      expect(b['facing'], 'up');
      // up/down brackets: alongFirst = axis(y) != Z ? target == Z : ...; the shaft runs along x so not along first.
      expect(b.flag('axis_along_first'), isTrue);
      expect(suitableBracket(bracket, Axis.z, Direction.up, BracketType.shaft)!.flag('axis_along_first'), isFalse);
      expect(suitableBracket(bracket, Axis.y, Direction.up, BracketType.cog), isNull);
      expect(suitableBracket(bracket, null, Direction.up, BracketType.cog), isNull);
      expect(suitableBracket(bracket, Axis.y, Direction.east, BracketType.pipe)!.flag('axis_along_first'), isTrue);
    });
  });

  group('copycat', () {
    bool valid(BState s) {
      // stone-like state domain: facing with six values for `observer`, four for `furnace`.
      final facing = s['facing'];
      if (s.key == 'minecraft:furnace' && (facing == 'up' || facing == 'down')) return false;
      if (s.key == 'minecraft:hay_block' && s['axis'] == 'y') return true;
      return true;
    }

    test('accepted block states', () {
      const stone = MaterialCandidate(defaultState: BState('minecraft:stone'));
      expect(copycatAcceptedState(stone, isAcceptedRegardless: (_) => false, valid: valid), const BState('minecraft:stone'));
      const noShape = MaterialCandidate(defaultState: BState('minecraft:lantern'), shapeOk: false);
      expect(copycatAcceptedState(noShape, isAcceptedRegardless: (_) => false, valid: valid), isNull);
      expect(copycatAcceptedState(noShape, isAcceptedRegardless: (_) => true, valid: valid), isNotNull);
      const stairs = MaterialCandidate(defaultState: BState('minecraft:oak_stairs'), isStair: true);
      expect(copycatAcceptedState(stairs, isAcceptedRegardless: (_) => false, valid: valid), isNull);
      const barrel = MaterialCandidate(defaultState: BState('minecraft:barrel', {'facing': 'north'}), isEntityBlock: true, allowTag: true);
      expect(copycatAcceptedState(barrel, isAcceptedRegardless: (_) => false, valid: valid, face: Direction.up)!['facing'], 'up');
      const denied = MaterialCandidate(defaultState: BState('minecraft:vine'), denyTag: true);
      expect(copycatAcceptedState(denied, isAcceptedRegardless: (_) => false, valid: valid), isNull);
      const furnace = MaterialCandidate(defaultState: BState('minecraft:furnace', {'facing': 'north'}), shapeOk: true);
      expect(copycatAcceptedState(furnace, isAcceptedRegardless: (_) => false, valid: valid, face: Direction.east)!['facing'], 'east');
      expect(copycatAcceptedState(furnace, isAcceptedRegardless: (_) => false, valid: valid, face: Direction.up)!['facing'], 'north');
      const log = MaterialCandidate(defaultState: BState('minecraft:oak_log', {'axis': 'y'}));
      expect(copycatAcceptedState(log, isAcceptedRegardless: (_) => false, valid: valid, face: Direction.east)!['axis'], 'x');
    });

    test('cycleMaterial turns the material', () {
      bool valid6(BState s) => true;
      bool valid4(BState s) => !(s['facing'] == 'up' || s['facing'] == 'down');
      expect(copycatCycleMaterial(const BState('minecraft:observer', {'facing': 'north'}), valid6)!['facing'], 'east');
      expect(copycatCycleMaterial(const BState('minecraft:observer', {'facing': 'up'}), valid6)!['facing'], 'down');
      expect(copycatCycleMaterial(const BState('minecraft:observer', {'facing': 'down'}), valid6)!['facing'], 'north');
      expect(copycatCycleMaterial(const BState('minecraft:furnace', {'facing': 'north'}), valid4)!['facing'], 'east');
      expect(copycatCycleMaterial(const BState('minecraft:oak_log', {'axis': 'x'}), (s) => true)!['axis'], 'y');
      expect(copycatCycleMaterial(const BState('minecraft:basalt', {'axis': 'z'}), (s) => true)!['axis'], 'x');
      expect(copycatCycleMaterial(const BState('minecraft:basalt', {'axis': 'z'}), (s) => s['axis'] != 'y')!['axis'], 'x');
      expect(copycatCycleMaterial(const BState('minecraft:redstone_lamp', {'lit': 'false'}), valid6)!['lit'], 'true');
      expect(copycatCycleMaterial(const BState('minecraft:acacia_trapdoor', {'half': 'top', 'open': 'true', 'facing': 'north'}), valid6)!['half'], 'bottom');
      expect(copycatCycleMaterial(const BState('minecraft:stone'), valid6), isNull);
    });

    test('special cases', () {
      expect(isBarsMaterial(const BState('minecraft:iron_bars', {'north': 'false', 'east': 'false', 'south': 'false', 'west': 'false'})), isTrue);
      expect(isBarsMaterial(const BState('minecraft:glass_pane', {'north': 'false', 'east': 'false', 'south': 'false', 'west': 'false'})), isFalse);
      expect(isTrapdoorMaterial(const BState('minecraft:oak_trapdoor', {'half': 'top', 'open': 'false', 'facing': 'north'})), isTrue);
    });

    test('material NBT map round trip', () {
      const m = BState('minecraft:oak_log', {'axis': 'z'});
      expect(materialFromMap(materialToMap(m)), m);
    });
  });

  group('doors', () {
    const door = BState('create:andesite_door', {
      'facing': 'north',
      'half': 'lower',
      'hinge': 'left',
      'open': 'false',
      'powered': 'false',
      'visible': 'true',
    });

    test('hinge chooses the side with a wall', () {
      final level = world({(1, 64, 0): const BState('minecraft:stone')});
      // Looking north; the right side (east) has a solid block: hinge right.
      expect(doorHinge(level, (0, 64, 0), Direction.north, (0.5, 64.5, 0.5), 'x'), 'right');
      final left = world({(-1, 64, 0): const BState('minecraft:stone')});
      expect(doorHinge(left, (0, 64, 0), Direction.north, (0.5, 64.5, 0.5), 'x'), 'left');
    });

    test('upper half adopts the lower half and vice versa, an orphan half goes', () {
      final lower = door;
      final upper = door.setValue('half', 'upper');
      final opened = lower.setFlag('open', true);
      final level = world({(0, 64, 0): lower, (0, 65, 0): upper, (0, 63, 0): const BState('minecraft:stone')});
      final next = doorUpdateShape(level, (0, 65, 0), upper, Direction.down, opened, sliding: true);
      expect(next['half'], 'upper');
      expect(next.flag('open'), isTrue);
      expect(doorUpdateShape(level, (0, 65, 0), upper, Direction.down, BState.air, sliding: true).isAir, isTrue);
      // Lower half without floor.
      expect(doorUpdateShape(world(), (0, 64, 0), lower, Direction.down, BState.air, sliding: true).isAir, isTrue);
      expect(doorUpdateShape(level, (0, 64, 0), lower, Direction.down, const BState('minecraft:stone'), sliding: true), lower);
    });

    test('using a sliding door opens it; a double door opens together', () {
      final left = door.setValue('hinge', 'left');
      final right = door.setValue('hinge', 'right');
      // facing north: left hinge -> other door at clockwise (east).
      final level = world({(0, 64, 0): left, (1, 64, 0): right});
      final action = slidingDoorUse(level, (0, 64, 0), left);
      expect(action.changes.length, 2);
      expect(action.changes[0].$2.flag('open'), isTrue);
      expect(action.changes[0].$2.flag('visible'), isFalse);
      expect(action.changes[1].$1, (1, 64, 0));
      expect(action.changes[1].$2.flag('open'), isTrue);
      final single = slidingDoorUse(world({(0, 64, 0): left}), (0, 64, 0), left);
      expect(single.changes.length, 1);
      expect(single.sound, isNotNull);
      // Closing again plays no sound from this branch.
      final closed = slidingDoorUse(world({(0, 64, 0): left.setFlag('open', true)}), (0, 64, 0), left.setFlag('open', true));
      expect(closed.changes.single.$2.flag('open'), isFalse);
      expect(closed.sound, isNull);
    });

    test('redstone opens and closes', () {
      final level = world({(0, 64, 0): door});
      final power = {(0, 64, 0)};
      var action = slidingDoorNeighborChanged(level, (0, 64, 0), door,
          sourceIsSameBlock: false, deferUpdate: false, hasNeighborSignal: power.contains);
      expect(action.changes.last.$2.flag('open'), isTrue);
      expect(action.changes.last.$2.flag('powered'), isTrue);
      expect(action.changes.last.$2.flag('visible'), isFalse);
      // No change when the powered state already matches.
      final poweredDoor = door.setFlag('powered', true).setFlag('open', true);
      action = slidingDoorNeighborChanged(world({(0, 64, 0): poweredDoor}), (0, 64, 0), poweredDoor,
          sourceIsSameBlock: false, deferUpdate: false, hasNeighborSignal: power.contains);
      expect(action.changes, isEmpty);
      // A deferred door waits.
      action = slidingDoorNeighborChanged(level, (0, 64, 0), door,
          sourceIsSameBlock: false, deferUpdate: true, hasNeighborSignal: power.contains);
      expect(action.changes, isEmpty);
    });

    test('setOpen', () {
      final level = world({(0, 64, 0): door});
      final action = slidingDoorSetOpen(level, (0, 64, 0), door, true);
      expect(action.changes.single.$2.flag('open'), isTrue);
      expect(slidingDoorSetOpen(level, (0, 64, 0), door, false).changes, isEmpty);
    });

    test('animation shows the model again after closing', () {
      final anim = SlidingDoorAnimation(open: true);
      var shown = false;
      var ticks = 0;
      while (!shown && ticks < 50) {
        ticks++;
        shown = anim.tick(open: false, visible: false);
      }
      expect(shown, isTrue);
      expect(ticks, inInclusiveRange(7, 9));
      expect(anim.tick(open: false, visible: true), isFalse);
    });

    test('a door saved while closing is shown again after a few ticks', () {
      final anim = SlidingDoorAnimation(open: false);
      var shownAt = -1;
      for (var i = 1; i <= 10 && shownAt < 0; i++) {
        if (anim.tick(open: false, visible: false)) shownAt = i;
      }
      expect(shownAt, 5);
    });
  });

  group('whistle', () {
    const ext = BState(whistleExtensionKey, {'shape': 'single', 'size': 'medium'});
    const whistle = BState(whistleKey, {'facing': 'north', 'powered': 'false', 'size': 'medium', 'wall': 'false'});

    test('pitch counts the extensions', () {
      final none = world({(0, 64, 0): whistle});
      expect(whistlePitchAt(none, (0, 64, 0)), 0);
      final one = world({(0, 64, 0): whistle, (0, 65, 0): ext});
      expect(whistlePitchAt(one, (0, 64, 0)), 1);
      final two = world({(0, 64, 0): whistle, (0, 65, 0): ext.setValue('shape', 'double'), (0, 66, 0): ext});
      expect(whistlePitchAt(two, (0, 64, 0)), 3);
      final doubleOnly = world({(0, 64, 0): whistle, (0, 65, 0): ext.setValue('shape', 'double_connected'), (0, 66, 0): ext.setValue('shape', 'double')});
      expect(whistlePitchAt(doubleOnly, (0, 64, 0)), 4);
      expect(whistlePitchId(3, 'large'), 203);
    });

    test('incrementSize adds then extends', () {
      final tank = MapBlockGetter(blocks: {(0, 64, 0): whistle, (0, 63, 0): const BState('create:fluid_tank')});
      var g = whistleIncrementSize(tank, (0, 64, 0), ext)!;
      expect(g.pos, (0, 65, 0));
      expect(g.state['shape'], 'single');
      expect(g.pitch, closeTo(0.9439, 1e-3));
      tank.set((0, 65, 0), g.state);
      g = whistleIncrementSize(tank, (0, 64, 0), ext)!;
      expect(g.pos, (0, 65, 0));
      expect(g.state['shape'], 'double');
      tank.set((0, 65, 0), g.state);
      g = whistleIncrementSize(tank, (0, 64, 0), ext)!;
      expect(g.pos, (0, 66, 0));
    });

    test('placement needs a tank and picks floor or wall', () {
      final level = MapBlockGetter(blocks: {(0, 63, 0): const BState('create:fluid_tank'), (1, 64, 0): const BState('create:creative_fluid_tank')});
      final floor = whistleStateForPlacement(
        level: level,
        pos: (0, 64, 0),
        defaultState: whistle,
        clickedFace: Direction.up,
        horizontalDirection: Direction.east,
        hasNeighborSignal: false,
      )!;
      expect(floor.flag('wall'), isFalse);
      expect(floor['facing'], 'east');
      // Clicking the west face of the tank at (1, 64, 0): the whistle goes on its west and faces away.
      final wall = whistleStateForPlacement(
        level: level,
        pos: (0, 64, 0),
        defaultState: whistle,
        clickedFace: Direction.west,
        horizontalDirection: Direction.east,
        hasNeighborSignal: true,
      )!;
      expect(wall.flag('wall'), isTrue);
      expect(wall.flag('powered'), isTrue);
      expect(wall['facing'], 'east');
      // A wall whistle needs the tank it is attached to.
      final noTank = whistleStateForPlacement(
        level: level,
        pos: (0, 64, 0),
        defaultState: whistle,
        clickedFace: Direction.east,
        horizontalDirection: Direction.east,
        hasNeighborSignal: false,
      );
      expect(noTank, isNull);
    });

    test('an extension without support goes', () {
      final level = MapBlockGetter(blocks: {(0, 64, 0): whistle});
      expect(whistleExtenderUpdateShape(level, (0, 65, 0), ext, Direction.down), ext.setValue('size', 'medium'));
      expect(whistleExtenderUpdateShape(MapBlockGetter(), (0, 65, 0), ext, Direction.down).isAir, isTrue);
      expect(whistleExtenderUpdateShape(level, (0, 65, 0), ext.setValue('shape', 'double'), Direction.up), ext.setValue('shape', 'double'));
      final stacked = MapBlockGetter(blocks: {(0, 66, 0): ext});
      expect(whistleExtenderUpdateShape(stacked, (0, 65, 0), ext.setValue('shape', 'double'), Direction.up)['shape'], 'double_connected');
      expect(whistleFindRoot(MapBlockGetter(blocks: {(0, 64, 0): whistle, (0, 65, 0): ext}), (0, 66, 0)), (0, 64, 0));
    });
  });

  group('ladders, scaffolding, placards', () {
    const ladder = BState('create:andesite_ladder', {'facing': 'north', 'waterlogged': 'false'});

    test('ladders survive on a solid back or below another ladder', () {
      final level = MapBlockGetter(blocks: {(0, 64, 1): const BState('minecraft:stone')});
      expect(ladderCanSurvive(level, (0, 64, 0), ladder), isTrue);
      expect(ladderCanSurvive(MapBlockGetter(), (0, 64, 0), ladder), isFalse);
      final stacked = MapBlockGetter(blocks: {(0, 65, 0): ladder});
      expect(ladderCanSurvive(stacked, (0, 64, 0), ladder), isTrue);
      expect(ladderUpdateShape(MapBlockGetter(), (0, 64, 0), ladder).isAir, isTrue);
    });

    test('ladder placement tries the looking directions', () {
      final level = MapBlockGetter(blocks: {(0, 64, -1): const BState('minecraft:stone')});
      final s = ladderStateForPlacement(
        level: level,
        pos: (0, 64, 0),
        defaultState: ladder,
        nearestLooking: [Direction.down, Direction.north, Direction.east],
        inWater: true,
        replacingClickedOnBlock: false,
        clickedFace: Direction.north,
      )!;
      expect(s['facing'], 'south');
      expect(s.flag('waterlogged'), isTrue);
    });

    test('ladder placement helper stacks ladders', () {
      final level = MapBlockGetter(blocks: {
        (0, 64, 1): const BState('minecraft:stone'),
        (0, 65, 1): const BState('minecraft:stone'),
        (0, 66, 1): const BState('minecraft:stone'),
        (0, 64, 0): ladder,
        (0, 65, 0): ladder,
      });
      final offset = ladderPlacementOffset(level: level, state: ladder, pos: (0, 64, 0), playerPitch: -10, range: 12);
      expect(offset.pos, (0, 66, 0));
      expect(ladderPlacementOffset(level: level, state: ladder, pos: (0, 64, 0), playerPitch: -10, range: 1).success, isFalse);
    });

    test('scaffolding distance and stacking', () {
      final level = MapBlockGetter(blocks: {(0, 63, 0): const BState('minecraft:stone')});
      expect(scaffoldingDistance(level, (0, 64, 0)), 0);
      expect(scaffoldingDistance(MapBlockGetter(), (0, 64, 0)), 7);
      const scaff = BState('create:andesite_scaffolding', {'bottom': 'false', 'distance': '7', 'waterlogged': 'false'});
      final placed = scaffoldingStateForPlacement(MapBlockGetter(), (0, 64, 0), scaff);
      expect(placed.flag('bottom'), isTrue);
      expect(placed.intValue('distance'), 7);
      final column = MapBlockGetter(blocks: {(0, 64, 0): scaff, (0, 65, 0): scaff, (0, 66, 0): scaff});
      final target = scaffoldingItemTarget(
        level: column,
        blockKey: scaff.key,
        clickedPos: (0, 64, 0),
        clickedFace: Direction.north,
        horizontalDirection: Direction.east,
        secondaryUse: false,
        minY: -64,
        maxY: 319,
      );
      expect(target, (0, 67, 0));
      final sideways = scaffoldingItemTarget(
        level: column,
        blockKey: scaff.key,
        clickedPos: (0, 64, 0),
        clickedFace: Direction.up,
        horizontalDirection: Direction.east,
        secondaryUse: false,
        minY: -64,
        maxY: 319,
      );
      expect(sideways, (1, 64, 0));
      expect(scaffoldingUpdateShape(column, (0, 64, 0), scaff, Direction.down).flag('bottom'), isTrue);
    });

    test('placard placement and signal', () {
      const placardState = BState('create:placard', {'face': 'floor', 'facing': 'north', 'powered': 'true', 'waterlogged': 'false'});
      final level = MapBlockGetter(blocks: {(0, 63, 0): const BState('minecraft:stone')});
      final s = placardStateForPlacement(
        level: level,
        pos: (0, 64, 0),
        defaultState: placardState.setFlag('powered', false),
        nearestLooking: [Direction.down, Direction.north],
        horizontalDirection: Direction.east,
        inWater: false,
      )!;
      expect(s['face'], 'floor');
      expect(s['facing'], 'west'); // flipped on the floor
      expect(placardSignal(placardState), 15);
      // Floor placards are "connected" upward, the signal reaches the up side only (strong).
      expect(placardDirectSignal(placardState, Direction.up), 15);
      expect(placardDirectSignal(placardState, Direction.north), 0);
      expect(placardCanSurvive(MapBlockGetter(), (0, 64, 0), placardState), isFalse);
    });
  });

  group('copper', () {
    test('weather ages', () {
      expect(copperWeatherAge('create:copper_shingles'), 0);
      expect(copperWeatherAge('create:exposed_copper_tile_slab'), 1);
      expect(copperWeatherAge('minecraft:weathered_cut_copper'), 2);
      expect(copperWeatherAge('create:oxidized_copper_shingle_stairs'), 3);
      expect(copperWeatherAge('create:waxed_copper_tiles'), isNull);
      expect(copperWeatherAge('minecraft:stone'), isNull);
      expect(copperWeatherAge('minecraft:copper_ore'), isNull);
    });

    test('names of the next, previous and waxed variants', () {
      expect(createCopperNext('copper_shingles'), 'exposed_copper_shingles');
      expect(createCopperNext('exposed_copper_tile_slab'), 'weathered_copper_tile_slab');
      expect(createCopperNext('weathered_copper_tile_stairs'), 'oxidized_copper_tile_stairs');
      expect(createCopperNext('oxidized_copper_tiles'), isNull);
      expect(createCopperNext('waxed_copper_tiles'), isNull);
      expect(createCopperPrevious('exposed_copper_tiles'), 'copper_tiles');
      expect(createCopperPrevious('copper_tiles'), isNull);
      expect(createCopperWaxed('copper_shingle_slab'), 'waxed_copper_shingle_slab');
      expect(createCopperWaxed('waxed_copper_tiles'), isNull);
      expect(createCopperUnwaxed('waxed_oxidized_copper_tiles'), 'oxidized_copper_tiles');
      expect(createCopperKey('copper_shingles', 'slab', stage: 2, waxed: true), 'waxed_weathered_copper_shingle_slab');
      expect(createCopperKey('copper_tiles', 'stairs'), 'copper_tile_stairs');
    });

    test('weathering is blocked by less weathered neighbours and sped up by older ones', () {
      final alone = MapBlockGetter();
      expect(copperShouldAdvance(alone, (0, 64, 0), 0, 0.74), isTrue);
      expect(copperShouldAdvance(alone, (0, 64, 0), 0, 0.76), isFalse);
      expect(copperShouldAdvance(alone, (0, 64, 0), 1, 0.99), isTrue);
      final fresher = MapBlockGetter(blocks: {(1, 64, 0): const BState('create:copper_tiles')});
      expect(copperShouldAdvance(fresher, (0, 64, 0), 1, 0.0), isFalse);
      final older = MapBlockGetter(blocks: {(1, 64, 0): const BState('create:oxidized_copper_tiles'), (0, 65, 0): const BState('minecraft:exposed_copper')});
      // 1 older (oxidized), 1 same age: chance = 2/3, squared 0.444
      expect(copperShouldAdvance(older, (0, 64, 0), 1, 0.44), isTrue);
      expect(copperShouldAdvance(older, (0, 64, 0), 1, 0.45), isFalse);
      // Distance 5 is out of range.
      final far = MapBlockGetter(blocks: {(5, 64, 0): const BState('create:copper_tiles')});
      expect(copperShouldAdvance(far, (0, 64, 0), 1, 0.9), isTrue);
    });
  });

  group('placement helpers', () {
    test('orderedByDistance sorts by the face nearest the hit', () {
      final dirs = orderedByDistance((0, 64, 0), (0.95, 64.5, 0.5));
      expect(dirs.first, Direction.east);
      expect(dirs.last, Direction.west);
      expect(orderedByDistanceExceptAxis((0, 64, 0), (0.95, 64.5, 0.5), Axis.x).first, isNot(Direction.east));
    });

    test('pole helper extends along the axis', () {
      const step = BState('create:copycat_step', {'facing': 'north', 'half': 'bottom', 'waterlogged': 'false'});
      final level = MapBlockGetter(blocks: {(0, 64, 0): step});
      final offset = poleOffset(
        level: level,
        state: step,
        pos: (0, 64, 0),
        hit: (0.9, 64.5, 0.5),
        matches: (s) => s.key == 'create:copycat_step',
        axisOf: (s) => s.dir('facing')!.clockWise.axis,
        transformProperty: 'facing',
        range: 12,
      );
      expect(offset.success, isTrue);
      expect(offset.pos, (1, 64, 0));
      expect(offset.transform(const BState('create:copycat_step', {'facing': 'south'}))['facing'], 'north');
    });
  });
}
