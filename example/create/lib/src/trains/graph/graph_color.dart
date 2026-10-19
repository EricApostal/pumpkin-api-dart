// The graph colour (`Color.rainbowColor(new Random(seed).nextInt())`), pure. The colour is only
// shown by the debug overlay but it is saved, so it is computed exactly like Java does.

/// The first `nextInt()` of `new java.util.Random(seed)`.
int javaRandomNextInt(int seed) {
  const mask = (1 << 48) - 1;
  var s = (seed ^ 0x5DEECE66D) & mask;
  s = (s * 0x5DEECE66D + 0xB) & mask;
  return (s >> 16).toSigned(32);
}

int _colorInPhase(int phase, int progress) {
  phase = phase % 6;
  if (phase <= 1) return 0;
  if (phase == 2) return progress;
  if (phase <= 4) return 255;
  return 255 - progress;
}

/// `Color.rainbowColor(timeStep).getRGB()`: an opaque ARGB value as a signed 32 bit int.
int rainbowColor(int timeStep) {
  final localTimeStep = timeStep.abs() % 1536;
  final timeStepInPhase = localTimeStep % 256;
  final phaseBlue = localTimeStep ~/ 256;
  final red = _colorInPhase(phaseBlue + 4, timeStepInPhase);
  final green = _colorInPhase(phaseBlue + 2, timeStepInPhase);
  final blue = _colorInPhase(phaseBlue, timeStepInPhase);
  return ((0xff << 24) | (red << 16) | (green << 8) | blue).toSigned(32);
}
