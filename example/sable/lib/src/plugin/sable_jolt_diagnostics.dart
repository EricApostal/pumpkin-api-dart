// The `/sablejolt` diagnostics tree: the live checks on the linked Jolt module
// and on the sub-levels this component owns.
//
// These commands exist because the module and the containers are both here: the
// engine's ABI/version and its collider registry, a body dropped onto a voxel
// floor, and the pose/velocity/mass/floating clusters of every sub-level — the
// values a headless rig reads out of the log. The `/sable` tree is the model's
// own command set; this one is the solver's.
//
// Host: this file uses `pumpkin_api`, so it is only linked by the plugin entry
// point (`bin/main.dart`), never by the model barrel.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../sable.dart' show BoxPhysicsObject, FloatingClusterContainer, Pose3d, ServerSubLevel, ServerSubLevelContainer, SubLevelContainer, SubLevelPhysicsSystem, Vector3d;
import '../physics/jolt.dart' show BlockColliderData, VoxelPhysicsState, packBlockState;
import '../physics/jolt/pipeline.dart' show JoltPhysicsPipeline;

/// Registers `/sablejolt` over [pipeline] and the containers [containerOf]
/// resolves (this plugin's own, in this component).
void registerJoltDiagnostics(
  Context context,
  Logger logger, {
  required JoltPhysicsPipeline pipeline,
  required SubLevelContainer? Function(String world) containerOf,
}) {
  /// Whether a `/sablejolt watch` sampler is running.
  var watching = false;

  context.command(
    'sablejolt',
    description: 'Jolt physics diagnostics',
    (c) => c
      ..runs((ctx) {
        ctx.replyLines([
          'Jolt ABI ${pipeline.moduleAbiVersion}, version id ${pipeline.moduleVersion}',
          'voxel colliders: ${pipeline.colliders.length}',
        ]);
      })
      ..sub(
        'drop',
        description: 'Drop a box onto a voxel floor',
        runs: (ctx) {
          final y = _dropTest(pipeline);
          ctx.replyLines(['box settled at y = ${y.toStringAsFixed(4)}']);
        },
      )
      ..sub(
        'floaty',
        description: 'Report the floating clusters and velocity of every sub-level here',
        runs: (ctx) => _floaty(ctx, containerOf),
      )
      ..sub(
        'watch',
        description: 'Log every sub-level here once a second for 20 seconds',
        runs: (ctx) {
          if (watching) {
            ctx.replyError('Already watching.');
            return;
          }
          watching = true;
          var ticks = 0;
          var samples = 0;
          EventSubscription? subscription;
          subscription = context.listen(Events.worldTick, (server, event) {
            if (++ticks % 20 != 0) return;
            samples++;
            final container = containerOf('minecraft:overworld');
            if (container is! ServerSubLevelContainer) {
              subscription?.cancel();
              watching = false;
              return;
            }
            for (final line in _bodyLines(container)) {
              logger.info('[watch $samples] $line');
            }
            if (samples >= 20) {
              subscription?.cancel();
              watching = false;
              logger.info('[watch] done after $samples samples');
            }
          });
          ctx.reply('watching for 20 seconds');
        },
      ),
  );
}

/// Reports every sub-level this component holds: its position, velocity, mass
/// and floating clusters.
///
/// A floating cluster is what makes a levitite body lift: its material's
/// `lift_strength` is applied in `FloatingBlockController.applyLift`. A body
/// with no cluster falls like stone however many levitite blocks it carries,
/// which is what this line distinguishes.
void _floaty(
  CommandContext ctx,
  SubLevelContainer? Function(String) containerOf,
) {
  final container = containerOf('minecraft:overworld');
  if (container is! ServerSubLevelContainer) {
    ctx.replyError('No server container for minecraft:overworld.');
    return;
  }
  final system = SubLevelPhysicsSystem.of(container);
  final subLevels = container.getAllSubLevels().whereType<ServerSubLevel>().toList();
  ctx.replyLines([
    'container ${identityHashCode(container)}: ${subLevels.length} sub-level(s), '
        'allSubLevels=${container.allSubLevels.length}, '
        'byUuid=${container.subLevelsByUUID.length}, '
        'physics=${system != null}',
  ]);
  if (subLevels.isEmpty) {
    ctx.reply('no sub-levels');
    return;
  }
  for (final line in _bodyLines(container)) {
    ctx.reply(line);
  }
}

