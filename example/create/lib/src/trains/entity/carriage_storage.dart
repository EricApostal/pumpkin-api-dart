// The cargo of a carriage as the train logic uses it (pure): `TrainCargoManager` in Java. The
// contraptions / logistics side implements it; `TrainCargo` (schedule) is the read-only view the
// wait conditions use.
import '../schedule/schedule_level.dart';
import '../util/ctag.dart';

abstract interface class CarriageStorage implements TrainCargo {
  /// `storage.write(tag, registries, spawnPacket)`. Named `writeCargo` because the mounted
  /// storage of a carriage contraption already has `write`/`read` with the `NbtMap` signature.
  void writeCargo(CTag tag, bool spawnPacket);

  /// `storage.read(tag, registries, spawnPacket, contraption)`.
  void readCargo(CTag tag, bool spawnPacket);

  /// `Train.burnFuel`: takes one fuel item out of the fuel inventory (the first slot whose item
  /// has a burn time), puts its crafting remainder back and returns the burn time gained in ticks
  /// (`burnTime * count`); 0 when there is no fuel.
  int extractFuel();
}

/// A cargo without items or fluids (`new TrainCargoManager()` before anything is loaded into it);
/// used when the contraptions side has not installed a [Carriage.storageFactory], and in tests.
final class EmptyCarriageStorage implements CarriageStorage {
  int _version = 0;
  int _ticksSinceLastExchange = 0;

  @override
  List<CargoItem> getAllItems() => const [];

  @override
  List<CargoFluid> getFluids() => const [];

  @override
  int getVersion() => _version;

  @override
  int getTicksSinceLastExchange() => _ticksSinceLastExchange;

  @override
  void resetIdleCargoTracker() {
    _ticksSinceLastExchange = 0;
  }

  @override
  void tickIdleCargoTracker() {
    _ticksSinceLastExchange++;
  }

  @override
  void writeCargo(CTag tag, bool spawnPacket) {}

  @override
  void readCargo(CTag tag, bool spawnPacket) {}

  @override
  int extractFuel() => 0;
}
