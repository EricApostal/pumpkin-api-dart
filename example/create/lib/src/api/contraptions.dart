/// The contraptions module's API for the other modules (published by `ContraptionsModule`):
/// the `Contraption` structure, its actors and mounted storage, the contraption entity kinds and
/// the host factories the actuators and the trains use.
///
/// ```dart
/// final contraption = Contraption()..anchor = pos;
/// await contraption.assemble(ActuatorHosts.levelOf(worldId)!, pos);
///
/// final factory = ActuatorHosts.entities;
/// final entity = factory?.createControlled(worldId, controllerPos, contraption);
/// ```
library;

export 'contraption/block_movement_checks.dart';
export 'contraption/dispenser/mounted_dispense_behaviours.dart';
export 'contraption/movement_setting.dart';
export 'contraption/storage/item_handler_container.dart';
export 'contraption/storage/mounted_storage_menus.dart';
export 'contraption/storage/mounted_storage_wrappers.dart';
export 'contraption/transformable.dart';
export '../contraptions/blocks/actuator_contract.dart'
    show ContraptionEntityFactory, ContraptionLevelFactory, ActuatorHosts;
export '../contraptions/core/collision.dart';
export '../contraptions/core/contraption.dart';
export '../contraptions/core/contraption_type.dart';
export '../contraptions/core/level.dart';
export '../contraptions/core/movement.dart';
export '../contraptions/core/movement_checks.dart';
export '../contraptions/core/nbt_map.dart';
export '../contraptions/core/structure_info.dart';
export '../contraptions/core/structure_transform.dart';
export '../contraptions/entity/contraption_collider.dart';
export '../contraptions/entity/contraption_entity.dart';
export '../contraptions/entity/contraption_handler.dart';
export '../contraptions/entity/contraption_packets.dart';
export '../contraptions/entity/contraption_world.dart';
export '../contraptions/entity/controlled_contraption_entity.dart';
export '../contraptions/entity/host_contraption_entities.dart';
export '../contraptions/entity/i_control_contraption.dart';
export '../contraptions/entity/oriented_contraption_entity.dart';
export '../contraptions/entity/translating_contraption.dart';
export '../contraptions/storage/mounted_storage.dart';
export '../contraptions/storage/stacks.dart';
export '../contraptions/storage/storage_manager.dart';
