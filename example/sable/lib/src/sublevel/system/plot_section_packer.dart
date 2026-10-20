// Packing a plot chunk section for the physics pipeline.
//
// `RapierPhysicsPipeline.handleChunkSectionAddition` takes a `LevelChunkSection`
// and packs it itself; the Dart pipeline (`PhysicsPipeline.handleChunkSectionAddition`,
// `api/physics_pipeline.dart`) takes the packed array instead, so that the
// pure package never touches a host chunk type. The packing needs the voxel
// collider of every block state (the collision-shape registry), which is the
// physics workstream's data, so the packer is injected.
//
// Layout (see `api/physics_pipeline.dart`): 4096 ints, indexed
// `bx + (bz << 4) + (by << 8)`, each `(colliderId + 1) << 16 | voxelStateIndex`.
// A zero entry is air.
//
// Pure: no host imports.
import '../host/sub_level_host.dart';

/// Turns one section of a plot chunk into the pipeline's packed array.
abstract interface class PlotSectionPacker {
  /// Packs section [sectionIndex] of [chunk].
  ///
  /// `sectionIndex` is the chunk's section index (`0..sectionsCount-1`); the
  /// section's lowest block y is `chunk.sectionMinY(sectionIndex)`.
  List<int> packSection(PlotChunk chunk, int sectionIndex);
}
