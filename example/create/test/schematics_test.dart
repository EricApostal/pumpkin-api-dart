import 'dart:typed_data';

import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/schematics/item_requirement.dart';
import 'package:create/src/schematics/launched_item.dart';
import 'package:create/src/schematics/material_checklist.dart';
import 'package:create/src/schematics/schematic_printer.dart';
import 'package:create/src/schematics/schematic_hooks.dart';
import 'package:create/src/schematics/schematic_stack.dart';
import 'package:create/src/schematics/schematic_world.dart';
import 'package:create/src/schematics/schematicannon_core.dart';
import 'package:create/src/schematics/state_transform.dart';
import 'package:create/src/schematics/upload_receiver.dart';
import 'package:test/test.dart';

const stone = BState('minecraft:stone');
const air = BState.air;

final class _View implements PrinterTargetView {
  final Map<Pos, BState> world;
  _View(this.world);

  @override
  bool isLoaded(Pos p) => true;

  @override
  bool isWithinWorldBorder(Pos p) => true;

  @override
  BState stateAt(Pos p) => world[p] ?? air;

  @override
  String? blockEntityTypeAt(Pos p) => null;

  @override
  bool hasBlockEntity(BState state) => state.key == 'minecraft:chest';

  @override
  double destroySpeed(BState s) => s.key == 'minecraft:bedrock' ? -1 : 1;

  @override
  bool isRedstoneConductor(BState s) => s.key == 'minecraft:stone';

  @override
  bool isWater(Pos p) => false;
}

final class _Env implements CannonEnv {
  @override
  final PrinterTargetView view;
  final SchematicWorld? schematic;
  final Map<String, int> chest = {
    'minecraft:stone': 100,
    'minecraft:gunpowder': 5,
  };
  final List<LaunchedItem> placed = [];
  int fired = 0;
  int finished = 0;

  _Env(this.view, this.schematic);

  @override
  Pos get cannonPos => (0, 64, 0);

  @override
  final SchematicRequirements requirements = SchematicRequirements();

  @override
  bool isBrittle(BState state) => false;

  @override
  int get cannonDelay => 2;

  @override
  int get shotsPerGunpowder => 400;

  @override
  BlueprintLoad loadBlueprint(SlotStack blueprint) => schematic == null
      ? const BlueprintLoad(BlueprintStatus.invalid)
      : BlueprintLoad(BlueprintStatus.ok, schematic);

  @override
  bool get hasCreativeCrate => false;

  @override
  Future<void> findInventories() async {}

  @override
  Future<bool> grabItems(
    StackRequirement required, {
    required bool simulate,
  }) async {
    final have = chest[required.item] ?? 0;
    if (have < required.count) return false;
    if (!simulate) chest[required.item] = have - required.count;
    return true;
  }

  @override
  Future<bool> takeExternalGunpowder() async {
    final have = chest['minecraft:gunpowder'] ?? 0;
    if (have <= 0) return false;
    chest['minecraft:gunpowder'] = have - 1;
    return true;
  }

  @override
  Future<List<SlotStack>> attachedStacks() async => [
    for (final e in chest.entries) SlotStack(e.key, e.value),
  ];

  @override
  void playFiringSound() => fired++;

  @override
  void playFinishSound() => finished++;

  @override
  void scheduleWaterTick(Pos pos) {}

  @override
  Future<void> place(LaunchedItem item) async => placed.add(item);

  @override
  List<int>? prepareBlockEntityData(BState state, List<int>? nbt) => nbt;

  @override
  Future<SlotStack> createChecklistStack(
    MaterialChecklist checklist, {
    required bool clipboard,
  }) async =>
      SlotStack(clipboard ? 'create:clipboard' : 'minecraft:written_book', 1);

  @override
  bool isClipboard(SlotStack stack) => stack.item == 'create:clipboard';

  @override
  bool isBlueprintItem(SlotStack stack) => stack.item == 'create:schematic';
}

