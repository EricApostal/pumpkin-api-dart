// Registration of the schedule area for the trains module (`TrainsModule` calls these).
//
// Registered here: the item `create:schedule`. Not registered here because the content module
// declares them from the manifest for everybody: the menu type `create:schedule`, the data
// component `create:train_schedule` (a network NBT compound), and the payload channels
// (`create:configure_schedule`, `create:c_configure_train`, `create:s_configure_train`,
// `create:submit_ghost_item`), whose handlers [loadSchedule] adds on the payload bus.
//
// Services consumed (optional): `ConductorSeatLookup` (schedule_services.dart, provided by the
// entity / contraptions side) to hand a schedule to a conductor; `CreateSounds`; `PayloadBus`.
import 'package:pumpkin_api/pumpkin_api.dart' show ItemRegistration;

import '../../core/module.dart';
import '../../core/registry.dart';
import '../../manifest/manifest.dart';
import 'schedule.dart';
import 'schedule_host.dart';

ScheduleHost? _host;

/// The host glue of the schedule area, `null` before [loadSchedule].
ScheduleHost? get scheduleHost => _host;

/// Phase 1: the item.
void registerSchedule(CreateRegistry registry) {
  Schedule.ensureRegistered();
  final item = kItems.firstWhere((i) => i.key == 'schedule');
  registry.item(ItemRegistration(key: 'create:schedule', maxStackSize: item.maxStack));
}

/// Phase 2: the item's right clicks, the conductor interaction and the payload handlers.
void loadSchedule(CreateContext ctx) {
  Schedule.ensureRegistered();
  _host = ScheduleHost(ctx)..install();
}

/// Plugin unload.
void unloadSchedule() {
  _host?.openMenus.clear();
  _host = null;
}
