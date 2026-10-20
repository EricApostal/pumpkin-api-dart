// `BlockMovementChecks` + `BlockMovementChecksImpl` (pure): which blocks a contraption has to move,
// may move, treats as brittle, drags along because they are attached, or does not drag along
// because they are not supportive. Other modules register checks; the fallbacks are Create's.
import '../../api/block_state.dart';
import '../../common/common.dart';
import 'level.dart';
import 'structure_info.dart';

/// `BlockMovementChecks.CheckResult`.
enum CheckResult {
  success,
  fail,
  pass;

  static CheckResult of(bool? b) => b == null ? pass : (b ? success : fail);
}

typedef MovementNecessaryCheck = CheckResult Function(BState state, ContraptionLevel level, Pos pos);
typedef MovementAllowedCheck = CheckResult Function(BState state, ContraptionLevel level, Pos pos);
typedef BrittleCheck = CheckResult Function(BState state);
typedef AttachedCheck = CheckResult Function(BState state, ContraptionLevel level, Pos pos, Direction direction);
typedef NotSupportiveCheck = CheckResult Function(BState state, Direction direction);

/// The registry of movement checks (`api/contraption/BlockMovementChecks`).
///
/// Each query asks the registered checks, newest first; the first non-[CheckResult.pass] answer
/// wins; if no check answers, the fallback of Create is used.
abstract final class BlockMovementChecks {
  static final List<MovementNecessaryCheck> _necessary = [];
  static final List<MovementAllowedCheck> _allowed = [];
  static final List<BrittleCheck> _brittle = [];
  static final List<AttachedCheck> _attached = [];
  static final List<NotSupportiveCheck> _notSupportive = [];

  static void registerMovementNecessaryCheck(MovementNecessaryCheck check) => _necessary.insert(0, check);
  static void registerMovementAllowedCheck(MovementAllowedCheck check) => _allowed.insert(0, check);
  static void registerBrittleCheck(BrittleCheck check) => _brittle.insert(0, check);
  static void registerAttachedCheck(AttachedCheck check) => _attached.insert(0, check);
  static void registerNotSupportiveCheck(NotSupportiveCheck check) => _notSupportive.insert(0, check);

  /// Removes every registered check (tests).
  static void clear() {
    _necessary.clear();
    _allowed.clear();
    _brittle.clear();
    _attached.clear();
    _notSupportive.clear();
  }

  /// Whether it is necessary to move the block; contraptions ignore unnecessary blocks.
  static bool isMovementNecessary(BState state, ContraptionLevel level, Pos pos) {
    for (final check in _necessary) {
      final r = check(state, level, pos);
      if (r != CheckResult.pass) return r == CheckResult.success;
    }
    return _movementNecessaryFallback(state, level, pos);
  }

  /// Whether the block is movable; an immobile block prevents assembly.
  static bool isMovementAllowed(BState state, ContraptionLevel level, Pos pos) {
    for (final check in _allowed) {
      final r = check(state, level, pos);
      if (r != CheckResult.pass) return r == CheckResult.success;
    }
    return _movementAllowedFallback(state, level, pos);
  }

  /// Brittle blocks need another block for support (torches, ladders); they are collected first
  /// so they do not break when their support is removed.
  static bool isBrittle(BState state, [ContraptionLevel? level]) {
    for (final check in _brittle) {
      final r = check(state);
      if (r != CheckResult.pass) return r == CheckResult.success;
    }
    return _brittleFallback(state, level);
  }

  /// Whether the block is attached to the block in [direction]; attached blocks move together.
  static bool isBlockAttachedTowards(BState state, ContraptionLevel level, Pos pos, Direction direction) {
    for (final check in _attached) {
      final r = check(state, level, pos, direction);
      if (r != CheckResult.pass) return r == CheckResult.success;
    }
    return _attachedFallback(state, level, pos, direction);
  }

