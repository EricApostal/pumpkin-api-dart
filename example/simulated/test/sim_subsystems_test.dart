// State-machine tests for the subsystems that need no physics: the typewriter's
// key table and key handling, the honey glue volume rules, the spring and
// merging-glue placement rules, the rope strand, the diagram frame builder and
// the physics staff's pure pieces.
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/direction.dart' show Direction;
// create's internals are pure but not exported from the barrel.
// ignore_for_file: implementation_imports
import 'package:sable/sable.dart' show Vector3d;
import 'package:simulated/simulated.dart';
import 'package:test/test.dart';

void main() {
  group('LinkedTypewriterEntries', () {
    KeyboardEntry entry(int key) => KeyboardEntry(glfwKeyCode: key);

    test('a key is set, activated and reported as transmitting', () {
      final entries = LinkedTypewriterEntries();
      entries.setKey(65, entry(65));

      expect(entries.size, 1);
      expect(entries.getEntry(65)!.transmittedStrength, 0);

      final added = <int>[];
      entries.activateKey(65);
      entries.updateNetworks(add: (e) => added.add(e.glfwKeyCode), remove: (_) {});
      expect(added, [65]);
      expect(entries.getEntry(65)!.transmittedStrength, 15);
      expect(entries.getEntry(65)!.isAlive, isTrue);
    });

    test('setting a key over an existing one deactivates the old entry', () {
      final entries = LinkedTypewriterEntries();
      final old = entry(65);
      entries
        ..setKey(65, old)
        ..activateKey(65)
        ..setKey(65, entry(66));
      expect(old.isAlive, isFalse);
    });

    test('setKey(null) removes the key', () {
      final entries = LinkedTypewriterEntries()..setKey(65, entry(65));
      entries.setKey(65, null);
      expect(entries.size, 0);
    });

    test('a key activated and deactivated in one tick ends deactivated', () {
      final entries = LinkedTypewriterEntries()..setKey(65, entry(65));
      final added = <int>[];
      final removed = <int>[];

      entries
        ..activateKey(65)
        ..deactivateKey(65)
        ..updateNetworks(add: (e) => added.add(e.glfwKeyCode), remove: (e) => removed.add(e.glfwKeyCode));

      // Activations are applied first, then deactivations, so the last word is
      // the deactivation.
      expect(added, [65]);
      expect(removed, [65]);
      expect(entries.getEntry(65)!.isAlive, isFalse);
    });

    test('clearAll drops the keys and the pending network updates', () {
      final entries = LinkedTypewriterEntries()..setKey(65, entry(65));
      final added = <int>[];
      final removed = <int>[];
      entries
        ..activateKey(65)
        ..clearAll()
        ..updateNetworks(add: (e) => added.add(e.glfwKeyCode), remove: (e) => removed.add(e.glfwKeyCode));

      expect(entries.size, 0);
      expect(added, isEmpty);
      expect(removed, isEmpty);
    });

    test('deactivateAll queues only the live entries', () {
      final entries = LinkedTypewriterEntries()
        ..setKey(65, entry(65))
        ..setKey(66, entry(66))
        ..activateKey(65);
      final removed = <int>[];
      entries
        ..deactivateAll()
        ..updateNetworks(add: (_) {}, remove: (e) => removed.add(e.glfwKeyCode));
      expect(removed, [65]);
    });

    test('addAll keeps the wire order of the sent map', () {
      final entries = LinkedTypewriterEntries()
        ..addAll({66: entry(66), 65: entry(65)});
      expect(entries.entries.map((e) => e.glfwKeyCode), [66, 65]);
    });
  });

  group('LinkedTypewriterLogic', () {
    test('only the current user may type', () {
      final logic = LinkedTypewriterLogic()..connectUser('a');
      expect(logic.connectUser('b'), isFalse);
      expect(logic.checkUser('b'), isFalse);

      logic.onKeyInteraction(user: 'b', key: 65, press: true);
      expect(logic.typedEntry, isEmpty);

      logic.onKeyInteraction(user: 'a', key: 65, press: true);
      expect(logic.typedEntry, 'A');
    });

    test('the text drops its oldest character once it reaches 25', () {
      final logic = LinkedTypewriterLogic()..connectUser('a');
      for (var i = 0; i < 30; i++) {
        logic.pressKey(66);
      }
      // The trim runs after the append, so 24 characters survive.
      expect(logic.typedEntry, hasLength(LinkedTypewriterLogic.typedEntryTrimThreshold - 1));
      expect(logic.typedEntry, 'B' * 24);
    });

    test('backspace deletes a character and types nothing', () {
      final logic = LinkedTypewriterLogic()..connectUser('a');
      logic
        ..pressKey(65)
        ..pressKey(backspace())
        ..pressKey(66);
      expect(logic.typedEntry, 'B');
      // The backspace is tracked as a pressed key.
      expect(logic.pressedKeys, contains(LinkedTypewriterLogic.backspaceKey));
    });

    test('releasing a key clears it and deactivates the entry', () {
      final logic = LinkedTypewriterLogic()..connectUser('a');
      logic.entries.setKey(65, KeyboardEntry(glfwKeyCode: 65));
      logic
        ..pressKey(65)
        ..releaseKey(65);
      expect(logic.pressedKeys, isEmpty);
      expect(logic.entries.getEntry(65)!.isAlive, isFalse);
    });

    test('a press with an entry binds the key instead of typing', () {
      final logic = LinkedTypewriterLogic()..connectUser('a');
      final bind = KeyboardEntry(glfwKeyCode: 65);
      logic.onKeyInteraction(user: 'a', toBind: bind, key: 65, press: true);
      expect(logic.entries.getEntry(65), same(bind));
      expect(logic.typedEntry, isEmpty);
    });

    test('disconnectUser clears the user and every entry', () {
      final logic = LinkedTypewriterLogic()..connectUser('a');
      logic.entries.setKey(65, KeyboardEntry(glfwKeyCode: 65));
      logic
        ..pressKey(65)
        ..disconnectUser();
      expect(logic.isInUse, isFalse);
      expect(logic.pressedKeys, isEmpty);
      expect(logic.entries.getEntry(65)!.isAlive, isFalse);
    });
  });

  group('TypewriterSaveLogic', () {
    test('a save replaces the table and stamps the position', () {
      final entries = LinkedTypewriterEntries()..setKey(1, KeyboardEntry(glfwKeyCode: 1));
      final changed = {65: KeyboardEntry(glfwKeyCode: 65)};

      expect(TypewriterSaveLogic.apply(entries, changed, const (2, 3, 4), clearAll: false), isFalse);
      expect(entries.entries.map((e) => e.glfwKeyCode), [65]);
      expect(entries.getEntry(65)!.pos, const (2, 3, 4));
    });

    test('clearAll leaves the table empty but reports the count rule', () {
      final entries = LinkedTypewriterEntries();
      expect(TypewriterSaveLogic.apply(entries, {1: KeyboardEntry(glfwKeyCode: 1)}, const (0, 0, 0), clearAll: true), isFalse);
      expect(entries.size, 0);
    });

    test('26 keys is the whole-keyboard threshold', () {
      final entries = LinkedTypewriterEntries();
      final changed = {for (var i = 0; i < 26; i++) i: KeyboardEntry(glfwKeyCode: i)};
      expect(TypewriterSaveLogic.apply(entries, changed, const (0, 0, 0), clearAll: false), isTrue);
    });
  });

  group('TypewriterItemKeys', () {
    test('a new key is appended, an existing code is replaced in place', () {
      final keys = TypewriterItemKeys.bindEntry(keys: null, entry: {'GLFWKey': 65, 'v': 1}, glfwKey: 65);
      expect(keys, hasLength(1));

      final two = TypewriterItemKeys.bindEntry(keys: keys, entry: {'GLFWKey': 66, 'v': 2}, glfwKey: 66);
      expect(two.map((e) => e['GLFWKey']), [65, 66]);

      final replaced = TypewriterItemKeys.bindEntry(keys: two, entry: {'GLFWKey': 65, 'v': 3}, glfwKey: 65);
      expect(replaced.map((e) => e['v']), [3, 2]);
    });
  });

  group('honey glue', () {
    test('the size rules reject thin and oversized volumes', () {
      const max = 48;
      expect(HoneyGlueMaxSizing.checkBounds(const Aabb(0, 0, 0, 2, 2, 2), maxRange: max).$1, isTrue);
      expect(HoneyGlueMaxSizing.checkBounds(const Aabb(0, 0, 0, 0.5, 2, 2), maxRange: max).$1, isFalse);
      expect(HoneyGlueMaxSizing.checkBounds(const Aabb(0, 0, 0, 49, 2, 2), maxRange: max).$1, isFalse);
    });

    test('the three payloads map to spawn / resize / discard / ignore', () {
      const valid = Aabb(0, 0, 0, 2, 2, 2);
      const huge = Aabb(0, 0, 0, 49, 2, 2);
      expect(HoneyGluePacketLogic.onSpawn(valid, maxRange: 48), HoneyGlueAction.spawn);
      expect(HoneyGluePacketLogic.onSpawn(huge, maxRange: 48), HoneyGlueAction.discard);
      expect(HoneyGluePacketLogic.onChangeBounds(valid, maxRange: 48), HoneyGlueAction.resize);
      expect(HoneyGluePacketLogic.onChangeBounds(huge, maxRange: 48), HoneyGlueAction.discard);
      expect(HoneyGluePacketLogic.onSync(senderUuid: 'a', selfUuid: 'a'), HoneyGlueAction.ignore);
      expect(HoneyGluePacketLogic.onSync(senderUuid: 'a', selfUuid: 'b'), HoneyGlueAction.resize);
      expect(HoneyGluePacketLogic.onSync(senderUuid: null, selfUuid: 'b'), HoneyGlueAction.resize);
    });

    test('a spawned volume is the box around both clicked corners', () {
      final bounds = const HoneyGlueSpawnPacket((9, 60, 9), (4, 66, 4)).bounds;
      expect(bounds.minX, 4.0);
      expect(bounds.maxX, 10.0);
      expect(bounds.ySize, 7.0);
    });
  });

  group('placement', () {
    test('a spring is placed only inside ten blocks and starts one longer', () {
      expect(SpringPlacement.canPlace(holdingSpring: true, distanceSquared: 100), isTrue);
      expect(SpringPlacement.canPlace(holdingSpring: true, distanceSquared: 100.0001), isFalse);
      expect(SpringPlacement.canPlace(holdingSpring: false, distanceSquared: 1), isFalse);

      expect(SpringPlacement.desiredLength(0), 1.0);
      expect(SpringPlacement.desiredLength(9), 4.0);
      // Clamped at MAX_LENGTH when the gap is nearly ten blocks.
      expect(SpringPlacement.desiredLength(80), SpringPlacement.maxLength);
      expect(SpringPlacement.isValidLength(SpringPlacement.desiredLength(80)), isTrue);
    });

    test('a spring end is the clicked block offset by the face', () {
      expect(SpringPlacement.relativeEnd((1, 2, 3), Direction.up), (1, 3, 3));
      expect(SpringPlacement.relativeEnd((1, 2, 3), Direction.north), (1, 2, 2));
    });

    test('merging glue needs both sides in a sub-level and a close click', () {
      bool can({double distance = 1, bool a = true, bool b = true, bool glue = true}) => MergingGluePlacement.canPlace(
        holdingGlue: glue,
        distanceSquared: distance,
        range: 4,
        parentInSubLevel: a,
        childInSubLevel: b,
      );

      expect(can(), isTrue);
      expect(can(distance: 16), isTrue);
      expect(can(distance: 16.0001), isFalse);
      expect(can(a: false), isFalse);
      expect(can(b: false), isFalse);
      expect(can(glue: false), isFalse);
    });
  });

  group('ServerRopeStrand', () {
    test('a new strand needs a sync, and a still one does not', () {
      final strand = ServerRopeStrand('u', [Vector3d(0, 0, 0), Vector3d(1, 0, 0)]);
      expect(strand.needsSync(), isTrue);
      strand.justSynced();
      expect(strand.needsSync(), isFalse);

      // A move smaller than 6.25 mm is not worth a packet.
      strand.points.first.x = 0.005;
      expect(strand.needsSync(), isFalse);

      strand.points.first.x = 0.5;
      expect(strand.needsSync(), isTrue);
    });

    test('a point added at the front needs a sync', () {
      final strand = ServerRopeStrand('u', [Vector3d(0, 0, 0), Vector3d(1, 0, 0)])..justSynced();
      strand.addPoint(Vector3d(-1, 0, 0));
      expect(strand.points.first.x, -1);
      expect(strand.needsSync(), isTrue);
    });

    test('the extension is the summed segment length', () {
      final strand = ServerRopeStrand('u', [Vector3d(0, 0, 0), Vector3d(3, 0, 0), Vector3d(3, 4, 0)]);
      expect(strand.currentExtension, 7.0);
    });

    test('the first segment extension is lerped between the last two goals', () {
      final strand = ServerRopeStrand('u', [Vector3d(0, 0, 0), Vector3d(1, 0, 0)]);
      strand.updateFirstSegmentExtension(0.0);
      expect(strand.lastExtensionGoal, 1.0);
      expect(strand.extensionGoal, 0.0);
      expect(strand.interpolatedExtension(0), 1.0);
      expect(strand.interpolatedExtension(0.5), 0.5);
      expect(strand.interpolatedExtension(1), 0.0);
    });

    test('prepareFirstSegment reports only real changes', () {
      final strand = ServerRopeStrand('u', [Vector3d(0, 0, 0), Vector3d(1, 0, 0)]);
      expect(strand.prepareFirstSegment(1.0), isFalse);
      strand.updateFirstSegmentExtension(0.25);
      expect(strand.prepareFirstSegment(1.0), isTrue);
      strand.lastFirstSegmentExtension = 0.25;
      expect(strand.prepareFirstSegment(1.0), isFalse);
    });

    test('attachments are kept per end', () {
      final strand = ServerRopeStrand('u', [Vector3d(0, 0, 0), Vector3d(1, 0, 0)]);
      strand.addAttachment(const RopeAttachment(RopeAttachmentPoint.start, (1, 2, 3), 'sub'));
      expect(strand.attachment(RopeAttachmentPoint.start)!.subLevelId, 'sub');
      expect(strand.attachment(RopeAttachmentPoint.end), isNull);
    });
  });

  group('diagram', () {
    test('the frame divides the recorded forces by the time step', () {
      final packet = DiagramForces.build(
        recordedForces: {
          'sable:drag': [PointForce(Vector3d(0, 0, 0), Vector3d(2, 4, 6))],
          'sable:buoyancy': <PointForce>[],
        },
        timeStep: 0.01,
        mass: 10,
        centerOfMass: Vector3d(1, 1, 1),
        localGravity: Vector3d(0, -10, 0),
      );

      expect(packet.forces.containsKey('sable:buoyancy'), isFalse);
      expect(packet.forces['sable:drag']!.single.force.y, 400);
      expect(packet.mass, 10);
    });

    test('gravity is always added, at the centre of mass', () {
      final packet = DiagramForces.build(
        recordedForces: {'sable:gravity': [PointForce(Vector3d(9, 9, 9), Vector3d(1, 1, 1))]},
        timeStep: 0.05,
        mass: 3,
        centerOfMass: Vector3d(1, 1, 1),
        localGravity: Vector3d(0, -30, 0),
      );
      expect(packet.forces[gravityForceGroup], hasLength(1));
      expect(packet.forces[gravityForceGroup]!.single.point.y, 1);
      expect(packet.forces[gravityForceGroup]!.single.force.y, -30);
    });

    test('the recording queue adds a player once and drains the frame', () {
      final queue = DiagramRecordingQueue();
      queue
        ..queue('minecraft:overworld', 'sub', 'a')
        ..queue('minecraft:overworld', 'sub', 'a')
        ..queue('minecraft:overworld', 'sub', 'b');
      expect(queue.pending('minecraft:overworld'), 1);

      final frames = queue.drain('minecraft:overworld');
      expect(frames, hasLength(1));
      expect(frames.single.players, ['a', 'b']);
      expect(queue.pending('minecraft:overworld'), 0);
      expect(queue.drain('minecraft:overworld'), isEmpty);
    });

    test('a ticket with no players is dropped without a frame', () {
      final queue = DiagramRecordingQueue()..queue('d', 'sub', 'a');
      queue.drain('d');
      expect(queue.pending('d'), 0);
    });
  });

  group('diagram config', () {
    test('makeDefault mirrors the entity orientation and displays nothing else', () {
      final config = DiagramConfig.makeDefault(
        defaultDisplayedForceGroups: ['sable:gravity', 'sable:lift'],
        entityYRot: 90,
        entityXRot: 15,
      );
      expect(config.enabledForceGroups, ['sable:gravity', 'sable:lift']);
      expect(config.displayCenterOfMass, isFalse);
      expect(config.mergeForces, isFalse);
      expect(config.yaw, -90);
      expect(config.pitch, 15);
      expect(config.noteConfig.noteYaw, -90);
      expect(config.noteConfig.active, isFalse);
    });
  });

  group('physics staff action', () {
    test('the ordinals are the Java declaration order', () {
      expect(PhysicsStaffAction.stopDrag.index, 0);
      expect(PhysicsStaffAction.lock.index, 1);
      expect(PhysicsStaffAction.startDrag.index, 2);
      expect(PhysicsStaffAction.values.map((a) => a.javaName), ['STOP_DRAG', 'LOCK', 'START_DRAG']);
    });
  });

  group('hold interaction', () {
    test('the target is the block centre, as the packets send it', () {
      final centre = HoldInteractionRange.blockCenter((1, 64, -3));
      expect([centre.x, centre.y, centre.z], [1.5, 64.5, -2.5]);
    });

    test('the reach is the attribute plus the buffer, and exactly at it is outside', () {
      final eye = Vector3d(0, 0, 0);
      bool within(double range, double buffer) => HoldInteractionRange.within(
        eye: eye,
        target: Vector3d(0, 0, 4.5),
        range: range,
        reachBuffer: buffer,
      );

      expect(within(4.5, 0), isFalse);
      expect(within(4.6, 0), isTrue);
      expect(within(3.5, 1), isFalse);
      expect(within(3.6, 1), isTrue);
    });

    test('a world without a sable level measures the raw points', () {
      expect(
        HoldInteractionRange.within(
          eye: Vector3d(10, 20, 30),
          target: Vector3d(10, 20, 35),
          range: 5.1,
        ),
        isTrue,
      );
      expect(
        HoldInteractionRange.within(
          eye: Vector3d(10, 20, 30),
          target: Vector3d(10, 20, 35),
          range: 4.9,
        ),
        isFalse,
      );
    });
  });

  group('end sea', () {
    test('the record round-trips through its NBT form', () {
      const physics = EndSeaPhysics(dimension: 'minecraft:the_end', priority: 2, startY: -40, depthGradient: 1.5, drag: 0.5);
      final back = EndSeaPhysics.fromNbt(physics.toNbt());
      expect(back, physics);
    });

    test('the optional fields are dropped at their default', () {
      const physics = EndSeaPhysics(dimension: 'minecraft:the_end', startY: -40);
      final map = physics.toNbt().asCompound;
      expect(map.keys.toSet(), {'dimension', 'start_y'});
      expect(EndSeaPhysics.fromNbt(physics.toNbt()), physics);
    });
  });
}

/// `InputConstants`' backspace: 259 (`LinkedTypewriterLogic.backspaceKey`).
int backspace() => LinkedTypewriterLogic.backspaceKey;