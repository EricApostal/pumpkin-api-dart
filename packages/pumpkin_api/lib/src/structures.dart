import 'dart:typed_data';

import 'bindings.g.dart' as generated;
import 'bindings.g.dart';
import 'bulk_placement.dart';
import 'host_result.dart';

/// Vanilla structure templates, the `.nbt` structure format
/// (`structures.wit`): load, save and place them with rotation and mirroring.
///
/// Template positions are relative to the origin (the 0,0,0 corner). Placing
/// mirrors first and then rotates around that corner.
///
/// ```dart
/// final bytes = await world.saveStructure(min, max);
/// final template = StructureTemplates.load(bytes);
/// await world.placeStructure(template, origin, rotation: Rotation.clockwise90);
/// ```
abstract final class StructureTemplates {
  /// Reads a template from `.nbt` bytes, gzip compressed or raw. Throws a
  /// [HostException] if they are not a template.
  static StructureTemplate load(List<int> bytes) => unwrapHost(
    generated.structures.loadStructureNbt(bytes: bytes),
    'Loading the structure template',
  );

  /// Saves the box between [min] and [max] (inclusive, any order) of [world] as
  /// gzip compressed `.nbt` bytes. The template origin is the minimum corner.
  /// Throws a [HostException] for an area of more than 16 million blocks.
  static Future<Uint8List> save(
    World world,
    BlockPos min,
    BlockPos max, {
    bool includeEntities = true,
  }) => unwrapHostAsync(
    generated.structures.saveStructureFromWorld(
      target: world,
      min: min,
      max: max,
      includeEntities: includeEntities,
    ),
    'Saving the structure',
  ).then(Uint8List.fromList);

  /// Places [template] in [world] with its origin at [origin]. Blocks go
  /// through the bulk path of `World.placeBlocks` with [flags], block entities
  /// are created from the template data and its entities are spawned. Structure
  /// voids are never placed, air only when [ignoreAir] is false. An [integrity]
  /// below 1 keeps each block with that chance. Returns the number of blocks
  /// that changed.
  static Future<int> place(
    StructureTemplate template,
    World world,
    BlockPos origin, {
    Rotation rotation = Rotation.none,
    Mirror mirror = Mirror.none,
    Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal,
    bool ignoreAir = true,
    double? integrity,
  }) => unwrapHostAsync(
    generated.structures.placeStructure(
      template: template,
      target: world,
      origin: origin,
      rotation: rotation,
      mirror: mirror,
      updateFlags: flags,
      ignoreAir: ignoreAir,
      integrity: integrity,
    ),
    'Placing the structure',
  );
}

/// Saving and placing structure templates in a [World].
extension WorldStructures on World {
  /// See [StructureTemplates.save].
  Future<Uint8List> saveStructure(BlockPos min, BlockPos max, {bool includeEntities = true}) =>
      StructureTemplates.save(this, min, max, includeEntities: includeEntities);

  /// See [StructureTemplates.place].
  Future<int> placeStructure(
    StructureTemplate template,
    BlockPos origin, {
    Rotation rotation = Rotation.none,
    Mirror mirror = Mirror.none,
    Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal,
    bool ignoreAir = true,
    double? integrity,
  }) => StructureTemplates.place(
    template,
    this,
    origin,
    rotation: rotation,
    mirror: mirror,
    flags: flags,
    ignoreAir: ignoreAir,
    integrity: integrity,
  );
}

/// Reading a [StructureTemplate].
extension StructureTemplateApi on StructureTemplate {
  /// The size in blocks.
  BlockPos get size => getSize();

  /// The author, empty if none was saved.
  String get author => getAuthor();

  /// The distinct block states of the first palette.
  List<PaletteEntry> get palette => getPalette();

  /// The blocks of the first palette.
  List<StructureBlock> get blocks => getBlocks();

  /// The entities.
  List<StructureEntity> get entities => getEntities();

  /// The template in the `.nbt` format, gzip compressed if [compress]. Throws a
  /// [HostException] on failure.
  Uint8List encode({bool compress = true}) => Uint8List.fromList(
    unwrapHost(toBytes(compress: compress), 'Encoding the structure template'),
  );
}
