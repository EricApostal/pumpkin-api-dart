// Which manifest blocks the decoration module owns, what each one is, and how it is built.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../core/blocks.dart';
import '../manifest/manifest.dart';
import 'roles.dart';
import 'shape_rules.dart';
import 'block_entities.dart';
import 'blocks_copycat.dart';
import 'blocks_door.dart';
import 'blocks_girder.dart';
import 'blocks_misc.dart';
import 'blocks_placard.dart';
import 'blocks_whistle.dart';
import 'families.dart';
import 'runtime.dart';
import 'shapes.dart';

/// Builds the [CreateBlock] for [m].
CreateBlock buildDecorationBlock(ManifestBlock m, DecorationRuntime rt) {
  final role = roleOf(m);
  BlockDrops? drops;
  if (role == DecorationRole.whistleExtension || role == DecorationRole.copycatBars || role == DecorationRole.copycatBase) {
    drops = BlockDrops.nothing;
  } else if (usesLootTable(m, role)) {
    drops = lootTableOf(m.key);
  }
  final copper = isCreateCopper(m);
  final weathering = copper && m.javaClass.contains('Weathering');

  CreateBlock make({
    BlockBehavior? behavior,
    List<PlacementRule> placement = const [],
    List<ShapeRule> shapeRules = const [],
    BlockShape? collisionShape,
    BlockShape? selectionShape,
    String? blockEntityType,
  }) => manifestBlock(
    m.key,
    behavior: behavior,
    placement: placement,
    shapeRules: shapeRules,
    collisionShape: collisionShape,
    selectionShape: selectionShape,
    drops: drops,
    blockEntityType: blockEntityType,
  );

  switch (role) {
    case DecorationRole.stairs:
      return make(
        behavior: stairBehavior(rt, weathering: weathering, copper: copper),
        placement: placementRulesOf(role),
        shapeRules: stairShapeRules(),
      );
    case DecorationRole.slab:
      return make(
        behavior: slabBehavior(rt, weathering: weathering),
        placement: placementRulesOf(role),
        shapeRules: slabShapeRules(),
      );
    case DecorationRole.wall:
      return make(
        behavior: wallBehavior(rt),
        placement: placementRulesOf(role),
        collisionShape: BlockShape.boxes(wallShape(true, const {}, collision: true)),
        selectionShape: BlockShape.boxes(wallShape(true, const {})),
      );
    case DecorationRole.pane:
      return make(
        behavior: paneBehavior(rt),
        placement: placementRulesOf(role),
        shapeRules: paneShapeRules(),
        collisionShape: BlockShape.boxes(crossShape(const {})),
        selectionShape: BlockShape.boxes(crossShape(const {})),
      );
    case DecorationRole.pillar:
      return make(behavior: pillarBehavior(rt), placement: const [PlacementRule.clickedAxis('axis')]);
    case DecorationRole.copperFull:
      return make(behavior: _copperFullBehavior(rt, weathering));
    case DecorationRole.plain:
      return make(behavior: copper ? _copperFullBehavior(rt, false) : null);
    case DecorationRole.girder:
      return make(
        behavior: girderBehavior(rt),
        placement: placementRulesOf(role),
        shapeRules: girderShapeRules(),
        collisionShape: girderPoleShape(),
        selectionShape: girderPoleShape(),
      );
    case DecorationRole.encasedGirder:
      return make(
        behavior: girderEncasedBehavior(rt),
        shapeRules: girderEncasedShapeRules(),
        // The kinetic block entity of the encased shaft belongs to the kinetics module.
        blockEntityType: 'create:encased_shaft',
      );
    case DecorationRole.copycatPanel:
      return make(
        behavior: copycatBehavior(rt, panel: true),
        placement: placementRulesOf(role),
        shapeRules: copycatPanelShapeRules(),
        blockEntityType: CopycatBlockEntity.type,
      );
    case DecorationRole.copycatStep:
      return make(
        behavior: copycatBehavior(rt, panel: false),
        placement: placementRulesOf(role),
        shapeRules: copycatStepShapeRules(),
        blockEntityType: CopycatBlockEntity.type,
      );
    case DecorationRole.placard:
      return make(
        behavior: placardBehavior(rt),
        placement: placementRulesOf(role),
        shapeRules: placardShapeRules(),
        blockEntityType: PlacardBlockEntity.type,
      );
    case DecorationRole.whistle:
      return make(
        behavior: whistleBehavior(rt),
        shapeRules: whistleShapeRules(),
        blockEntityType: WhistleBlockEntity.type,
      );
    case DecorationRole.whistleExtension:
      return make(behavior: whistleExtenderBehavior(rt), shapeRules: whistleExtenderShapeRules());
    case DecorationRole.slidingDoor:
      return make(
        behavior: slidingDoorBehavior(rt),
        placement: placementRulesOf(role),
        shapeRules: slidingDoorShapeRules(folds: foldingDoorKeysContain(m.key)),
      );
    case DecorationRole.trapdoor:
      return make(
        behavior: trapdoorBehavior(rt),
        placement: placementRulesOf(role),
        shapeRules: trapdoorShapeRules(),
      );
    case DecorationRole.ladder:
      return make(
        behavior: ladderBehavior(rt),
        placement: placementRulesOf(role),
        shapeRules: ladderShapeRules(),
      );
    case DecorationRole.scaffolding:
      return make(
        behavior: scaffoldingBehavior(rt),
        placement: placementRulesOf(role),
        shapeRules: scaffoldingShapeRules(),
      );
    case DecorationRole.cardboard:
      return make(behavior: cardboardBehavior(rt));
    case DecorationRole.casing:
    case DecorationRole.bracket:
    case DecorationRole.copycatBars:
    case DecorationRole.copycatBase:
      return make();
  }
}

bool foldingDoorKeysContain(String key) => const {'framed_glass_door'}.contains(key);

/// Copper blocks that are not stairs or slabs: weathering (unwaxed) and honeycomb / axe use.
BlockBehavior _copperFullBehavior(DecorationRuntime rt, bool weathering) => BlockBehavior(
  onRandomTick: weathering ? (server, e) => copperRandomTick(rt, e) : null,
  onUseWithItem: (server, e) async => (await copperInteraction(rt, e)) ?? BlockUseResult.tryEmptyHand,
);
