import SwiftUI
import FitlingCore

/// The day's targets as one card: the energy target in heavy numerals, then a ribbon per macro.
/// In phase 2 the ribbons fill up as the day is logged.
struct TargetsCard: View {
    let targets: NutritionTargets
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                NamePlate("targets.kcal.label", fill: Color.track, foreground: Color.ink)
                Text(Measurement(value: Double(targets.kcal), unit: UnitEnergy.kilocalories), format: .measurement(width: .abbreviated, usage: .food))
                    .font(.largeTitle.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
            }
            .accessibilityElement(children: .combine)

            ribbon("targets.protein", grams: targets.proteinG, fill: Color.protein)
            ribbon("targets.carbs", grams: targets.carbsG, fill: Color.carbs)
            ribbon("targets.fat", grams: targets.fatG, fill: Color.fat)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.card)
                .shadow(color: Color.cardShadow, radius: 12, y: 4)
        }
    }

    /// At accessibility sizes the grams move under the label instead of being squeezed beside it.
    private func ribbon(_ key: LocalizedStringKey, grams: Int, fill: Color) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.s))
        return layout {
            Text(key)
                .font(.subheadline.weight(.bold))
            if !stacked {
                Spacer(minLength: Spacing.s)
            }
            Text(Measurement(value: Double(grams), unit: UnitMass.grams), format: .measurement(width: .abbreviated, usage: .asProvided))
                .font(.title3.weight(.heavy))
                .monospacedDigit()
        }
        .foregroundStyle(Color.onRibbon)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, minHeight: Radius.ribbon * 2, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: Radius.ribbon, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