  /// Whether the block does not support what is in [facing] direction; this stops the propagation.
  static bool isNotSupportive(BState state, Direction facing, [ContraptionLevel? level]) {
    for (final check in _notSupportive) {
      final r = check(state, facing);
      if (r != CheckResult.pass) return r == CheckResult.success;
    }
    return _notSupportiveFallback(state, facing, level);
  }
}

// -- Classification of vanilla blocks by key ---------------------------------------------------------

String _path(String key) {
  final i = key.indexOf(':');
  return i < 0 ? key : key.substring(i + 1);
}

bool _vanilla(BState s) => s.key.startsWith('minecraft:');

bool _isLadder(BState s) => s.key == 'minecraft:ladder';

/// `BaseTorchBlock` (torches, soul torches, redstone torches, copper torches).
bool _isTorch(BState s) => _vanilla(s) && _path(s.key).endsWith('torch');

bool _isWallTorch(BState s) => _isTorch(s) && _path(s.key).contains('wall') && !_path(s.key).startsWith('redstone');

bool _isRedstoneWallTorch(BState s) => s.key == 'minecraft:redstone_wall_torch';

/// `SignBlock` (all standing, wall and hanging signs).
bool _isSign(BState s) => _vanilla(s) && _path(s.key).endsWith('sign');

bool _isWallSign(BState s) => _vanilla(s) && _path(s.key).endsWith('wall_sign');

bool _isStandingSign(BState s) => _vanilla(s) && _path(s.key).endsWith('sign') && !_path(s.key).contains('wall') && !_path(s.key).contains('hanging');

bool _isPressurePlate(BState s) => _vanilla(s) && _path(s.key).endsWith('pressure_plate');

bool _isDoor(BState s) => s.has('hinge') && s.has('half') && s.has('open') && s.has('facing');

bool _isBed(BState s) => _vanilla(s) && _path(s.key).endsWith('_bed') && s.has('part');

bool _isFlowerPot(BState s) => s.key == 'minecraft:flower_pot' || (_vanilla(s) && _path(s.key).startsWith('potted_'));

bool _isDiode(BState s) {
  if (s.key == 'minecraft:repeater' || s.key == 'minecraft:comparator') return true;
  return switch (s.key) {
    'create:pulse_extender' || 'create:pulse_repeater' || 'create:pulse_timer' || 'create:powered_latch' || 'create:powered_toggle_latch' => true,
    _ => false,
  };
}

bool _isRedstoneWire(BState s) => s.key == 'minecraft:redstone_wire';

bool _isCarpet(BState s) => _vanilla(s) && _path(s.key).endsWith('_carpet') && !_path(s.key).contains('moss');

bool _isRail(BState s) =>
    s.key == 'minecraft:rail' ||
    s.key == 'minecraft:powered_rail' ||
    s.key == 'minecraft:detector_rail' ||
    s.key == 'minecraft:activator_rail' ||
    s.key == 'create:controller_rail';

bool _isCartAssembler(BState s) => s.key == 'create:cart_assembler';

/// `FaceAttachedHorizontalDirectionalBlock`: levers, buttons, grindstones, packager links.
bool _isFaceAttached(BState s) => s.has('face') && s.has('facing') && (s['face'] == 'floor' || s['face'] == 'wall' || s['face'] == 'ceiling');

bool _isGrindstone(BState s) => s.key == 'minecraft:grindstone';

bool _isWhistle(BState s) => s.key == 'create:steam_whistle';

bool _isWhistleExtension(BState s) => s.key == 'create:steam_whistle_extension';

bool _isBeltFunnel(BState s) => s.key == 'create:andesite_belt_funnel' || s.key == 'create:brass_belt_funnel';

bool _isSail(BState s) => _path(s.key) == 'sail_frame' || (s.key.startsWith('create:') && _path(s.key).endsWith('_sail'));

bool _isAttachedActor(BState s) => switch (s.key) {
  'create:mechanical_harvester' || 'create:mechanical_plough' || 'create:mechanical_roller' => true,
  _ => false,
};

