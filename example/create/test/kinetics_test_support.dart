// A fake world and fake kinetic block entities for the kinetics unit tests.
import 'package:create/src/kinetics/block_defs.dart';
import 'package:create/src/kinetics/generating.dart';
import 'package:create/src/kinetics/geometry.dart';
import 'package:create/src/kinetics/node.dart';
import 'package:create/src/kinetics/settings.dart';
import 'package:create/src/kinetics/transmission.dart';

class FakeLevel extends KineticLevel {
  @override
  KineticConfig settings;
  @override
  final KineticBlockRegistry blocks = KineticBlockRegistry();
  @override
  late KineticStressTable stress = KineticStressTable(const KineticsSettings());

  final Map<KPos, FakeNode> nodes = {};
  final Map<KPos, KState> states = {};
  final Set<KPos> unloaded = {};
  final List<KPos> destroyed = [];
  @override
  bool isTickFrozen = false;

  FakeLevel({this.settings = const KineticsSettings()}) {
    const axis = AxisBlockDef();
    blocks.register('create:shaft', axis);
    blocks.register('create:cogwheel', const AxisBlockDef(smallCog: true, dedicatedCog: true));
    blocks.register('create:large_cogwheel', const AxisBlockDef(largeCog: true, dedicatedCog: true));
    blocks.register('create:gearbox', const AxisBlockDef(shaftAlongAxis: false));
    blocks.register('create:creative_motor', const FacingBlockDef());
    blocks.register('create:machine', axis);
    blocks.register('create:gearshift', axis);
    blocks.register('create:clutch', axis);
  }

  FakeSplitShaft split(String kind, int x, int y, int z, {KAxis axis = KAxis.y, bool powered = false}) {
    final state = KState('create:$kind', {'axis': axis.name, if (kind != 'gearbox') 'powered': '$powered'});
    final node = FakeSplitShaft(this, KPos(x, y, z), state, kind);
    nodes[node.kpos] = node;
    states[node.kpos] = state;
    return node;
  }

  FakeNode place(KPos pos, KState state, {double generated = 0, int? generatorKind}) {
    final node = generated != 0 ? FakeGenerator(this, pos, state, generated) : FakeNode(this, pos, state);
    nodes[pos] = node;
    states[pos] = state;
    return node;
  }

  FakeNode shaft(int x, int y, int z, {KAxis axis = KAxis.x}) =>
      place(KPos(x, y, z), KState('create:shaft', {'axis': axis.name}));

  FakeNode cog(int x, int y, int z, {KAxis axis = KAxis.y, bool large = false}) =>
      place(KPos(x, y, z), KState(large ? 'create:large_cogwheel' : 'create:cogwheel', {'axis': axis.name}));

  FakeNode machine(int x, int y, int z, {KAxis axis = KAxis.x}) =>
      place(KPos(x, y, z), KState('create:machine', {'axis': axis.name}));

  FakeGenerator motor(int x, int y, int z, double speed, {Dir facing = Dir.east}) =>
      place(KPos(x, y, z), KState('create:creative_motor', {'facing': facing.name}), generated: speed) as FakeGenerator;

  /// Runs `tick()` of every node once (what the block entity ticker does).
  void tickAll([int times = 1]) {
    for (var i = 0; i < times; i++) {
      for (final n in nodes.values.toList()) {
        n.tick();
      }
    }
  }

  /// Removes a block like breaking it.
  void remove(KPos pos) {
    final node = nodes.remove(pos);
    states.remove(pos);
    node?.kineticRemove();
  }

  @override
  KineticNode? nodeAt(KPos pos) => unloaded.contains(pos) ? null : nodes[pos];

  @override
  KState stateAt(KPos pos) => states[pos] ?? KState.air;

  @override
  bool isLoaded(KPos pos) => !unloaded.contains(pos);

  @override
  void destroyBlock(KPos pos) {
    destroyed.add(pos);
    remove(pos);
  }
}

class FakeNode with KineticNodeMixin {
  final FakeLevel _level;
  final KPos _pos;
  KState state;
  int sent = 0;
  int changed = 0;
  bool initialized = false;

  FakeNode(this._level, this._pos, this.state);

  @override
  KPos get kpos => _pos;

  @override
  FakeLevel get level => _level;

  @override
  KState get blockState => state;

  @override
  void sendData() => sent++;

  @override
  void markChanged() => changed++;

  void tick() {
    kineticTickStart();
    if (!initialized) {
      initialized = true;
      kineticInitialize();
    }
    kineticTickEnd();
  }

  /// `SimpleKineticBlockEntity.addPropagationLocations`: large cogs also look at
  /// all twelve edge diagonals.
  @override
  List<KPos> addPropagationLocations(KineticBlockDef block, KState state, List<KPos> neighbours) {
    if (!block.isLargeCog) return super.addPropagationLocations(block, state, neighbours);
    for (var z = -1; z <= 1; z++) {
      for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
          if (x * x + y * y + z * z == 2) neighbours.add(kpos.offset(x, y, z));
        }
      }
    }
    return neighbours;
  }
}

class FakeController extends FakeNode implements SpeedControllerNode {
  @override
  int targetSpeedValue;

  FakeController(super.level, super.pos, super.state, this.targetSpeedValue);
}

class FakeGenerator extends FakeNode with GeneratingNodeMixin {
  double target;

  FakeGenerator(super.level, super.pos, super.state, this.target);

  @override
  double get generatedSpeed => target;

  @override
  void tick() {
    kineticTickStart();
    if (!initialized) {
      initialized = true;
      kineticInitialize();
      if (!hasSource || generatedSpeed > theoreticalSpeed) updateGeneratedRotation();
    }
    kineticTickEnd();
    generatingTick();
  }
}

/// A gearbox / gearshift / clutch for the tests: a split shaft with the ratios of Create.
class FakeSplitShaft extends FakeNode {
  final String kind; // gearbox, gearshift, clutch

  FakeSplitShaft(super.level, super.pos, super.state, this.kind);

  Dir get sourceFacing {
    final s = source ?? kpos;
    final d = s - kpos;
    return Dir.approximateNearest(d.x, d.y, d.z);
  }

  @override
  double shaftHalvesModifier(Dir direction) {
    final powered = state.flag('powered');
    return switch (kind) {
      'gearbox' => gearboxModifier(direction, sourceFacing),
      'gearshift' => gearshiftModifier(hasSource: hasSource, face: direction, sourceFacing: sourceFacing, powered: powered),
      _ => clutchModifier(hasSource: hasSource, face: direction, sourceFacing: sourceFacing, powered: powered),
    };
  }
}
