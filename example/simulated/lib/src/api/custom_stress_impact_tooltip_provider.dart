// `dev.simulated_team.simulated.api.CustomStressImpactTooltipProvider`: a block
// that draws its own stress bar instead of the generic one (propellers, sails).
//
// Pure: no host imports.

/// Java: `dev.simulated_team.simulated.api.CustomStressImpactTooltipProvider`
abstract interface class CustomStressImpactTooltipProvider {
  /// The translation key of the tooltip's description.
  String get customImpactLangKey;

  /// How many bar segments the tooltip has.
  int get barLength;

  /// How many bar segments are filled.
  int get filledBarLength;
}
