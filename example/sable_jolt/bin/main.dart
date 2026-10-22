// ignore_for_file: import_internal_library
//
// The plugin entry point: links the Jolt core module, builds the physics
// pipeline on load, and exposes two checks that a live server can run.
//
// The module never calls back into Dart, but the component linker always
// instantiates the table-init module, which imports `dart.host_call`, so this
// program must export it (`/tmp/joltspike/ADR.md` §1, `transform.dart:245-254`).
import 'dart:_wasm';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart';
import 'package:sable/sable_plugin.dart' show SablePlugin;
import 'package:sable_jolt/sable_jolt_native.dart';

/// The trampoline the core module's `host.call` import is routed to.
@pragma('wasm:export', 'host_call')
WasmI32 hostCall(WasmI32 id, WasmI32 a, WasmI32 b, WasmI32 c) => WasmI32.fromInt(0);

void main() => runPlugin(SableJoltPlugin());

final class SableJoltPlugin extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: 'sable_jolt',
    version: '0.1.0',
    description: 'Jolt Physics as the Sable backend: a freestanding wasm core '
        'module behind a C ABI, driven by JoltPhysicsPipeline.',
    // The Sable server half runs in this component (it owns the sub-level
    // containers, see [_server]): it writes the data pack and the sub-level
    // storage, and declares nothing — the `sable` plugin keeps the NeoForge
    // declaration, so the mod is announced exactly once.
    permissions: [Permissions.fsWriteData],
  );

  late final JoltPhysicsPipeline pipeline = createJoltPipeline();

  /// The Sable server, running in this component.
  ///
  /// **This plugin owns the sub-level containers.** A `PhysicsPipeline` is a Dart
  /// object and cannot cross a wasm component boundary, and `sable_jolt` depends
  /// on `sable` (its pipeline implements `sable`'s contract), so `sable` cannot
  /// depend on `sable_jolt` to get one: the two would form a package cycle. The
  /// containers therefore live here, next to the solver, and the `sable` plugin
  /// stands down once this one answers the ownership probe. Everything a caller
  /// needs is reached over the operation channel
  /// (`package:sable/src/plugin/sable_sub_level_api.dart`), which this component
  /// installs by running the server half below — so there is one owner and one
  /// door. See "Cross-plugin ownership" in `example/sable/docs/sable-core-port.md`.
  late final SablePlugin _server = SablePlugin(pipelineOf: _pipelineFor);

  /// One pipeline per level, the way `PhysicsPipelineProvider.createPipeline`
  /// builds them for the fallback.
  JoltPhysicsPipeline _pipelineFor(SableLevel level) => createJoltPipeline();

  @override
  Future<void> onLoad(Context context) async {
    // Answer the ownership probe before the worlds are opened: the `sable`
    // plugin asks on the first tick and stands down when this says yes.
    SablePlugin.ownershipChannel.handle((sender, message) {
      if (message['op'] != 'owns') return null;
      return {'owns': true, 'plugin': info.name};
    });

    pipeline.init(Vector3d(0.0, -9.81, 0.0), 0.0);
    logger.info(
      'Jolt module: ABI ${pipeline.moduleAbiVersion}, version id '
      '${pipeline.moduleVersion}.',
    );

    await _server.startServer(context);

    context.command(
      'sablejolt',
      description: 'Jolt physics diagnostics',
      (c) => c
        ..runs((ctx) {
          ctx.replyLines([
            'Jolt ABI ${pipeline.moduleAbiVersion}, version id '
                '${pipeline.moduleVersion}',
            'voxel colliders: ${pipeline.colliders.length}',
          ]);
        })
        ..sub('drop', description: 'Drop a box onto a voxel floor', runs: (ctx) {
          final y = _dropTest();
          ctx.replyLines(['box settled at y = ${y.toStringAsFixed(4)}']);
        }),
    );
  }

  @override
  void onUnload(Context context) {
    _server.stopServer();
    pipeline.dispose();
  }

  /// Drops a 1x1x1 box onto a voxel floor and returns where it came to rest.
  ///
  /// The same sequence the acceptance test runs, but inside a live server, so
  /// the log line proves the module is linked and stepping.
  double _dropTest() {
    final collider = pipeline.registerVoxelCollider(const BlockColliderData());
    final section = List<int>.filled(4096, 0);
    for (var bx = 0; bx < 16; bx++) {
      for (var bz = 0; bz < 16; bz++) {
        section[bx + (bz << 4) + (15 << 8)] =
            packBlockState(collider, VoxelPhysicsState.face);
      }
    }
    pipeline.handleChunkSectionAddition(0, -1, 0, section, global: true);

    final pose = Pose3d()..position().set(0.0, 5.0, 0.0);
    final box = pipeline.addBox(
      BoxPhysicsObject(pose, Vector3d(0.5, 0.5, 0.5), 1.0),
    );
    for (var i = 0; i < 120; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final rest = Pose3d();
    box.readPose(rest);
    final y = rest.position().y;
    box.remove();
    return y;
  }
}