void main() {
  group('state transform', () {
    test('facing, axis, sides and rotation', () {
      expect(
        rotateState(
          const BState('minecraft:furnace', {'facing': 'north'}),
          BlockRotation.clockwise90,
        )['facing'],
        'east',
      );
      expect(
        rotateState(
          const BState('minecraft:dispenser', {'facing': 'up'}),
          BlockRotation.clockwise90,
        )['facing'],
        'up',
      );
      expect(
        rotateState(
          const BState('minecraft:oak_log', {'axis': 'x'}),
          BlockRotation.clockwise90,
        )['axis'],
        'z',
      );
      expect(
        rotateState(
          const BState('minecraft:oak_log', {'axis': 'y'}),
          BlockRotation.clockwise90,
        )['axis'],
        'y',
      );
      expect(
        rotateState(
          const BState('minecraft:oak_log', {'axis': 'x'}),
          BlockRotation.clockwise180,
        )['axis'],
        'x',
      );
      final fence = rotateState(
        const BState('minecraft:oak_fence', {
          'north': 'true',
          'east': 'false',
          'south': 'false',
          'west': 'false',
        }),
        BlockRotation.clockwise90,
      );
      expect(fence['east'], 'true');
      expect(fence['north'], 'false');
      expect(
        rotateState(
          const BState('minecraft:oak_sign', {'rotation': '2'}),
          BlockRotation.clockwise90,
        )['rotation'],
        '6',
      );
      expect(
        mirrorState(
          const BState('minecraft:oak_sign', {'rotation': '2'}),
          BlockMirror.leftRight,
        )['rotation'],
        '6',
      );
      expect(
        mirrorState(
          const BState('minecraft:furnace', {'facing': 'north'}),
          BlockMirror.leftRight,
        )['facing'],
        'south',
      );
      expect(
        mirrorState(
          const BState('minecraft:furnace', {'facing': 'east'}),
          BlockMirror.leftRight,
        )['facing'],
        'east',
      );
    });

    test('stairs, doors and rails', () {
      final stairs = const BState('minecraft:oak_stairs', {
        'facing': 'north',
        'half': 'bottom',
        'shape': 'inner_left',
      });
      final m = mirrorState(stairs, BlockMirror.leftRight);
      expect(m['facing'], 'south');
      expect(m['shape'], 'inner_right');
      final door = const BState('minecraft:oak_door', {
        'facing': 'east',
        'hinge': 'left',
        'half': 'lower',
      });
      expect(mirrorState(door, BlockMirror.frontBack)['hinge'], 'right');
      expect(mirrorState(door, BlockMirror.frontBack)['facing'], 'west');
      expect(
        rotateState(
          const BState('minecraft:rail', {'shape': 'north_south'}),
          BlockRotation.clockwise90,
        )['shape'],
        'east_west',
      );
      expect(
        rotateState(
          const BState('minecraft:rail', {'shape': 'ascending_north'}),
          BlockRotation.clockwise90,
        )['shape'],
        'ascending_east',
      );
      expect(
        rotateState(
          const BState('minecraft:rail', {'shape': 'south_east'}),
          BlockRotation.clockwise180,
        )['shape'],
        'north_west',
      );
    });

    test('mirror then rotate', () {
      final s = transformState(
        const BState('minecraft:furnace', {'facing': 'north'}),
        BlockMirror.leftRight,
        BlockRotation.clockwise90,
      );
      expect(s['facing'], 'west'); // north -> south -> west
    });
  });

  group('schematic world', () {
    TemplateData tpl() => const TemplateData(
      (3, 1, 1),
      [
        TemplateBlock((0, 0, 0), stone),
        TemplateBlock((
          1,
          0,
          0,
        ), BState('minecraft:furnace', {'facing': 'north', 'lit': 'true'})),
        TemplateBlock((2, 0, 0), air),
      ],
    );

    test('transforms blocks and widens the bounds', () {
      final w = SchematicWorld.fromTemplate(
        tpl(),
        anchor: (10, 64, 10),
        rotation: BlockRotation.clockwise90,
      );
      // (x, y, z) -> (-z, y, x)
      expect(w.stateAt((0, 0, 0)), stone);
      expect(w.stateAt((0, 0, 1))['facing'], 'east');
      expect(w.stateAt((0, 0, 1))['lit'], 'false'); // not lit for printing
      expect(w.bounds, BlockBounds.fromCorners((0, 0, 0), (0, 0, 2)));
      expect(w.stateAt((0, -1, 0)).key, 'minecraft:dirt'); // support layer
    });
  });

  group('printer', () {
    test('walks all blocks in x, z, y order and defers brittle ones', () {
      final world = SchematicWorld(posZero)
        ..setBlock((0, 0, 0), const SchematicBlock(stone))
        ..setBlock((1, 0, 0), const SchematicBlock(BState('minecraft:torch')))
        ..setBlock((0, 0, 1), const SchematicBlock(stone))
        ..setBlock((0, 1, 0), const SchematicBlock(stone));
      final printer = SchematicPrinter()
        ..isBrittle = ((s) => s.key == 'minecraft:torch')
        ..load(world);
      final order = <Pos>[];
      while (printer.advanceCurrentPos()) {
        order.add(printer.currentPos!);
      }
      expect(order.first, (0, 0, 0));
      expect(order.last, (1, 0, 0)); // the torch was deferred to the end
      expect(
        order.toSet(),
        containsAll(<Pos>[(0, 0, 0), (0, 0, 1), (0, 1, 0), (1, 0, 0)]),
      );
      expect(printer.printStage, PrintStage.entities);
    });

    test('persists progress', () {
      final p = SchematicPrinter();
      p.load(
        SchematicWorld((5, 64, 5))
          ..setBlock((0, 0, 0), const SchematicBlock(stone)),
      );
      p.advanceCurrentPos();
      final tag = p.toTag();
      final q = SchematicPrinter()..fromTag(tag, clientPacket: true);
      expect(q.currentPos, p.currentPos);
      expect(q.anchor, (5, 64, 5));
      expect(q.printStage, p.printStage);
    });
  });

  group('requirements', () {
    final r = SchematicRequirements()
      ..itemOfBlock = (k) => k == 'minecraft:water'
          ? null
          : (k == 'minecraft:wall_torch' ? 'minecraft:torch' : k);
    test('defaults', () {
      expect(r.ofBlock(air, null).isEmpty, isTrue);
      expect(
        r.ofBlock(const BState('minecraft:water'), null).isInvalid,
        isTrue,
      );
      expect(
        r
            .ofBlock(const BState('minecraft:wall_torch'), null)
            .requiredItems
            .single
            .item,
        'minecraft:torch',
      );
      expect(
        r
            .ofBlock(
              const BState('minecraft:oak_slab', {'type': 'double'}),
              null,
            )
            .requiredItems
            .single
            .count,
        2,
      );
      expect(
        r
            .ofBlock(const BState('minecraft:farmland'), null)
            .requiredItems
            .single
            .item,
        'minecraft:dirt',
      );
      expect(
        r
            .ofBlock(
              const BState('minecraft:sea_pickle', {'pickles': '3'}),
              null,
            )
            .requiredItems
            .single
            .count,
        3,
      );
      expect(
        r
            .ofBlock(const BState('minecraft:snow', {'layers': '5'}), null)
            .requiredItems
            .single
            .count,
        5,
      );
      expect(
        r
            .ofBlock(const BState('minecraft:tall_grass'), null)
            .requiredItems
            .single
            .item,
        'minecraft:short_grass',
      );
    });

    test('union', () {
      final a = ItemRequirement.of1(ItemUseType.consume, 'a');
      expect(a.union(ItemRequirement.none).requiredItems.length, 1);
      expect(a.union(ItemRequirement.invalid).isInvalid, isTrue);
      expect(
        a
            .union(ItemRequirement.of1(ItemUseType.damage, 'b'))
            .requiredItems
            .length,
        2,
      );
    });

    test('a strict requirement compares the components it names', () {
      const strict = StackRequirement(
        'minecraft:diamond_sword',
        1,
        ItemUseType.consume,
        strictComponents: {'minecraft:damage': NbtValue.int32(5)},
      );
      // `ItemStack.getComponents` gives a component's network bytes under its wire name;
      // `DataComponentCodec` turns the required NBT into that form.
      List<int>? encode(String name, NbtValue value) =>
          name == 'minecraft:damage' ? [value.value as int] : null;
      // The item decides first.
      expect(
        strict.matches(
          'minecraft:iron_sword',
          otherComponents: {
            'damage': [5],
          },
          encode: encode,
        ),
        isFalse,
      );
      // Nothing to compare against: the requirement pins the item only.
      expect(strict.matches('minecraft:diamond_sword'), isTrue);
      // The component the requirement names must match too.
      expect(
        strict.matches(
          'minecraft:diamond_sword',
          otherComponents: {
            'damage': [5],
          },
          encode: encode,
        ),
        isTrue,
      );
      expect(
        strict.matches(
          'minecraft:diamond_sword',
          otherComponents: {
            'damage': [6],
          },
          encode: encode,
        ),
        isFalse,
      );
      expect(
        strict.matches(
          'minecraft:diamond_sword',
          otherComponents: const <String, List<int>>{},
          encode: encode,
        ),
        isFalse,
      );
      // A component without an encoder cannot be compared, so it is not.
      expect(
        strict.matches(
          'minecraft:diamond_sword',
          otherComponents: const <String, List<int>>{},
          encode: (name, value) => null,
        ),
        isTrue,
      );
    });

    test('entities: glue and blueprint', () {
      final empty = BinaryNbt.write(NbtValue.compound(const {}));
      final glue = r
          .ofEntity('create:super_glue', empty)
          .requiredItems
          .single;
      expect(glue.item, 'create:super_glue');
      expect(glue.usage, ItemUseType.damage);
      expect(glue.count, 1);
      final blueprint = r
          .ofEntity('create:crafting_blueprint', empty)
          .requiredItems
          .single;
      expect(blueprint.item, 'create:crafting_blueprint');
      expect(blueprint.usage, ItemUseType.consume);
      final frame = r
          .ofEntity('minecraft:item_frame', empty)
          .requiredItems
          .single;
      expect(frame.item, 'minecraft:item_frame');
    });

    test('blocks without an item resolve through their special requirement', () {
      final special = SchematicRequirements()
        ..itemOfBlock = (k) => k.startsWith('create:') ? k : null;
      registerSpecialBlockRequirements(special);
      String items(BState state) => special
          .ofBlock(state, null)
          .requiredItems
          .map((e) => '${e.count}x ${e.item}')
          .join(', ');
      expect(items(const BState('create:glass_fluid_pipe')), '1x create:fluid_pipe');
      expect(
        items(const BState('create:andesite_belt_funnel')),
        '1x create:andesite_funnel',
      );
      expect(
        items(const BState('create:brass_belt_funnel')),
        '1x create:brass_funnel',
      );
      expect(
        items(const BState('create:metal_girder_encased_shaft')),
        '1x create:shaft, 1x create:metal_girder',
      );
      expect(
        items(const BState('create:lectern_controller')),
        '1x minecraft:lectern, 1x create:linked_controller',
      );
    });

    test('a copycat needs the item it was made from', () {
      final copycat = SchematicRequirements();
      copycat.itemOfBlock = (k) => k;
      copycat.blockEntityTypeOf = (k) =>
          k == 'create:copycat_panel' ? 'create:copycat' : null;
      registerSpecialBlockRequirements(copycat);
      final nbt = BinaryNbt.write(
        NbtValue.compound({
          'Item': NbtValue.compound({
            'id': const NbtValue.string('minecraft:stone'),
            'count': const NbtValue.int32(1),
          }),
          'Material': NbtValue.compound({
            'Name': const NbtValue.string('minecraft:stone'),
          }),
        }),
      );
      expect(
        copycat
            .ofBlock(const BState('create:copycat_panel'), nbt)
            .requiredItems
            .map((e) => e.item),
        ['create:copycat_panel', 'minecraft:stone'],
      );
      // A copycat without a material needs only its own item.
      expect(
        copycat
            .ofBlock(const BState('create:copycat_panel'), null)
            .requiredItems
            .map((e) => e.item),
        ['create:copycat_panel'],
      );
    });
  });

  group('safe nbt', () {
    test('a printed copycat keeps its item and material', () {
      final hooks = SchematicHooks();
      registerCreateSafeNbtWriters(hooks);
      final writer = hooks.safeNbtWriters['create:copycat_panel']!;
      final data = writer(
        const BState('create:copycat_panel'),
        BinaryNbt.write(
          NbtValue.compound({
            'id': const NbtValue.string('create:copycat'),
            'Item': NbtValue.compound({
              'id': const NbtValue.string('minecraft:stone'),
              'count': const NbtValue.int32(1),
              'components': NbtValue.compound({
                'minecraft:custom_name': const NbtValue.string('x'),
              }),
            }),
            'Material': NbtValue.compound({
              'Name': const NbtValue.string('minecraft:stone'),
            }),
            'ClientOnly': const NbtValue.string('drop me'),
          }),
        ),
      );
      final kept = BinaryNbt.read(data!)!.root.asCompound;
      expect(kept.containsKey('ClientOnly'), isFalse);
      expect(kept['Item']!.asCompound['id']!.value, 'minecraft:stone');
      // `ItemStack.CODEC` of `DataComponentPatch.EMPTY`: the components are not copied.
      expect(kept['Item']!.asCompound.containsKey('components'), isFalse);
      expect(kept['Material']!.asCompound['Name']!.value, 'minecraft:stone');
    });

    test('safe behaviours survive, a table cloth keeps none of its filter', () {
      final data = safeBlockEntityData(
        const BState('create:white_table_cloth'),
        BinaryNbt.write(
          NbtValue.compound({
            'id': const NbtValue.string('create:table_cloth'),
            'Filter': NbtValue.compound({
              'id': const NbtValue.string('minecraft:stone'),
            }),
            'FilterAmount': const NbtValue.int32(4),
            'ScrollValue': const NbtValue.int32(2),
            'Bracket': NbtValue.compound({
              'Name': const NbtValue.string('minecraft:oak_log'),
            }),
          }),
        ),
      );
      final kept = BinaryNbt.read(data!)!.root.asCompound;
      expect(kept.containsKey('Filter'), isFalse);
      expect(kept.containsKey('FilterAmount'), isFalse);
      expect(kept['ScrollValue']!.value, 2);
      expect(kept['Bracket']!.asCompound['Name']!.value, 'minecraft:oak_log');
    });
  });

  test('material checklist', () {
    final c = MaterialChecklist();
    c.require(ItemRequirement.of1(ItemUseType.consume, 'minecraft:stone', 70));
    c.require(ItemRequirement.of1(ItemUseType.consume, 'minecraft:oak_log', 3));
    c.require(ItemRequirement.of1(ItemUseType.damage, 'minecraft:shears', 5));
    c.maxDamageOf = (k) => k == 'minecraft:shears' ? 238 : 1;
    c.collect('minecraft:stone', 70);
    c.collect('minecraft:dirt', 1000); // not needed
    expect(c.gathered.containsKey('minecraft:dirt'), isFalse);
    expect(c.getRequiredAmount('minecraft:shears'), 1);
    final e = c.entries();
    expect(e.completed.single.$1, 'minecraft:stone');
    expect(e.missing.map((m) => m.$1), [
      'minecraft:oak_log',
      'minecraft:shears',
    ]);
    expect(
      MaterialChecklist.entryText(
        'minecraft:stone',
        70,
        unfinished: true,
        forBook: true,
      ),
      'Stone\n x70 | 1▤ +6\n',
    );
    expect(c.bookPages().length, 1);
    expect(c.clipboardPages().single.first.icon, 'minecraft:oak_log');
    expect(c.clipboardPages().single.first.text, 'Oak Log\n x3 | 0\u25A4 +3');
  });

  group('launched items', () {
    test('flight time and persistence', () {
      final l = LaunchedBlock.launch(
        (0, 64, 0),
        (16, 64, 0),
        const SlotStack('minecraft:stone', 1),
        stone,
        null,
      );
      expect(l.totalTicks, 16);
      var ticks = 0;
      while (!l.update()) {
        ticks++;
      }
      expect(ticks, 16);
      final back = LaunchedItem.fromTag(l.toTag());
      expect(back, isA<LaunchedBlock>());
      expect((back as LaunchedBlock).state, stone);
    });

    test('belt segments', () {
      const belt = BState('create:belt', {
        'facing': 'east',
        'slope': 'upward',
        'part': 'start',
      });
      expect(nextBeltSegment(belt, (0, 0, 0), true), (1, 1, 0));
      expect(nextBeltSegment(belt, (0, 0, 0), false), isNull);
      expect(stripBeltIfNotLast(belt.setValue('part', 'middle')), BState.air);
      expect(stripBeltIfNotLast(belt).key, 'create:shaft');
      expect(
        stripBeltIfNotLast(belt.setValue('part', 'end')).key,
        'create:belt',
      );
    });
  });

  group('schematicannon', () {
    test('prints a small schematic', () async {
      final schematic = SchematicWorld((10, 64, 10))
        ..setBlock((0, 0, 0), const SchematicBlock(stone))
        ..setBlock((1, 0, 0), const SchematicBlock(stone));
      final real = <Pos, BState>{};
      final env = _Env(_View(real), schematic);
      env.requirements.itemOfBlock = (k) => k;
      final cannon = SchematicannonCore();
      cannon.inventory[CannonSlot.blueprint] = const SlotStack(
        'create:schematic',
        1,
      );
      cannon.configure(CannonOption.play, true);
      await cannon.tick(env); // the printer initializes and waits ("ready")
      expect(cannon.statusMsg, 'ready');
      expect(cannon.blocksToPlace, 2);
      cannon.configure(CannonOption.play, true);
      for (var i = 0; i < 400 && cannon.statusMsg != 'finished'; i++) {
        await cannon.tick(env);
      }
      expect(cannon.statusMsg, 'finished');
      for (var i = 0; i < 40; i++) {
        await cannon.tick(env); // the last shots land
      }
      expect(
        env.placed.whereType<LaunchedBlock>().map((l) => l.target).toSet(),
        {(10, 64, 10), (11, 64, 10)},
      );
      expect(env.fired, 2);
      expect(env.finished, 1);
      expect(env.chest['minecraft:stone'], 98);
      expect(
        cannon.inventory[CannonSlot.blueprintOutput].item,
        'create:empty_schematic',
      );
      expect(cannon.inventory[CannonSlot.blueprint].isEmpty, isTrue);
      expect(cannon.state, CannonState.stopped);
    });

    test('pauses on a missing item and resumes when it is skipped', () async {
      final schematic = SchematicWorld((10, 64, 10))
        ..setBlock((
          0,
          0,
          0,
        ), const SchematicBlock(BState('minecraft:gold_block')));
      final env = _Env(_View({}), schematic)
        ..requirements.itemOfBlock = ((k) => k);
      final cannon = SchematicannonCore();
      cannon.inventory[CannonSlot.blueprint] = const SlotStack(
        'create:schematic',
        1,
      );
      cannon.configure(CannonOption.play, true);
      await cannon.tick(env);
      cannon.configure(CannonOption.play, true);
      for (var i = 0; i < 20; i++) {
        await cannon.tick(env);
      }
      expect(cannon.statusMsg, 'missingBlock');
      expect(cannon.state, CannonState.paused);
      expect(cannon.missingItem?.item, 'minecraft:gold_block');
      cannon.skipMissing = true;
      cannon.configure(CannonOption.skipMissing, true);
      cannon.configure(CannonOption.play, true);
      for (var i = 0; i < 20; i++) {
        await cannon.tick(env);
      }
      expect(cannon.statusMsg, 'finished');
    });

    test(
      'stops without a deployed schematic and respects the replace mode',
      () async {
        final env = _Env(_View({}), null);
        final cannon = SchematicannonCore();
        cannon.inventory[CannonSlot.blueprint] = const SlotStack(
          'create:schematic',
          1,
        );
        cannon.configure(CannonOption.play, true);
        await cannon.tick(env);
        expect(cannon.statusMsg, 'schematicInvalid');
        // replace modes
        final c = SchematicannonCore();
        final e = _Env(_View({}), null)..requirements.itemOfBlock = ((k) => k);
        c.replaceMode = 0; // don't replace solid blocks
        expect(
          c.shouldPlace(e, (20, 64, 20), stone, null, stone, null, true),
          isFalse,
        );
        expect(
          c.shouldPlace(e, (20, 64, 20), stone, null, air, null, true),
          isTrue,
        );
        c.replaceMode = 2;
        expect(
          c.shouldPlace(e, (20, 64, 20), stone, null, stone, null, true),
          isTrue,
        );
        expect(
          c.shouldPlace(e, (20, 64, 20), air, null, stone, null, false),
          isFalse,
        ); // placing air
        c.replaceMode = 3;
        expect(
          c.shouldPlace(e, (20, 64, 20), air, null, stone, null, false),
          isTrue,
        );
        // too close to the cannon
        expect(
          c.shouldPlace(e, (1, 64, 0), stone, null, air, null, true),
          isFalse,
        );
      },
    );

    test(
      'protects vanilla block entities unless replacing them is allowed',
      () {
        final env = _Env(_View({}), null)
          ..requirements.itemOfBlock = ((k) => k);
        final cannon = SchematicannonCore()..replaceMode = 3;
        const chest = BState('minecraft:chest');
        expect(
          cannon.shouldPlace(env, (20, 64, 20), stone, null, chest, null, true),
          isFalse,
        );
        cannon.replaceBlockEntities = true;
        expect(
          cannon.shouldPlace(env, (20, 64, 20), stone, null, chest, null, true),
          isTrue,
        );
      },
    );
  });

  group('upload receiver', () {
    test('uploads in chunks and delivers', () {
      final store = MemorySchematicStore();
      final delivered = <String>[];
      final target = _Target(delivered);
      final r = SchematicUploadReceiver(store);
      expect(
        r.handleNewUpload('Steve', 'house.nbt', 6, target),
        UploadResult.started,
      );
      expect(target.started, ['house.nbt']);
      r.handleWriteRequest('Steve', 'house.nbt', [1, 2, 3]);
      expect(target.lastProgress, 0.5);
      r.handleWriteRequest('Steve', 'house.nbt', [4, 5, 6]);
      r.handleFinishedUpload('Steve', 'house.nbt');
      expect(
        store.files['schematics/uploaded/Steve/house.nbt'],
        Uint8List.fromList([1, 2, 3, 4, 5, 6]),
      );
      expect(delivered, ['Steve/house.nbt']);
      expect(r.activeCount, 0);
    });

    test('rejects traversal, formats, sizes and extra data', () {
      final store = MemorySchematicStore();
      final r = SchematicUploadReceiver(
        store,
        limits: const SchematicLimits(
          maxTotalSchematicSize: 1,
          maxSchematicPacketSize: 4,
        ),
      );
      final t = _Target([]);
      expect(
        r.handleNewUpload('Steve', '../evil.nbt', 1, t),
        UploadResult.pathTraversal,
      );
      expect(
        r.handleNewUpload('../Steve', 'a.nbt', 1, t),
        UploadResult.pathTraversal,
      );
      expect(
        r.handleNewUpload('Steve', 'a.txt', 1, t),
        UploadResult.wrongFormat,
      );
      var msg = '';
      expect(
        r.handleNewUpload(
          'Steve',
          'a.nbt',
          5000,
          t,
          onTooLarge: (a, b) => msg = b,
        ),
        UploadResult.tooLarge,
      );
      expect(msg, contains('1 KB'));
      expect(
        r.handleNewUpload('Steve', 'a.nbt', 100, null),
        UploadResult.noTable,
      );
      expect(r.handleNewUpload('Steve', 'a.nbt', 100, t), UploadResult.started);
      expect(
        r.handleNewUpload('Steve', 'a.nbt', 100, t),
        UploadResult.alreadyActive,
      );
      r.handleWriteRequest('Steve', 'a.nbt', [
        1,
        2,
        3,
        4,
        5,
      ]); // oversized packet cancels
      expect(r.activeCount, 0);
      expect(store.files, isEmpty);
      expect(t.finished, 1);
    });

    test('deletes the oldest when over quota; times out idle uploads', () {
      final store = MemorySchematicStore();
      final r = SchematicUploadReceiver(
        store,
        limits: const SchematicLimits(
          maxSchematics: 2,
          schematicIdleTimeout: 3,
        ),
      );
      store.write('schematics/uploaded/Steve/old.nbt', [1]);
      store.write('schematics/uploaded/Steve/new.nbt', [1]);
      final t = _Target([]);
      expect(
        r.handleNewUpload('Steve', 'fresh.nbt', 10, t),
        UploadResult.started,
      );
      expect(store.exists('schematics/uploaded/Steve/old.nbt'), isFalse);
      expect(store.exists('schematics/uploaded/Steve/new.nbt'), isTrue);
      for (var i = 0; i < 6; i++) {
        r.tick();
      }
      expect(r.activeCount, 0);
      expect(store.exists('schematics/uploaded/Steve/fresh.nbt'), isFalse);
    });

    test('export names', () {
      final store = MemorySchematicStore();
      final r = SchematicUploadReceiver(store);
      expect(r.exportName('Steve', '', overwrite: false), 'my_schematic.nbt');
      store.write('schematics/uploaded/Steve/my_schematic.nbt', [1]);
      expect(
        r.exportName('Steve', 'My Schematic', overwrite: false),
        'my_schematic_1.nbt',
      );
      expect(r.exportName('Steve', 'Keep Me', overwrite: true), 'Keep Me.nbt');
    });
  });

  test('schematic stack data round trips through components', () {
    final data =
        SchematicStackData.create(
          'house.nbt',
          'Steve',
          bounds: (3, 4, 5),
        ).copyWith(
          anchor: (100, 64, -200),
          rotation: BlockRotation.clockwise180,
          mirror: BlockMirror.frontBack,
          deployed: true,
        );
    final comps = data.toComponents();
    final back = SchematicStackData.fromComponents({
      for (final e in comps.entries)
        if (e.value != null) e.key: e.value!,
    });
    expect(back.file, 'house.nbt');
    expect(back.owner, 'Steve');
    expect(back.deployed, true);
    expect(back.anchor, (100, 64, -200));
    expect(back.rotation, BlockRotation.clockwise180);
    expect(back.mirror, BlockMirror.frontBack);
    expect(back.bounds, (3, 4, 5));
    // entity nbt transform
    final entityNbt = NbtValue.compound({
      'id': const NbtValue.string('minecraft:armor_stand'),
      'Pos': NbtValue.list([
        const NbtValue.double64(1),
        const NbtValue.double64(2),
        const NbtValue.double64(3),
      ]),
      'Rotation': NbtValue.list([
        const NbtValue.float(90),
        const NbtValue.float(0),
      ]),
    });
    final w = SchematicWorld.fromTemplate(
      TemplateData(
        (2, 2, 2),
        const [],
        [
          TemplateEntity(
            (1.5, 0.0, 0.5),
            (1, 0, 0),
            BinaryNbtHelper.bytes(entityNbt),
          ),
        ],
      ),
      anchor: (0, 0, 0),
      rotation: BlockRotation.clockwise90,
    );
    expect(
      w.entities.single.relativePos.$1,
      closeTo(1.0 - 0.5, 1e-9),
    ); // -z... (x,z)=(1.5,0.5): (i+j+1-d2 ...)
  });
}

final class _Target implements UploadTarget {
  final List<String> delivered;
  final List<String> started = [];
  double lastProgress = 0;
  int finished = 0;
  _Target(this.delivered);

  @override
  void startUpload(String schematic) => started.add(schematic);

  @override
  void progress(double fraction) => lastProgress = fraction;

  @override
  void finishUpload() => finished++;

  @override
  void deliver(String schematic, String owner) =>
      delivered.add('$owner/$schematic');

  @override
  bool get isValid => true;
}

abstract final class BinaryNbtHelper {
  static List<int> bytes(NbtValue v) => BinaryNbt.write(v);
}
