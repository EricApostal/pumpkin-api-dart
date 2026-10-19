// Services other modules provide to the schedule (pure interfaces).
import '../entity/train.dart';

/// What the contraptions / entity side knows about an entity that sits on a carriage
/// (`entity.getRootVehicle() instanceof CarriageContraptionEntity`).
final class ScheduleCarriagePassenger {
  /// `cce.getCarriage().train`; `null` when the carriage has no train.
  final Train? train;

  /// Whether the passenger sits in a seat of the contraption (`getSeatMapping().get(uuid) != null`).
  final bool seated;

  /// Whether that seat is a conductor seat (`cc.conductorSeats.get(seatPos) != null`).
  final bool conductorSeat;

  /// Whether the carriage's contraption is a `CarriageContraption`.
  final bool isCarriageContraption;

  /// Whether the passenger is a living entity (`entity instanceof LivingEntity`).
  final bool living;

  const ScheduleCarriagePassenger({
    required this.train,
    required this.seated,
    required this.conductorSeat,
    this.isCarriageContraption = true,
    this.living = true,
  });
}

/// Finds the carriage a clicked entity rides on. Provided by the entity / contraptions side with
/// `ctx.services.provide<ConductorSeatLookup>()`; without it schedules cannot be handed to
/// conductors.
abstract interface class ConductorSeatLookup {
  /// The passenger info of the entity with [entityId] in the world [worldId]; `null` when the
  /// entity does not ride a `CarriageContraptionEntity`.
  ScheduleCarriagePassenger? passengerOf(String worldId, int entityId);
}
