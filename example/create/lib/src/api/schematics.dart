/// The schematic API for other modules (provided by the `schematics` module):
/// `ctx.services.require<SchematicHooks>()` to register state filters, item requirements, safe
/// block entity data, brittle blocks and belt placement; `SchematicRequirements` and the pure
/// block state transform (`transformState`, `rotateState`, `mirrorState`).
library;

export '../schematics/item_requirement.dart';
export '../schematics/schematic_hooks.dart';
export '../schematics/state_transform.dart';
export '../schematics/upload_receiver.dart' show SchematicUploadReceiver;