bool _isBogey(BState s) => s.key == 'create:small_bogey' || s.key == 'create:large_bogey';

bool _isTrack(BState s) => s.key == 'create:track' || s.key == 'create:fake_track';

bool _isStation(BState s) => s.key == 'create:track_station';

bool _isPiston(BState s) => s.key == 'create:mechanical_piston' || s.key == 'create:sticky_mechanical_piston';

bool _isBearing(BState s) =>
    s.key == 'create:mechanical_bearing' || s.key == 'create:windmill_bearing' || s.key == 'create:clockwork_bearing';

bool _isChassis(BState s) =>
    s.key == 'create:linear_chassis' || s.key == 'create:secondary_linear_chassis' || s.key == 'create:radial_chassis';

bool _isMultiblock(BState s) => s.key == 'create:fluid_tank' || s.key == 'create:creative_fluid_tank' || s.key == 'create:item_vault';

bool _isSlidingDoor(BState s) => s.has('visible') && _isDoor(s);

// -- Fallbacks -----------------------------------------------------------------------------------------

bool _movementNecessaryFallback(BState state, ContraptionLevel level, Pos pos) {
  if (BlockMovementChecks.isBrittle(state, level)) return true;
  if (level.stateHasTag(state, 'create:movable_empty_collider')) return true;
  if (level.stateCollisionEmpty(state)) return false;
  return !level.stateReplaceable(state);
}

bool _movementAllowedFallback(BState state, ContraptionLevel level, Pos pos) {
  if (_isChassis(state)) return true;
  if (level.isUnbreakable(state)) return false;
  if (level.stateHasTag(state, 'c:relocation_not_supported')) return false;
  if (level.stateHasTag(state, 'create:non_movable')) return false;
  if (level.settings.movementSettingOf(state.key) == ContraptionMovementSetting.unmovable) return false;

  // Move controllers only when they aren't moving.
  if (_isPiston(state) && state['state'] != 'moving') return true;
  if (state.key == 'create:mechanical_bearing' || state.key == 'create:clockwork_bearing') {
    if (level.blockEntityAt(pos) != null) return !level.isActuatorRunning(pos);
  }
  if (state.key == 'create:rope_pulley') {
    if (level.blockEntityAt(pos) != null) return !level.isActuatorRunning(pos);
  }

  if (state.key == 'create:belt') return true;
  if (_isGrindstone(state)) return true;
  if (_isTrack(state)) return false;
  if (_isStation(state)) return false;
  return level.pushReaction(state) != PushReaction.block;
}

bool _brittleFallback(BState state, ContraptionLevel? level) {
  if (state.has('hanging')) return true;
  if (_isLadder(state)) return true;
  if (_isTorch(state)) return true;
  if (_isSign(state)) return true;
  if (_isPressurePlate(state)) return true;
  if (_isFaceAttached(state) && !_isGrindstone(state) && state.key != 'create:stock_link') return true;
  if (_isCartAssembler(state)) return false;
  if (_isRail(state)) return true;
  if (_isDiode(state)) return true;
  if (_isRedstoneWire(state)) return true;
  if (_isCarpet(state)) return true;
  if (_isWhistle(state)) return true;
  if (_isWhistleExtension(state)) return true;
  if (_isBeltFunnel(state)) return true;
  return level?.stateHasTag(state, 'create:brittle') ?? false;
}

