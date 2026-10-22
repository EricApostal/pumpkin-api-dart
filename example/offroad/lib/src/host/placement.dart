// The host half of `AbstractDirectionalAxisBlock`'s placement.
//
// The host's placement rules turn the clicked face into `facing`
// (`PlacementRule.clickedFace('facing')`, Java's `getFacingForPlacement`). The
// `axis_along_first` that goes with it cannot be expressed as a placement rule: it is
// `sneaking != alongFirst`, and `alongFirst` is the clicked face's own axis for a
// horizontal face but the player's horizontal *look* axis for a vertical one — two
// sources combined by a comparison no rule source provides. So it is applied from the
// block's `placed` callback, which is what Create's own kinetic blocks do
// (`buildKineticBehavior`'s `_placementFix`, `create/src/kinetics/behavior_builder.dart`).
//
// Host: this file uses `pumpkin_api`.
// ignore_for_file: implementation_imports
import 'package:create/src/api/blocks.dart' show HostBlockGetter, setBlockState;
import 'package:create/src/kinetics/runtime.dart' show KineticsRuntime;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../content/blocks/directional_axis.dart';

/// `AbstractDirectionalAxisBlock.getStateForPlacement`: sets `axis_along_first` on the
/// block [event] placed.
///
/// The sneak state is the one the recorded click carries
/// (`KineticsRuntime.instance.useRecords`, filled by the module's `playerUseBlock`
/// listener): the host's own placement rules read that click and the `placed` event does
/// not carry it. A placement without a record (a block placed by something other than a
/// player's click) falls back to the player's live state, as Create's placement
/// correction does.
Future<void> applyDirectionalAxisPlacement(Server server, CustomBlockPlacedEventData event) async {
  final playerId = event.player;
  if (playerId == null) return;

  final pos = (event.pos.x, event.pos.y, event.pos.z);
  final state = HostBlockGetter(event.targetWorld).stateAt(pos);
  if (!state.has('axis_along_first')) return;
  final facing = state.dir('facing');
  if (facing == null) return;

  final player = server.getPlayerByUuid(id: playerId);
  if (player == null) return;
  final record = KineticsRuntime.isLoaded
      ? KineticsRuntime.instance.useRecords.matching(playerId.asString, event.pos)
      : null;
  final sneaking = record?.sneaking ?? player.asEntity().isSneaking();

  final next = state.setFlag(
    'axis_along_first',
    axisAlongFirstForPlacement(
      facing: facing,
      horizontalLook: horizontalLookDirection(player.getYaw()),
      sneaking: sneaking,
    ),
  );
  if (next != state) await setBlockState(event.targetWorld, pos, next);
}