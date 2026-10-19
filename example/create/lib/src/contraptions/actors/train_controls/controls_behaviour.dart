// `ControlsMovementBehaviour`, `ControlsInteractionBehaviour` and `ControlsServerHandler`: driving a
// train from the controls block on a carriage.
import '../../../common/common.dart';
import '../../core/contraption.dart';
import '../../core/movement.dart';
import '../../entity/contraption_entity.dart';
import '../../entity/contraption_handler.dart';
import '../../storage/stacks.dart';

/// `ControlsMovementBehaviour`.
final class ControlsMovementBehaviour extends MovementBehaviour {
  const ControlsMovementBehaviour();

  /// The controls cannot be disabled by contraption controls.
  @override
  StoredStack? canBeDisabledVia(MovementContext context) => null;

  @override
  void stopMoving(MovementContext context) {
    final entity = context.contraption.entity;
    if (entity is AbstractContraptionEntity)
      entity.stopControlling(context.localPos);
    super.stopMoving(context);
  }
}

/// `ControlsInteractionBehaviour`.
final class ControlsInteractionBehaviour extends MovingInteractionBehaviour {
  const ControlsInteractionBehaviour();

  @override
  bool handlePlayerInteraction(
    InteractingPlayer player,
    Pos localPos,
    Contraption contraption,
  ) {
    if (player.holdsWrench) return false;

    final entity = contraption.entity;
    if (entity is! AbstractContraptionEntity) return false;

    final currentlyControlling = entity.controllingPlayer;
    if (currentlyControlling != null) {
      entity.stopControlling(localPos);
      if (currentlyControlling == player.uuid) return true;
    }

    if (!entity.startControlling(localPos, player)) return false;
    entity.setControllingPlayer(player.uuid);
    return true;
  }
}

/// `ControlsServerHandler.ManuallyPressedKey`: a held key with a keep-alive counter.
final class ManuallyPressedKey extends IntAttached<int> {
  ManuallyPressedKey(int value) : super(ControlsServerHandler.timeout, value);

  void keepAlive() => first = ControlsServerHandler.timeout;

  bool isAlive() => first > 0;
}

/// `ControlsServerHandler.ControlsContext`.
final class ControlsContext {
  final AbstractContraptionEntity entity;
  final Pos controlsLocalPos;
  final List<ManuallyPressedKey> keys = [];

  ControlsContext(this.entity, this.controlsLocalPos);
}

/// Resolves the host `Player` of a uuid as an [InteractingPlayer], or `null`.
typedef ControlsPlayerResolver = InteractingPlayer? Function(String uuid);

/// `ControlsServerHandler`: the keys players hold on the controls of a contraption.
final class ControlsServerHandler {
  static const int timeout = 30;

  final Map<String, Map<String, ControlsContext>> _received = {};

  /// `tick`: advances the held keys and passes them to the contraption entity.
  void tick(String worldId, ControlsPlayerResolver playerOf) {
    final map = _received[worldId];
    if (map == null) return;
    for (final entry in map.entries.toList()) {
      final ctx = entry.value;
      if (!ctx.entity.isAlive) {
        map.remove(entry.key);
        continue;
      }

      for (final key in List.of(ctx.keys)) {
        key.decrement();
        if (!key.isAlive()) ctx.keys.remove(key);
      }

      final player = playerOf(entry.key);
      if (player == null) {
        ctx.entity.stopControlling(ctx.controlsLocalPos);
        map.remove(entry.key);
        continue;
      }

      if (!ctx.entity.control(
        ctx.controlsLocalPos,
        ctx.keys.map((k) => k.value).toList(),
        player,
      )) {
        ctx.entity.stopControlling(ctx.controlsLocalPos);
      }

      if (ctx.keys.isEmpty) map.remove(entry.key);
    }
  }

  /// `receivePressed`: a client packet pressed or released [keys].
  void receivePressed(
    String worldId,
    AbstractContraptionEntity entity,
    Pos controlsPos,
    String uuid,
    Iterable<int> keys,
    bool pressed,
  ) {
    final map = _received.putIfAbsent(worldId, () => {});
    if (map.containsKey(uuid) && !identical(map[uuid]!.entity, entity))
      map.remove(uuid);

    final ctx = map.putIfAbsent(
      uuid,
      () => ControlsContext(entity, controlsPos),
    );
    final list = ctx.keys;

    for (final activated in keys) {
      ManuallyPressedKey? existing;
      for (final key in list) {
        if (key.value == activated) {
          existing = key;
          break;
        }
      }
      if (existing != null) {
        if (pressed) {
          existing.keepAlive();
        } else {
          existing.first = 0;
        }
        continue;
      }
      if (!pressed) continue;
      list.add(ManuallyPressedKey(activated));
    }
  }

  void forgetWorld(String worldId) => _received.remove(worldId);
}

/// `ContraptionHandler.entityById`: the contraption entity a client packet refers to.
AbstractContraptionEntity? controlsEntityAt(String worldId, int entityId) =>
    ContraptionHandler.entityById(worldId, entityId);
