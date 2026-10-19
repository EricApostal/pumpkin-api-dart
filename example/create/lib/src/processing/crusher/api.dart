/// The public API of the crusher part of the processing module (re-exported by
/// `package:create/src/api/processing.dart`).
///
/// The machines of other modules that interact with the crushing wheels (the mechanical arm's
/// interaction points, belts) read the controller's storage through
/// [ItemStorageProvider][CrushingWheelControllerBlockEntity] and need the block keys below.
library;

export 'crushing_keys.dart';
export 'crushing_wheel_controller_block_entity.dart'
    show CrushingWheelControllerBlockEntity;
