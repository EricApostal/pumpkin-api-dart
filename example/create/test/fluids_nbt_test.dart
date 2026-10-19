// Pure NBT round-trip tests for the fluid stack, tank and tank-segment forms the block entities
// write (`TransferUtil.saveFluid`, `CreateFluidTank.writeToNBT`,
// `SmartFluidTankBehaviour.TankSegment.writeNBT`). These helpers do not touch the host, so they
// run on the VM.
import 'package:create/src/core/nbt.dart';
import 'package:create/src/fluids/fluid_stack.dart';
import 'package:create/src/fluids/nbt_util.dart';
import 'package:create/src/fluids/potion_data.dart';
import 'package:test/test.dart';

void main() {
  group('fluid stack NBT', () {
    test('a fluid round trips through {id, amount}', () {
      const stack = FStack(FluidKeys.water, 750);
      final value = FluidNbt.write(stack);
      expect(value.kind, NbtKind.compound);
      expect(value.asCompound['id']!.value, FluidKeys.water);
      expect(value.asCompound['amount']!.value, 750);

      final back = FluidNbt.read(value);
      expect(back.fluid, FluidKeys.water);
      expect(back.amount, 750);
    });

    test('an empty fluid is an empty compound', () {
      final value = FluidNbt.write(FStack.empty);
      expect(value.kind, NbtKind.compound);
      expect(value.asCompound, isEmpty);
      expect(FluidNbt.read(value).isEmpty, isTrue);
    });

    test('potion components survive the round trip', () {
      final stack = const PotionFluidData(
        'minecraft:strength',
        bottle: BottleType.splash,
      ).toStack(250);
      final back = FluidNbt.read(FluidNbt.write(stack));
      expect(back.fluid, stack.fluid);
      expect(back.amount, 250);

      final decoded = PotionFluidData.decode(back.data);
      expect(decoded?.potion, 'minecraft:strength');
      expect(decoded?.bottle, BottleType.splash);
    });
  });

  group('CreateFluidTank NBT', () {
    test('the stack is nested under Fluid', () {
      const stack = FStack(FluidKeys.lava, 1000);
      final value = fluidTankNbt(stack);
      final compound = value.asCompound;
      final fluid = compound['Fluid']!;
      expect(fluid.kind, NbtKind.compound);
      expect(fluid.asCompound['id']!.value, FluidKeys.lava);
      expect(fluid.asCompound['amount']!.value, 1000);

      final back = readFluidTankNbt(value);
      expect(back.fluid, FluidKeys.lava);
      expect(back.amount, 1000);
    });

    test('an empty tank round trips', () {
      final value = fluidTankNbt(FStack.empty);
      // `CreateFluidTank.writeToNBT` omits `Fluid` for an empty tank.
      expect(value.asCompound, isEmpty);
      expect(readFluidTankNbt(value).isEmpty, isTrue);
    });
  });

  group('SmartFluidTankBehaviour segments', () {
    test('a segment has TankContent and Level', () {
      const stack = FStack(FluidKeys.water, 500);
      final value = tankSegmentNbt(stack, 1000);
      final segment = value.asCompound;
      expect(segment.keys, containsAll(['TankContent', 'Level']));

      final level = segment['Level']!.asCompound;
      expect(level['Value']!.value, .5);
      expect(level['Target']!.value, .5);
      expect(level['Speed']!.value, 0.0);

      final back = readTankSegmentNbt(value);
      expect(back.fluid, FluidKeys.water);
      expect(back.amount, 500);
    });

    test('an empty segment reads empty with a zero level', () {
      final value = tankSegmentNbt(FStack.empty, 1000);
      expect(readTankSegmentNbt(value).isEmpty, isTrue);
      expect(value.asCompound['Level']!.asCompound['Value']!.value, 0.0);
    });

    test('a list keeps the order and capacities', () {
      final value = tankSegmentListNbt(
        const [FStack(FluidKeys.water, 1000), FStack.empty],
        const [1000, 2000],
      );
      final values = value.value as List<NbtValue>;
      expect(values, hasLength(2));
      expect(readTankSegmentNbt(values[0]).amount, 1000);
      expect(readTankSegmentNbt(values[1]).isEmpty, isTrue);
      expect(values[1].asCompound['Level']!.asCompound['Value']!.value, 0.0);
    });
  });

  group('positions', () {
    test('BlockPos.CODEC is a three int array', () {
      final value = posToNbt((1, -2, 3));
      expect(value.kind, NbtKind.intArray);
      expect(posFromNbt(value), (1, -2, 3));
    });
  });
}
