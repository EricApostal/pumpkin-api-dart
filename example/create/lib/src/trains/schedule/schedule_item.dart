// `ScheduleItem` and `ScheduleItemEntityInteraction` (pure parts): reading the schedule of the item
// component and handing a schedule to, or taking it from, the train of a clicked conductor. The
// item registration, the menu and the event wiring are in `schedule_host.dart`.
import '../../core/nbt.dart' show NetworkNbt, NbtKind;
import '../util/ctag.dart';
import 'schedule.dart';
import 'schedule_services.dart';

/// The key of the item.
const String scheduleItemKey = 'create:schedule';

/// The key of the data component holding the schedule (`AllDataComponents.TRAIN_SCHEDULE`).
const String trainScheduleComponent = 'create:train_schedule';

/// The key of the menu type (`AllMenuTypes.SCHEDULE`).
const String scheduleMenuType = 'create:schedule';

/// The cooldown the item gets after an edit or a hand over (`addCooldown(stack, 5)`).
const int scheduleCooldownTicks = 5;

/// What `handScheduleTo` decided.
enum HandScheduleOutcome {
  /// `InteractionResult.PASS`: not a conductor.
  pass,

  /// `InteractionResult.SUCCESS` without further effect.
  success,

  /// "schedule.non_controlling_seat" with the deny sound.
  nonControllingSeat,

  /// "schedule.remove_with_empty_hand" with the deny sound: the train has a schedule already.
  removeWithEmptyHand,

  /// "schedule.no_stops" with the deny sound.
  noStops,

  /// The schedule was applied: confirm sound, "schedule.applied_to_train", one item is used.
  applied,
}

abstract final class ScheduleItem {
  /// `getSchedule(registries, stack)` from the bytes of the `create:train_schedule` component
  /// (network NBT), `null` when the stack has none.
  static Schedule? getSchedule(List<int>? component) {
    if (component == null) return null;
    final nbt = NetworkNbt.decode(component);
    if (nbt == null || nbt.kind != NbtKind.compound) return null;
    return Schedule.fromTag(CTag.fromNbt(nbt));
  }

  /// The component value for [schedule] (`stack.set(TRAIN_SCHEDULE, schedule.write(...))`).
  static List<int> encodeSchedule(Schedule schedule) => NetworkNbt.encode(schedule.write().toNbt());

  /// `handScheduleTo(stack, player, target, hand)` once the server side checks are done: [schedule]
  /// is the schedule of the held item, [passenger] what the clicked entity rides.
  static HandScheduleOutcome handScheduleTo(Schedule? schedule, ScheduleCarriagePassenger? passenger) {
    if (schedule == null) return HandScheduleOutcome.pass;
    if (passenger == null || !passenger.living) return HandScheduleOutcome.pass;
    if (!passenger.isCarriageContraption) return HandScheduleOutcome.success;

    final train = passenger.train;
    if (train == null) return HandScheduleOutcome.success;
    if (!passenger.seated) return HandScheduleOutcome.success;
    if (!passenger.conductorSeat) return HandScheduleOutcome.nonControllingSeat;
    if (train.runtime.getSchedule() != null) return HandScheduleOutcome.removeWithEmptyHand;
    if (schedule.entries.isEmpty) return HandScheduleOutcome.noStops;

    train.runtime.setSchedule(schedule, false);
    return HandScheduleOutcome.applied;
  }
}

/// What the conductor interaction without a schedule item decided.
enum ConductorClickOutcome {
  /// Nothing happens (no schedule, not a conductor seat, ...).
  ignore,

  /// The paused schedule continues ("schedule.continued", confirm sound).
  resumed,

  /// The player holds something: deny sound and "schedule.remove_with_empty_hand".
  denyHeldItem,

  /// The schedule was taken off the train; [ConductorClick.returned] is the schedule tag for the item.
  returned,
}

final class ConductorClick {
  final ConductorClickOutcome outcome;

  /// The tag of the returned schedule (for a new schedule item); `null` for an automatic one.
  final CTag? returned;

  /// Whether the schedule that was taken was an automatic one.
  final bool wasAuto;

  const ConductorClick(this.outcome, {this.returned, this.wasAuto = false});
}

/// The part of `ScheduleItemEntityInteraction.interactWithConductor` after the schedule item check.
ConductorClick interactWithConductor(ScheduleCarriagePassenger? passenger, {required bool handEmpty}) {
  const ignore = ConductorClick(ConductorClickOutcome.ignore);
  if (passenger == null || !passenger.living || !passenger.isCarriageContraption) return ignore;
  final train = passenger.train;
  if (train == null) return ignore;
  if (train.runtime.getSchedule() == null) return ignore;
  if (!passenger.seated) return ignore;
  if (!passenger.conductorSeat) return ignore;

  if (train.runtime.paused && !train.runtime.completed) {
    train.runtime.paused = false;
    return const ConductorClick(ConductorClickOutcome.resumed);
  }

  if (!handEmpty) return const ConductorClick(ConductorClickOutcome.denyHeldItem);

  final wasAuto = train.runtime.isAutoSchedule;
  final returned = train.runtime.returnSchedule();
  return ConductorClick(ConductorClickOutcome.returned, returned: returned, wasAuto: wasAuto);
}
