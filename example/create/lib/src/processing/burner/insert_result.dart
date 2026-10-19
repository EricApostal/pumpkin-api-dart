// `BlazeBurnerBlock.InsertResult` (pure): what `tryInsert` reports to the machines that feed a
// burner (belts, funnels, the mechanical arm and the player's hand).
import '../common/stack.dart';

/// `InteractionResult` as far as a fuel insertion needs it.
enum InsertResultType {
  success,
  fail;

  bool get isSuccess => this == InsertResultType.success;
}

/// `BlazeBurnerBlock.InsertResult`: whether the fuel went in, and the container it leaves behind
/// (a lava bucket's bucket, ...). The whole [object] is empty when there is no container.
final class InsertResult {
  final InsertResultType result;

  /// The stack the caller gets back (`ItemStack.EMPTY` for none).
  final PStack object;

  const InsertResult(this.result, this.object);

  static const InsertResult success = InsertResult(
    InsertResultType.success,
    PStack.empty,
  );
  static const InsertResult fail = InsertResult(
    InsertResultType.fail,
    PStack.empty,
  );

  bool get succeeded => result.isSuccess;

  @override
  String toString() => 'InsertResult(${result.name}, $object)';
}
