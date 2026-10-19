import 'package:create/src/equipment/tools/copper_stages.dart';
import 'package:test/test.dart';

void main() {
  test('copper weathering stages', () {
    expect(CopperStages.previousOxidizedStage('minecraft:oxidized_copper'), 'minecraft:weathered_copper');
    expect(CopperStages.previousOxidizedStage('minecraft:weathered_cut_copper_stairs'), 'minecraft:exposed_cut_copper_stairs');
    expect(CopperStages.previousOxidizedStage('minecraft:exposed_copper'), 'minecraft:copper_block');
    expect(CopperStages.previousOxidizedStage('minecraft:exposed_cut_copper'), 'minecraft:cut_copper');
    expect(CopperStages.previousOxidizedStage('minecraft:copper_block'), isNull);
    expect(CopperStages.previousOxidizedStage('create:oxidized_x'), isNull);
  });

  test('unwaxing', () {
    expect(CopperStages.unwaxed('minecraft:waxed_copper_block'), 'minecraft:copper_block');
    expect(CopperStages.unwaxed('minecraft:waxed_oxidized_cut_copper'), 'minecraft:oxidized_cut_copper');
    expect(CopperStages.unwaxed('minecraft:copper_block'), isNull);
  });
}
