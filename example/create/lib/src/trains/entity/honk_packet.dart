// `HonkPacket.Serverbound` (serverbound `create:c_train_honk`): the driver honks the train. The
// server awards the whistle advancement and broadcasts the clientbound honk to everyone.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart';
import '../../core/module.dart';
import '../manager/create.dart';
import 'train_host.dart' show trainWhistleAdvancement;
import 'train_level.dart';

/// Installs the handler on the payload bus.
void installHonkPacket(CreateContext ctx) {
  final bus = ctx.services.find<PayloadBus>();
  bus?.onServerbound('create:c_train_honk', (player, fields) {
    final trainId = fields['trainId'] as String?;
    if (trainId == null) return;
    final train = Create.RAILWAYS.trains[trainId];
    if (train == null) return;

    final isHonk = fields['isHonk'] == true;
    TrainFx.effects.awardAdvancement(
      player.getId().asString,
      trainWhistleAdvancement,
    );
    bus.sendClientboundAll('create:s_train_honk', bus.roster.players, {
      'trainId': train.id,
      'isHonk': isHonk,
    });

    final (x, y, z) = player.getPosition();
    TrainFx.effects.gameEvent(
      player.getWorld().getId(),
      'minecraft:resonate_15',
      (x, y, z),
    );
  });
}
