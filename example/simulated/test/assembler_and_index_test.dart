import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:sable/sable.dart'
    show
        BoundingBox3d,
        ConstraintJointAxis,
        PhysicsConstraintHandle,
        Quaterniond,
        SubLevel,
        Vector3d;
import 'package:simulated/simulated.dart';
import 'package:test/test.dart';

void main() {
  setUp(() => SimConfigService.instance.load(SimConfig.defaults));

  group('PhysicsAssemblerLogic', () {
    test('the lever flick moves to the target angle', () {
      final logic = PhysicsAssemblerLogic();
      logic.flickLeverTo(true);
      for (var i = 0; i < 100; i++) {
        logic.tickLever();
      }
      expect(logic.visualAngle.value, closeTo(PhysicsAssemblerLogic.flickedAngleDegrees, 0.01));

      logic.flickLeverTo(false);
      for (var i = 0; i < 100; i++) {
        logic.tickLever();
      }
      expect(logic.visualAngle.value, closeTo(0, 0.01));
    });

    test('a held lever does not move', () {
      final logic = PhysicsAssemblerLogic()
        ..flickLeverTo(true)
        ..jerkLever()
        ..holdingLever = true;
      final before = logic.visualAngle.value;
      logic.tickLever();
      expect(logic.visualAngle.value, before);
    });

    test('the alignment needs six ticks within tolerance', () {
      final logic = PhysicsAssemblerLogic()..disassembling = true;
      expect(
        logic.tickDisassemblingWith(angleError: 0.001, distanceToGoal: 0.01),
        isFalse,
      );
      // Five more ready ticks, then the goal.
      for (var i = 0; i < 5; i++) {
        logic.tickDisassemblingWith(angleError: 0.001, distanceToGoal: 0.01);
      }
      expect(
        logic.tickDisassemblingWith(angleError: 0.001, distanceToGoal: 0.01),
        isTrue,
      );
    });

    test('a tilt outside the tolerance resets the counter', () {
      final logic = PhysicsAssemblerLogic()..disassembling = true;
      for (var i = 0; i < 5; i++) {
        logic.tickDisassemblingWith(angleError: 0.001, distanceToGoal: 0.01);
      }
      expect(logic.disassemblyReadyTicks, 5);
      logic.tickDisassemblingWith(angleError: 0.5, distanceToGoal: 0.01);
      expect(logic.disassemblyReadyTicks, 0);
    });

    test('the alignment times out', () {
      SimConfigService.instance.loadFromMap({
        'server': {
          'assembly': {'maxDisassemblyTicks': 5},
        },
      });
      final logic = PhysicsAssemblerLogic()..disassembling = true;
      for (var i = 0; i < 25; i++) {
        logic.tickDisassemblingWith(angleError: 1, distanceToGoal: 1);
      }
      expect(logic.disassembling, isFalse);
      expect(logic.lastException?.translationKey, contains('could_not_align'));
    });

    test('startDisassembling picks the closest quarter turn', () {
      final logic = PhysicsAssemblerLogic();
      final turns = logic.startDisassembling(Quaterniond());
      expect(turns, 0);
      expect(logic.disassembling, isTrue);
      expect(logic.disassemblyOrientation, isNotNull);
    });

    test('the checks reject out-of-world, too fast and mid-air', () {
      final logic = PhysicsAssemblerLogic();
      final bounds = BoundingBox3d()..setValues(-1, 0, -1, 1, 1, 1);

      expect(
        () => logic.checkDisassemblyAllowed(
          bounds: BoundingBox3d()..setValues(0, 400, 0, 1, 401, 1),
          minY: -64,
          maxY: 320,
          linearVelocity: Vector3d(),
          angularVelocity: Vector3d(),
          hasTerrainNearby: true,
        ),
        throwsA(isA<SimAssemblyException>()),
      );

      expect(
        () => logic.checkDisassemblyAllowed(
          bounds: bounds,
          minY: -64,
          maxY: 320,
          linearVelocity: Vector3d(100, 0, 0),
          angularVelocity: Vector3d(),
          hasTerrainNearby: true,
        ),
        throwsA(isA<SimAssemblyException>()),
      );

      expect(
        () => logic.checkDisassemblyAllowed(
          bounds: bounds,
          minY: -64,
          maxY: 320,
          linearVelocity: Vector3d(),
          angularVelocity: Vector3d(),
          hasTerrainNearby: false,
        ),
        throwsA(isA<SimAssemblyException>()),
      );

      logic.checkDisassemblyAllowed(
        bounds: bounds,
        minY: -64,
        maxY: 320,
        linearVelocity: Vector3d(),
        angularVelocity: Vector3d(),
        hasTerrainNearby: true,
      );
    });

    test('the sticky face follows the block state', () {
      expect(stickyFacing('floor', Direction.north), Direction.down);
      expect(stickyFacing('ceiling', Direction.north), Direction.up);
      expect(stickyFacing('wall', Direction.east), Direction.west);
    });

    test('the player control can be released once', () {
      final logic = PhysicsAssemblerLogic();
      expect(logic.stopControllingPlayer(), isFalse);
      logic.updateControlledByPlayer(12);
      expect(logic.controlledByPlayer, isTrue);
      expect(logic.stopControllingPlayer(), isTrue);
      expect(logic.stopControllingPlayer(), isFalse);
    });
  });

  group('DisassemblyPrevention', () {
    tearDown(DisassemblyPrevention.clear);

    test('only the primary assembler may disassemble when the config says so', () {
      DisassemblyPrevention.setPrimary('sub-level-1', (10, 64, 10));

      expect(
        () => DisassemblyPrevention.checkSubLevelForPrimary(
          primaryDisassembly: true,
          containingSubLevelId: 'sub-level-1',
          toCheck: (20, 64, 20),
        ),
        throwsA(isA<SimAssemblyException>()),
      );

      DisassemblyPrevention.checkSubLevelForPrimary(
        primaryDisassembly: true,
        containingSubLevelId: 'sub-level-1',
        toCheck: (10, 64, 10),
      );

      // Disabled: anyone may disassemble.
      DisassemblyPrevention.checkSubLevelForPrimary(
        primaryDisassembly: false,
        containingSubLevelId: 'sub-level-1',
        toCheck: (20, 64, 20),
      );
    });

    test('an unknown sub-level has no primary', () {
      DisassemblyPrevention.checkSubLevelForPrimary(
        primaryDisassembly: true,
        containingSubLevelId: 'unknown',
        toCheck: (0, 0, 0),
      );
    });

    test('clearing the primary releases the sub-level', () {
      DisassemblyPrevention.setPrimary('sub-level-2', (1, 2, 3));
      DisassemblyPrevention.setPrimary('sub-level-2', null);
      expect(DisassemblyPrevention.primaryAssemblerOf('sub-level-2'), isNull);
    });
  });

  group('SimServices', () {
    test('sticky blocks stick to each other and to everything else', () {
      final services = SimServices();
      const slime = BState('minecraft:slime_block');
      const honey = BState('minecraft:honey_block');
      const stone = BState('minecraft:stone');

      expect(services.canStickTo(slime, honey), isFalse);
      expect(services.canStickTo(slime, slime), isTrue);
      expect(services.canStickTo(slime, stone), isTrue);
      expect(services.canStickTo(stone, stone), isFalse);
    });

    test('the dye colours are recognised', () {
      expect(SimServices.dyeColorOf('minecraft:red_dye'), 'red');
      expect(SimServices.dyeColorOf('minecraft:light_blue_dye'), 'light_blue');
      expect(SimServices.dyeColorOf('minecraft:stick'), isNull);
    });
  });

  group('SimSoundEvents', () {
    test('every event is namespaced and has a unique key', () {
      final keys = <String>{};
      for (final sound in SimSoundEvents.all) {
        expect(sound.key, startsWith('simulated:'));
        expect(keys.add(sound.key), isTrue, reason: 'duplicate ${sound.key}');
      }
    });

    test('the assembler sounds the assembler uses are registered', () {
      final keys = SimSoundEvents.all.map((s) => s.key).toSet();
      expect(keys, contains('simulated:block.physics_assembler.assemble'));
      expect(keys, contains('simulated:block.physics_assembler.disassemble'));
      expect(keys, contains('simulated:block.physics_assembler.fail'));
    });

    test('the file variants are numbered as the resource pack names them', () {
      final moves = SimSoundEvents.simulatedContraptionMoves;
      expect(moves.files, hasLength(5));
      expect(moves.files.first.name, 'block/physics_assembler/assemble1');
    });
  });

  group('SimLiftProviders', () {
    tearDown(SimLiftProviders.clear);

    test('registers the sails and answers with their normal', () {
      registerSimLiftProviders();
      final provider = SimLiftProviders.providerOf('simulated:red_symmetric_sail');
      expect(provider, isNotNull);

      final context = SimLiftProviders.contextOf(
        (1, 2, 3),
        const BState('simulated:red_symmetric_sail', {'axis': 'x'}),
      )!;
      expect(context.pos, (1, 2, 3));
      expect(context.dir.x, 1);
    });

    test('a block without a provider has no context', () {
      registerSimLiftProviders();
      expect(
        SimLiftProviders.contextOf((0, 0, 0), const BState('minecraft:stone')),
        isNull,
      );
    });

    test('contextsFor skips the blocks that are not providers', () {
      registerSimLiftProviders();
      final contexts = SimLiftProviders.contextsFor(
        [(0, 0, 0), (1, 0, 0)],
        (pos) => pos.$1 == 0
            ? const BState('simulated:white_symmetric_sail', {'axis': 'y'})
            : const BState('minecraft:stone'),
      );
      expect(contexts, hasLength(1));
      expect(contexts.keys, contains((0, 0, 0)));
    });
  });

  group('SimpleResourceManager', () {
    test('indexes by id and by value', () {
      final manager = SimpleResourceManager<int>('simulated:test')..apply({'a': 1, 'b': 2});
      expect(manager.get('a'), 1);
      expect(manager.idOf(2), 'b');
      expect(manager.values, hasLength(2));
    });

    test('a sorted manager orders the values', () {
      final manager = SimpleResourceManager<int>.sorted('simulated:test', comparator: (a, b) => a.compareTo(b))
        ..apply({'a': 3, 'b': 1, 'c': 2});
      expect(manager.sortedEntries, [1, 2, 3]);
    });

    test('clearing empties the manager', () {
      final manager = SimpleResourceManager<int>('simulated:test')..apply({'a': 1});
      manager.clear();
      expect(manager.get('a'), isNull);
    });

    test('the in-memory registry keeps the managers by path', () {
      final registry = InMemoryResourceManagerRegistry();
      final manager = SimpleResourceManager<int>('simulated:test');
      registry.registerListener(manager.path, manager);
      expect(registry.managers['simulated:test'], same(manager));
    });
  });

  group('SimAssemblyEvents', () {
    tearDown(SimAssemblyEvents.clear);

    test('a listener hears every assembly and can be removed', () {
      final heard = <(String, (int, int, int))>[];
      final remove = SimAssemblyEvents.onAssembled((worldId, anchor, result) {
        heard.add((worldId, anchor));
      });

      final subLevel = _StubSubLevel();
      SimAssemblyEvents.notifyAssembled('minecraft:overworld', (1, 2, 3), SimAssemblyResult(subLevel, (4, 5, 6)));
      expect(heard, [('minecraft:overworld', (1, 2, 3))]);

      remove();
      SimAssemblyEvents.notifyAssembled('minecraft:overworld', (7, 8, 9), SimAssemblyResult(subLevel, (0, 0, 0)));
      expect(heard, hasLength(1));
    });

    test('the disassembly listener is separate', () {
      var assembled = 0;
      var disassembled = 0;
      SimAssemblyEvents.onAssembled((_, _, _) => assembled++);
      SimAssemblyEvents.onDisassembled((_, _, _) => disassembled++);

      SimAssemblyEvents.notifyDisassembled('minecraft:overworld', (0, 0, 0), Object());
      expect(disassembled, 1);
      expect(assembled, 0);
    });

    test('the disassembly carries the world, the anchor and the sub-level', () {
      final heard = <(String, (int, int, int), Object)>[];
      SimAssemblyEvents.onDisassembled((worldId, anchor, subLevel) {
        heard.add((worldId, anchor, subLevel));
      });

      final subLevel = _StubSubLevel();
      SimAssemblyEvents.notifyDisassembled('minecraft:the_nether', (4, 70, -9), subLevel);

      expect(heard, hasLength(1));
      expect(heard.single.$1, 'minecraft:the_nether');
      expect(heard.single.$2, (4, 70, -9));
      expect(heard.single.$3, same(subLevel));
    });
  });

  group('AssemblyAlignmentMotors', () {
    test('the gains are the Java constants', () {
      expect(AssemblyAlignmentMotors.linearStiffness, 1000);
      expect(AssemblyAlignmentMotors.linearDamping, 50);
      expect(AssemblyAlignmentMotors.angularStiffness, 13000);
      expect(AssemblyAlignmentMotors.angularDamping, 1000);
    });

    test('every joint axis gets a motor', () {
      final motors = AssemblyAlignmentMotors.motors(
        localGoal: Vector3d(1, 2, 3),
        tightenLinear: true,
      );
      expect(motors, hasLength(6));
      expect(
        motors.map((m) => m.$1).toSet(),
        {
          ConstraintJointAxis.linearX,
          ConstraintJointAxis.linearY,
          ConstraintJointAxis.linearZ,
          ConstraintJointAxis.angularX,
          ConstraintJointAxis.angularY,
          ConstraintJointAxis.angularZ,
        },
      );
    });

    test('the angular axes are held at zero rotation', () {
      final motors = AssemblyAlignmentMotors.motors(localGoal: Vector3d());
      for (final axis in AssemblyAlignmentMotors.angularAxes) {
        final motor = motors.firstWhere((m) => m.$1 == axis);
        expect(motor.$2, 0);
        expect(motor.$3, AssemblyAlignmentMotors.angularStiffness);
        expect(motor.$4, AssemblyAlignmentMotors.angularDamping);
      }
    });

    test('the linear axes target the local goal and tighten on request', () {
      final soft = AssemblyAlignmentMotors.motors(localGoal: Vector3d(4, 5, 6));
      expect(soft.firstWhere((m) => m.$1 == ConstraintJointAxis.linearX).$2, 4);
      expect(soft.firstWhere((m) => m.$1 == ConstraintJointAxis.linearY).$2, 5);
      expect(soft.firstWhere((m) => m.$1 == ConstraintJointAxis.linearZ).$2, 6);
      expect(soft.firstWhere((m) => m.$1 == ConstraintJointAxis.linearX).$3, 0.000001);

      final tight = AssemblyAlignmentMotors.motors(
        localGoal: Vector3d(4, 5, 6),
        tightenLinear: true,
      );
      expect(
        tight.firstWhere((m) => m.$1 == ConstraintJointAxis.linearX).$3,
        AssemblyAlignmentMotors.linearStiffness,
      );
    });

    test('apply writes every motor to the handle', () {
      final handle = _RecordingConstraintHandle();
      AssemblyAlignmentMotors.apply(
        handle,
        AssemblyAlignmentMotors.motors(localGoal: Vector3d(1, 1, 1)),
      );
      expect(handle.motors, hasLength(6));
      expect(handle.contactsEnabled, isTrue);
    });
  });

  group('Glue geometry', () {
    test('the glue span covers both blocks', () {
      final span = glueSpan((0, 0, 0), (1, 0, 0));
      expect(span.minX, 0);
      expect(span.maxX, 2);
      expect(span.ySize, 1);
    });

    test('a glue box contains block centres', () {
      const glue = SimGlueBox(1, Aabb(0, 0, 0, 2, 1, 1));
      expect(glue.contains((0, 0, 0)), isTrue);
      expect(glue.contains((1, 0, 0)), isTrue);
      expect(glue.contains((2, 0, 0)), isFalse);
    });
  });
}

/// A constraint handle that records what was set on it.
final class _RecordingConstraintHandle implements PhysicsConstraintHandle {
  final List<(int, double, double, double)> motors = [];
  bool contactsEnabled = true;
  bool removed = false;

  @override
  void setMotor(int axis, double target, double stiffness, double damping, bool hasMaxForce, double maxForce) {
    motors.add((axis, target, stiffness, damping));
  }

  @override
  void setContactsEnabled(bool enabled) => contactsEnabled = enabled;

  @override
  void getJointImpulses(Vector3d linearImpulseDest, Vector3d angularImpulseDest) {}

  @override
  void remove() => removed = true;

  @override
  bool get isValid => !removed;
}

/// A sub-level that does nothing: the event tests never touch it.
final class _StubSubLevel implements SubLevel {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
