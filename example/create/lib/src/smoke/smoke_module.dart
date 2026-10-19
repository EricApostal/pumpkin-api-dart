// FRAMEWORK SMOKE TEST. Not part of Create: it proves registration, block entity
// creation, batched ticking, NBT persistence and the config switch work.
// Active only with `"core": {"debug_smoke_test": true}`. Place `create:smoke_block`;
// its entity counts ticks, saves the counter (mappable state) every second and logs
// it every 10 seconds, so a restart shows the counter continuing.
import 'package:dart_mappable/dart_mappable.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/block_entity.dart';
import '../core/blocks.dart';
import '../core/config.dart';
import '../core/module.dart';
import '../core/registry.dart';

part 'smoke_module.mapper.dart';

@MappableClass()
class SmokeState with SmokeStateMappable {
  final int count;

  const SmokeState({this.count = 0});
}

final class SmokeBlockEntity extends MappableBlockEntity<SmokeState> {
  static const String type = 'create:smoke_block';
  static Logger? log;

  SmokeBlockEntity(super.worldId, super.pos);

  @override
  SmokeState initialState() => const SmokeState();

  @override
  SmokeState stateFromMap(Map<String, dynamic> map) => SmokeStateMapper.fromMap(map);

  @override
  Map<String, dynamic> stateToMap(SmokeState state) => state.toMap();

  @override
  void tick() {
    super.tick();
    state = SmokeState(count: state.count + 1);
    if (state.count % 20 == 0) markDirty();
    if (state.count % 200 == 0) log?.info('smoke block at ${pos.x}, ${pos.y}, ${pos.z}: ${state.count} ticks');
  }
}

final class SmokeTestModule extends CreateModule {
  @override
  String get name => 'smoke_test';

  @override
  bool isEnabled(CreateConfig config) => config.core.debugSmokeTest;

  @override
  void register(CreateRegistry registry) {
    registry.blockEntityType(
      const BlockEntityTypeSpec(
        key: SmokeBlockEntity.type,
        validBlocks: ['create:smoke_block'],
        create: SmokeBlockEntity.new,
      ),
    );
    registry.block(CreateBlock(key: 'create:smoke_block', blockEntityType: SmokeBlockEntity.type));
  }

  @override
  void onLoad(CreateContext ctx) {
    SmokeBlockEntity.log = ctx.log;
  }
}
