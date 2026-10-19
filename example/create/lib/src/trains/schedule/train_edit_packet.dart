// `TrainEditPacket` (pure part): rename a train, change its icon and map colour. The serverbound
// `create:c_configure_train` edits the train and answers every client with
// `create:s_configure_train` (`TrainEditReturnPacket`), which has the same fields.
import '../../redstone/support/text.dart' show Txt;
import '../entity/train_icon_type.dart';
import '../manager/create.dart';

final class TrainEditPacket {
  final String id;
  final String name;
  final String iconType;
  final int mapColor;

  const TrainEditPacket(this.id, this.name, this.iconType, this.mapColor);

  /// From the payload map (`id`, `name`, `iconType`, `mapColor`).
  factory TrainEditPacket.fromFields(Map<String, Object?> f) =>
      TrainEditPacket(f['id']! as String, f['name']! as String, f['iconType']! as String, f['mapColor']! as int);

  Map<String, Object?> toFields() => {'id': id, 'name': name, 'iconType': iconType, 'mapColor': mapColor};

  /// `handleSided(sender)` on the server: edits the train and returns the packet to send to all
  /// clients, or `null` when the train does not exist.
  TrainEditPacket? handleServer() {
    final train = Create.RAILWAYS.trains[id];
    if (train == null) return null;
    if (name.trim().isNotEmpty) {
      train.name = Txt.literal(name);
    }
    train.icon = TrainIconType.byId(iconType);
    train.mapColorIndex = mapColor;
    return TrainEditPacket(id, name, iconType, mapColor);
  }
}
