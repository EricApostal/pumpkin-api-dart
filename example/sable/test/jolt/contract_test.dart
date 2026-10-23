// The pipeline's own contract decisions: where a chunk section is uploaded when
// Sable does not say which sub-level owns it, and which features the Jolt
// pipeline declares.
//
// Both run against `RecordingJolt` (`support/recording_jolt.dart`), a fake ABI
// that records `chunkAdd`/`chunkRemove`, so no node and no built module are
// needed.
import 'package:sable/sable.dart';
import 'package:sable/src/physics/jolt.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/recording_jolt.dart';

/// The global chunk coordinates of the first plot of a container with the
/// default layout: plot `(defaultOrigin, defaultOrigin)`, `1 << 7` chunks per
/// plot (so `1280000` is the first chunk of that plot).
const int _plotChunk = SubLevelContainer.defaultOrigin * (1 << 7);

void main() {
  late RecordingJolt abi;
  late JoltPhysicsPipeline pipeline;
  late SableLevel level;
  late TestServerContainer container;

  setUp(() {
    abi = RecordingJolt();
    pipeline = JoltPhysicsPipeline(abi: abi, memory: abi);
    pipeline.init(Vector3d(0.0, -9.81, 0.0), 0.0);
    level = TestLevel();
    container = TestServerContainer(level, TestChunkHost());
    SubLevelContainer.register(container);
    addTearDown(() => SubLevelContainer.unregister(level));
  });

  tearDown(() => pipeline.dispose());

  /// A section whose local origin block has [collider].
  List<int> section(int collider) {
    final data = List<int>.filled(4096, 0);
    data[0] = packBlockState(collider, VoxelPhysicsState.face);
    return data;
  }

  group('chunk section routing', () {
    test('a section in a plot lands on the sub-level body without a runtime id', () {
      final subLevel = container.allocateSubLevel('uuid', 0, 0, Pose3d()) as ServerSubLevel;
      pipeline.addSubLevel(subLevel, subLevel.pose);
      final collider = pipeline.registerVoxelCollider(const BlockColliderData());

      // Exactly what `SubLevelPhysicsSystem.handleChunkSectionAddition` does
      // (`physics_system.dart:419`): `global: false`, no `subLevelRuntimeId`.
      // The owner has to come from the plot grid, as
      // `RapierPhysicsPipeline.handleChunkSectionAddition` decides it
      // (`RapierPhysicsPipeline.java:358-365`).
      pipeline.handleChunkSectionAddition(
        _plotChunk,
        0,
        _plotChunk,
        section(collider),
        global: false,
      );

      expect(abi.chunks, hasLength(1));
      expect(abi.chunks.single.global, isFalse);
      expect(abi.chunks.single.body, isNot(0), reason: 'the section must reach a body');
      expect(
        pipeline.blocksOf(subLevel)!.hasSection(_plotChunk, 0, _plotChunk),
        isTrue,
        reason: 'the sub-level body records the section',
      );
      expect(
        pipeline.levelBlocks.hasSection(_plotChunk, 0, _plotChunk),
        isFalse,
        reason: 'the static level must not claim a plot section',
      );
    });

    test('a section outside every plot goes to the static level', () {
      final subLevel = container.allocateSubLevel('uuid', 0, 0, Pose3d()) as ServerSubLevel;
      pipeline.addSubLevel(subLevel, subLevel.pose);
      final collider = pipeline.registerVoxelCollider(const BlockColliderData());

      pipeline.handleChunkSectionAddition(0, -1, 0, section(collider), global: false);

      expect(abi.chunks.single.global, isTrue);
      expect(abi.chunks.single.body, 0);
      expect(pipeline.levelBlocks.hasSection(0, -1, 0), isTrue);
      expect(pipeline.blocksOf(subLevel)!.hasSection(0, -1, 0), isFalse);
    });

    test('an explicit runtime id still wins over the plot lookup', () {
      // The existing tests upload a sub-level section at a non-plot chunk with
      // `subLevelRuntimeId` set (Java's `uploadDataIfGlobal` path,
      // `RapierPhysicsPipeline.java:362-363`).
      final subLevel = ServerSubLevel(
        level,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
        Pose3d(),
        runtimeId: 7,
      );
      pipeline.addSubLevel(subLevel, subLevel.pose);
      final collider = pipeline.registerVoxelCollider(const BlockColliderData());

      pipeline.handleChunkSectionAddition(
        0,
        0,
        0,
        section(collider),
        global: false,
        subLevelRuntimeId: 7,
      );

      expect(abi.chunks.single.global, isFalse);
      expect(abi.chunks.single.body, isNot(0));
      expect(pipeline.blocksOf(subLevel)!.hasSection(0, 0, 0), isTrue);
      expect(pipeline.levelBlocks.hasSection(0, 0, 0), isFalse);
    });

    test('a plot section whose sub-level has no body is not uploaded anywhere', () {
      // Both plots exist in the grid; only the first sub-level is registered
      // with the pipeline. A section of the second one belongs to a plot, but
      // Java sends the same call with body id -1
      // (`RapierPhysicsPipeline.java:363`), which the module turns into a no-op
      // (`jolt_abi.cpp:1372-1376`).
      final registered = container.allocateSubLevel('registered', 0, 0, Pose3d());
      final other = container.allocateSubLevel('other', 1, 0, Pose3d());
      pipeline.addSubLevel(registered as ServerSubLevel, registered.pose);
      final collider = pipeline.registerVoxelCollider(const BlockColliderData());

      // Plot local (1, 0) starts one plot (`1 << 7` chunks) to the right.
      const otherChunk = _plotChunk + (1 << 7);

      expect(
        () => pipeline.handleChunkSectionAddition(
          otherChunk,
          0,
          _plotChunk,
          section(collider),
          global: false,
        ),
        returnsNormally,
      );

      expect(abi.chunks.single.global, isFalse);
      expect(abi.chunks.single.body, 0);
      expect(pipeline.levelBlocks.hasSection(otherChunk, 0, _plotChunk), isFalse);
      expect(
        pipeline.blocksOf(other as ServerSubLevel),
        isNull,
        reason: 'the second sub-level was never registered',
      );
    });

    test('removal takes a plot section from the body and a static one from the level', () {
      final subLevel = container.allocateSubLevel('uuid', 0, 0, Pose3d()) as ServerSubLevel;
      pipeline.addSubLevel(subLevel, subLevel.pose);
      final collider = pipeline.registerVoxelCollider(const BlockColliderData());

      pipeline.handleChunkSectionAddition(
        _plotChunk,
        0,
        _plotChunk,
        section(collider),
        global: false,
      );
      pipeline.handleChunkSectionAddition(0, -1, 0, section(collider), global: false);
      abi.chunks.clear();

      // `SubLevelPhysicsSystem.handleChunkSectionRemoval` passes no `global`
      // (`physics_system.dart:425`).
      expect(
        () => pipeline.handleChunkSectionRemoval(_plotChunk, 0, _plotChunk),
        returnsNormally,
      );
      expect(
        () => pipeline.handleChunkSectionRemoval(0, -1, 0),
        returnsNormally,
      );

      expect(abi.chunks, hasLength(2));
      expect(abi.chunks.first.global, isFalse);
      expect(abi.chunks.first.body, isNot(0));
      expect(pipeline.blocksOf(subLevel)!.hasSection(_plotChunk, 0, _plotChunk), isFalse);
      // `RapierPhysicsPipeline.handleChunkSectionRemoval` treats everything
      // outside the plot grid as static level geometry
      // (`RapierPhysicsPipeline.java:371-373`).
      expect(abi.chunks.last.global, isTrue);
      expect(abi.chunks.last.body, 0);
      expect(pipeline.levelBlocks.hasSection(0, -1, 0), isFalse);
    });
  });

  group('declared capabilities', () {
    test('the Jolt pipeline declares contraptions and ropes unsupported', () {
      expect(pipeline.supportsFeature(PhysicsPipelineFeature.contraption), isFalse);
      expect(pipeline.supportsFeature(PhysicsPipelineFeature.rope), isFalse);
    });

    test('the throwing methods are typed and name the missing native capability', () {
      final contraption = _FakeContraption();
      final rope = RopePhysicsObject([Vector3d(0, 0, 0)], 0.25);
      final ropeHandle = _FakeRope();
      for (final call in <void Function()>[
        () => pipeline.addContraption(contraption),
        () => pipeline.removeContraption(contraption),
      ]) {
        expect(
          call,
          throwsA(
            isA<UnsupportedPhysicsFeatureException>()
                .having((e) => e.feature, 'feature', PhysicsPipelineFeature.contraption)
                .having((e) => e.missingCapability, 'missingCapability', isNotEmpty),
          ),
        );
      }
      for (final call in <void Function()>[
        () => pipeline.addRope(rope),
        () => pipeline.removeRope(ropeHandle),
      ]) {
        expect(
          call,
          throwsA(
            isA<UnsupportedPhysicsFeatureException>()
                .having((e) => e.feature, 'feature', PhysicsPipelineFeature.rope)
                .having((e) => e.missingCapability, 'missingCapability', isNotEmpty),
          ),
        );
      }
    });

    test('the guard keeps an unsupported feature from being called', () {
      // The shape of the guard in the two Sable call sites: the call is only
      // made when the pipeline declares the feature
      // (`contraption_physics.dart:579-585`,
      // `sable_spawn_commands.dart:451-457`).
      final gated = _GatedPipeline(const {});
      final contraption = _FakeContraption();

      if (gated.supportsFeature(PhysicsPipelineFeature.contraption)) {
        gated.addContraption(contraption);
      }
      if (gated.supportsFeature(PhysicsPipelineFeature.rope)) {
        gated.addRope(RopePhysicsObject([Vector3d(0, 0, 0)], 0.25));
      }

      expect(gated.calls, isEmpty);
      // …and a pipeline that does not implement the interface at all keeps the
      // Java behaviour: every feature is available.
      expect(pipeline.supportsFeature(PhysicsPipelineFeature.contraption), isFalse);
      expect(_UndeclaredPipeline().supportsFeature(PhysicsPipelineFeature.rope), isTrue);
    });

    test('the static fallback declares the features it accepts', () {
      final static = StaticPhysicsPipeline();
      expect(static.supportsFeature(PhysicsPipelineFeature.contraption), isTrue);
      expect(static.supportsFeature(PhysicsPipelineFeature.rope), isTrue);
      // It accepts them exactly as Java does: by ignoring them.
      expect(
        () => static.addRope(RopePhysicsObject([Vector3d(0, 0, 0)], 0.25)),
        returnsNormally,
      );
    });
  });
}

/// A `KinematicContraption` stand-in: the pipeline only ever passes it on.
final class _FakeContraption implements KinematicContraption {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A `RopeHandle` stand-in: `removeRope` only ever throws with it.
final class _FakeRope implements RopeHandle {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A pipeline that declares [supported].
final class _GatedPipeline implements PhysicsPipeline, FeatureAwarePhysicsPipeline {
  final Set<PhysicsPipelineFeature> supported;

  _GatedPipeline(this.supported);

  final List<String> calls = [];

  @override
  bool supportsFeature(PhysicsPipelineFeature feature) => supported.contains(feature);

  @override
  void addContraption(KinematicContraption contraption) => calls.add('addContraption');

  @override
  RopeHandle addRope(RopePhysicsObject rope) {
    calls.add('addRope');
    throw UnimplementedError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('_GatedPipeline.${invocation.memberName}');
}

/// A pipeline that does not implement [FeatureAwarePhysicsPipeline] at all.
final class _UndeclaredPipeline implements PhysicsPipeline {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('_UndeclaredPipeline.${invocation.memberName}');
}