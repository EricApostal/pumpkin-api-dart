// `IControlContraption` (pure): a block entity that controls a contraption (bearings, pistons,
// pulleys). The controlled entity finds its controller through this interface.
import '../../common/pos.dart';
import 'contraption_entity.dart';
import 'controlled_contraption_entity.dart';

/// `IControlContraption`.
abstract interface class IControlContraption {
  /// `isAttachedTo(contraption)`.
  bool isAttachedTo(AbstractContraptionEntity contraption);

  /// `attach(contraption)`.
  void attach(ControlledContraptionEntity contraption);

  /// `onStall()`.
  void onStall();

  /// `isValid()`.
  bool isValid();

  /// `getBlockPosition()`.
  Pos getBlockPosition();
}

/// `IControlContraption.MovementMode`.
enum MovementMode {
  movePlace,
  movePlaceReturned,
  moveNeverPlace;

  /// The translation key of the mode (`create.contraptions.movement_mode.move_place`).
  String get translationKey =>
      'create.contraptions.movement_mode.$serializedName';

  String get serializedName => switch (this) {
    MovementMode.movePlace => 'move_place',
    MovementMode.movePlaceReturned => 'move_place_returned',
    MovementMode.moveNeverPlace => 'move_never_place',
  };
}

/// `IControlContraption.RotationMode`.
enum RotationMode {
  rotatePlace,
  rotatePlaceReturned,
  rotateNeverPlace;

  /// The translation key of the mode (`create.contraptions.movement_mode.rotate_place`).
  String get translationKey =>
      'create.contraptions.movement_mode.$serializedName';

  String get serializedName => switch (this) {
    RotationMode.rotatePlace => 'rotate_place',
    RotationMode.rotatePlaceReturned => 'rotate_place_returned',
    RotationMode.rotateNeverPlace => 'rotate_never_place',
  };
}