bool _attachedFallback(BState state, ContraptionLevel level, Pos pos, Direction direction) {
  final opposite = direction.opposite;
  if (_isLadder(state)) return state.dir('facing') == opposite;
  if (_isWallTorch(state)) return state.dir('facing') == opposite;
  if (_isWallSign(state)) return state.dir('facing') == opposite;
  if (_isStandingSign(state)) return direction == Direction.down;
  if (_isPressurePlate(state)) return direction == Direction.down;
  if (_isDoor(state)) {
    if (state['half'] == 'lower' && direction == Direction.up) return true;
    return direction == Direction.down;
  }
  if (_isBed(state)) {
    var facing = state.dir('facing') ?? Direction.north;
    if (state['part'] == 'head') facing = facing.opposite;
    return direction == facing;
  }
  if (state.key == 'create:redstone_link') return opposite == state.dir('facing');
  if (_isFlowerPot(state)) return direction == Direction.down;
  if (_isDiode(state)) return direction == Direction.down;
  if (_isRedstoneWire(state)) return direction == Direction.down;
  if (_isCarpet(state)) return direction == Direction.down;
  if (_isRedstoneWallTorch(state)) return state.dir('facing') == opposite;
  if (_isTorch(state)) return direction == Direction.down;
  if (_isFaceAttached(state)) {
    final face = state['face'];
    if (face == 'ceiling') return direction == Direction.up;
    if (face == 'floor') return direction == Direction.down;
    if (face == 'wall') return opposite == state.dir('facing');
  }
  if (state.has('hanging')) return direction == (state.flag('hanging') ? Direction.up : Direction.down);
  if (_isRail(state)) return direction == Direction.down;
  if (_isAttachedActor(state)) return direction == state.dir('facing')?.opposite;
  if (state.key == 'create:hand_crank') return direction == state.dir('facing')?.opposite;
  if (state.key == 'create:nozzle') return direction == state.dir('facing')?.opposite;
  if (state.key == 'minecraft:bell') {
    final attachment = state['attachment'];
    if (attachment == 'floor') return direction == Direction.down;
    if (attachment == 'ceiling') return direction == Direction.up;
    return direction == state.dir('facing');
  }
  if (_isSail(state)) return direction.axis != state.dir('facing')?.axis;
  if (_isMultiblock(state)) return level.isConnected(pos, pos.relative(direction));
  if (state.key == 'create:sticker' && state.flag('extended')) {
    return direction == state.dir('facing') &&
        !BlockMovementChecks.isNotSupportive(level.stateAt(pos.relative(direction)), opposite, level);
  }
  if (_isBogey(state)) {
    final axis = state.axisOf('horizontal_axis') ?? Axis.x;
    final sticky = axis == Axis.x ? const [Direction.east, Direction.west] : const [Direction.south, Direction.north];
    return sticky.contains(direction);
  }
  if (_isWhistle(state)) return direction == (state.flag('wall') ? state.dir('facing') : Direction.down);
  if (_isWhistleExtension(state)) return direction == Direction.down;
  return false;
}

bool _notSupportiveFallback(BState state, Direction facing, ContraptionLevel? level) {
  if (state.key == 'create:mechanical_drill') return state.dir('facing') == facing;
  if (state.key == 'create:mechanical_bearing') return state.dir('facing') == facing;
  if (_isCartAssembler(state)) return facing == Direction.down;
  if (state.key == 'create:mechanical_saw') return state.dir('facing') == facing;
  if (state.key == 'create:portable_storage_interface') return state.dir('facing') == facing;
  if (_isAttachedActor(state) && state.key != 'create:mechanical_roller') return state.dir('facing') == facing;
  if (state.key == 'create:rope_pulley') return facing == Direction.down;
  if (_isCarpet(state)) return facing == Direction.up;
  if (_isSail(state)) return facing.axis == state.dir('facing')?.axis;
  if (state.key == 'create:piston_extension_pole') return facing.axis != state.dir('facing')?.axis;
  if (state.key == 'create:mechanical_piston_head') return facing.axis != state.dir('facing')?.axis;
  if (state.key == 'create:sticker' && !state.flag('extended')) return facing == state.dir('facing');
  if (_isSlidingDoor(state)) return false;
  return BlockMovementChecks.isBrittle(state, level);
}

/// Whether a state is a Create chassis block.
bool isChassisState(BState s) => _isChassis(s);

/// Whether a state is a mechanical piston base (normal or sticky).
bool isPistonState(BState s) => _isPiston(s);

/// Whether a state is a bearing of any kind.
bool isBearingState(BState s) => _isBearing(s);