/// One block of lines per sub-level of [container]: the body's pose, velocity,
/// mass and floating clusters.
List<String> _bodyLines(ServerSubLevelContainer container) {
  final system = SubLevelPhysicsSystem.of(container);
  final subLevels = container.getAllSubLevels().whereType<ServerSubLevel>().toList();
  final out = <String>[];
  for (final subLevel in subLevels) {
    final handle = system?.getPhysicsHandle(subLevel);
    final pose = Pose3d();
    final velocity = Vector3d();
    final pipeline = system?.pipeline;
    if (handle != null && pipeline is JoltPhysicsPipeline) {
      pipeline.readPose(subLevel, pose);
      pipeline.getLinearVelocity(handle, velocity);
    } else {
      pose.set(subLevel.logicalPose);
      if (handle != null) handle.getLinearVelocity(velocity);
    }
    final position = pose.position();
    final logical = subLevel.logicalPose.position();
    final controller = subLevel.floatingBlockController;
    // `containers` is the controller's own list and it starts with
    // `sublevelContainer` (`physicsTick`), so the body's clusters are read
    // there and only the contraption containers are added on top.
    final holders = controller == null
        ? const <FloatingClusterContainer>[]
        : controller.containers.isEmpty
        ? [controller.sublevelContainer]
        : controller.containers;
    final clusters = [
      for (final holder in holders)
        for (final cluster in holder.clusters)
          '${cluster.material.liftStrength} x${cluster.blockData.blockCount}',
    ];
    out.addAll([
      '${subLevel.uniqueIdOrNull} at ${DateTime.now().toIso8601String()}: '
          'body ${position.x.toStringAsFixed(2)}, '
          '${position.y.toStringAsFixed(2)}, ${position.z.toStringAsFixed(2)}',
      '  logical ${logical.x.toStringAsFixed(2)}, '
          '${logical.y.toStringAsFixed(2)}, ${logical.z.toStringAsFixed(2)}',
      '  linear velocity ${velocity.x.toStringAsFixed(2)}, '
          '${velocity.y.toStringAsFixed(2)}, ${velocity.z.toStringAsFixed(2)}',
      '  mass ${subLevel.massTracker?.getMass() ?? 0}',
      '  floating clusters: ${clusters.isEmpty ? 'none' : clusters.join(', ')}',
    ]);
  }
  return out;
}

/// Drops a 1x1x1 box onto a voxel floor and returns where it came to rest.
/// The same sequence the acceptance test runs, but inside a live server, so the
/// log line proves the module is linked and stepping.
double _dropTest(JoltPhysicsPipeline pipeline) {
  final collider = pipeline.registerVoxelCollider(const BlockColliderData());
  final section = List<int>.filled(4096, 0);
  for (var bx = 0; bx < 16; bx++) {
    for (var bz = 0; bz < 16; bz++) {
      section[bx + (bz << 4) + (15 << 8)] = packBlockState(collider, VoxelPhysicsState.face);
    }
  }
  pipeline.handleChunkSectionAddition(0, -1, 0, section, global: true);

  final pose = Pose3d()..position().set(0.0, 5.0, 0.0);
  final box = pipeline.addBox(BoxPhysicsObject(pose, Vector3d(0.5, 0.5, 0.5), 1.0));
  for (var i = 0; i < 120; i++) {
    pipeline.physicsTick(1.0 / 60.0);
  }
  final rest = Pose3d();
  box.readPose(rest);
  final y = rest.position().y;
  box.remove();
  return y;
}