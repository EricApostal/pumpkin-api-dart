// `TrainHUDUpdatePacket.Serverbound` (serverbound `create:c_train_hud`): the throttle the driver
// set in the HUD. The manifest carries the optional `throttle` plus the `speed` / `fuelTicks` the
// client shows; only the throttle is an input. The handler answers with the clientbound HUD so the
// sender renders the state the server accepted.
import '../../api/payloads.dart';
import '../../core/module.dart';
import '../manager/create.dart';
import '../support/runtime.dart';

/// Installs the handler on the payload bus.
void installTrainHudPacket(CreateContext ctx) {
  final bus = ctx.services.find<PayloadBus>();
  bus?.onServerbound('create:c_train_hud', (player, fields) {
    final trainId = fields['trainId'] as String?;
    if (trainId == null) return;
    final train = Create.RAILWAYS.trains[trainId];
    if (train == null) return;

    final throttle = fields['throttle'];
    if (throttle is double) {
      train.throttle = throttle;
      Tr.i.log.debug('Train ${train.id} throttle set to $throttle');
    }

    bus.sendClientbound('create:s_train_hud', player, {
      'trainId': train.id,
      'throttle': train.throttle,
      'speed': train.speedBeforeStall ?? train.speed,
      'fuelTicks': train.fuelTicks,
    });
  });
}
