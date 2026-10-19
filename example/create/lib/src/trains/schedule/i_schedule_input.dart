// `IScheduleInput` (pure): the common face of schedule instructions and wait conditions. The
// parts of the Java interface that only feed the schedule screen (`getSummary`, `getTitleAs`,
// `getSecondLineIcon`, `getSecondLineTooltip`, `initConfigurationWidgets`, `renderSpecialIcon`)
// are client side and are not ported. Items are carried as their NBT form (`ItemStack.CODEC`).
import '../util/ctag.dart';

abstract interface class IScheduleInput {
  /// The identifier of the type (`create:destination`).
  String getId();

  /// The raw configuration tag (`Data`).
  CTag getData();

  /// `setData(registries, data)`: replaces the tag and reads the derived fields from it.
  void setData(CTag data);

  /// `slotsTargeted()`: how many ghost item slots the screen shows for this input.
  int slotsTargeted();

  /// `setItem(slot, stack)`: a ghost item chosen in the screen, as `ItemStack.CODEC` NBT.
  void setItem(int slot, CTag stack);

  /// `getItem(slot)`: the ghost item of a slot (an empty tag for none).
  CTag getItem(int slot);
}
