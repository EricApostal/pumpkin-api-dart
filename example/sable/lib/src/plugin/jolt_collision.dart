// The solver's half of `PhysicsPipeline.handleChunkSectionAddition`: the section
// packer and the collider bakery.
//
// The Jolt pipeline takes the *packed* section, so somebody has to turn the
// level's block states into those words and register a collider per block state.
// Java packs inside `RapierPhysicsPipeline.handleChunkSectionAddition`, which
// owns the `LevelChunkSection`; the Dart seam has the packer injected
// (`PhysicsChunkTicketManager.packer`), so the component that links the solver
// installs it here. Without this every section stays unuploaded: the sub-level
// body keeps Jolt's empty shape and the static level has no geometry, so an
// assembled structure falls through the world.
//
// The bakery reads the collision shape and the liquid flag off the host's block
// registry (`HostBlockShapeSource`, `host_block_shapes.dart`), and the per-block
// physics properties off Sable's embedded datapack table (`SablePlugin
// .blockProperties`, installed by `_installBlockProperties` before the first
// level opens).
import '../physics/jolt/pipeline.dart' show JoltPhysicsPipeline;
import '../sublevel/api/sub_level_assembly_helper.dart' show AssemblyBlockHost;
import '../sublevel/physics/physics_block_properties.dart' show PhysicsBlockPropertiesTable;
import '../sublevel/system/physics_system.dart' show SubLevelPhysicsSystem;
import '../physics/section_packer.dart' show JoltCollisionPacker;
import 'host_block_shapes.dart' show HostBlockShapeSource;

/// Installs the section packer and the collider bakery on [system]'s physics
/// system.
void installJoltCollision(
  SubLevelPhysicsSystem system, {
  required PhysicsBlockPropertiesTable? properties,
}) {
  final pipeline = system.pipeline;
  if (pipeline is! JoltPhysicsPipeline) {
    throw StateError(
      'Sable installed a ${pipeline.runtimeType}; the collision packer needs '
      'the Jolt pipeline it registers colliders with.',
    );
  }
  final host = system.container.chunkHost;
  final AssemblyBlockHost blocks;
  if (host is AssemblyBlockHost) {
    // The field is public, so it does not promote; the cast is the check.
    blocks = host as AssemblyBlockHost;
  } else {
    throw StateError(
      'The chunk host of ${system.container.level.dimensionId} '
      '(${host.runtimeType}) does not read whole block states; the section '
      'packer needs one that does (the Pumpkin host implements '
      'AssemblyBlockHost).',
    );
  }
  system.ticketManager.packer = JoltCollisionPacker(
    pipeline: pipeline,
    shapes: HostBlockShapeSource(),
    blocks: blocks,
    properties: properties,
  );
}