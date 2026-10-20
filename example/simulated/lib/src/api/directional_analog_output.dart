// `dev.simulated_team.simulated.api.IDirectionalAnalogOutput`: a block whose
// comparator output depends on the side it is read from (steering wheel,
// torsion spring).
//
// Pure: no host imports.
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;

/// Java: `dev.simulated_team.simulated.api.IDirectionalAnalogOutput`
abstract interface class IDirectionalAnalogOutput {
  /// `getAnalogOutputSignalFrom(state, level, pos, dir)`.
  int getAnalogOutputSignalFrom(BState state, Direction dir);
}
