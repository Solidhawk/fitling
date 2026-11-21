import SwiftUI
import FitlingCore

/// The day's targets as one card: the energy target in heavy numerals, then a block per macro.
struct TargetsCard: View {
    let targets: NutritionTargets

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                NamePlate("targets.kcal.label", fill: Color.track, foreground: Color.ink, edge: nil)
                Text(Measurement(value: Double(targets.kcal), unit: UnitEnergy.kilocalories), format: .measurement(width: .abbreviated, usage: .asProvided))
                    .font(.largeTitle.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
            }
            .accessibilityElement(children: .combine)

            MacroBlocks(targets: targets)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.card)
                .shadow(color: Color.cardShadow, radius: 12, y: 4)
        }
    }
}
