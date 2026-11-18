import SwiftUI
import FitlingCore

/// The day as a De Stijl composition: the kcal field on top, and below it protein, carbs and fat
/// as primary fields whose widths follow their share of the energy.
struct TargetsComposition: View {
    let targets: NutritionTargets
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: Rule.width) {
            kcalField
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Rule.width) { macroFields }
            } else {
                ProportionalRow(weights: macroEnergy, spacing: Rule.width) { macroFields }
            }
        }
        .padding(Rule.width)
        .background(Color.ink)
    }

    private var macroEnergy: [Double] {
        [Double(targets.proteinG) * 4, Double(targets.carbsG) * 4, Double(targets.fatG) * 9]
    }

    private var kcalField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("targets.kcal.label")
                .font(.subheadline)
            Text(Measurement(value: Double(targets.kcal), unit: UnitEnergy.kilocalories), format: .measurement(width: .abbreviated, usage: .food))
                .font(.largeTitle.weight(.heavy))
                .monospacedDigit()
        }
        .foregroundStyle(Color.ink)
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.paper)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var macroFields: some View {
        macroField("targets.protein", grams: targets.proteinG, fill: .protein, text: .white)
        macroField("targets.carbs", grams: targets.carbsG, fill: .carbs, text: .onCarbs)
        macroField("targets.fat", grams: targets.fatG, fill: .fat, text: .white)
    }

    private func macroField(_ key: LocalizedStringKey, grams: Int, fill: Color, text: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(key)
                .font(.footnote.weight(.semibold))
            Text(Measurement(value: Double(grams), unit: UnitMass.grams), format: .measurement(width: .abbreviated, usage: .asProvided))
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(text)
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .bottomLeading)
        .background(fill)
        .accessibilityElement(children: .combine)
    }
}

/// Lays children out side by side with widths proportional to `weights`. Every field keeps at
/// least `minimumShare` of the row so its label stays readable; the numbers carry the exact split.
struct ProportionalRow: Layout {
    let weights: [Double]
    let spacing: CGFloat
    var minimumShare: Double = 0.2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let widths = columnWidths(total: width, count: subviews.count)
        let height = zip(subviews, widths)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, columnWidths(total: bounds.width, count: subviews.count)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func columnWidths(total: CGFloat, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let available = max(0, total - spacing * CGFloat(count - 1))
        let sum = weights.prefix(count).reduce(0, +)
        guard sum > 0, weights.count >= count else {
            return Array(repeating: available / CGFloat(count), count: count)
        }
        let floored = weights.prefix(count).map { max($0 / sum, minimumShare) }
        let flooredSum = floored.reduce(0, +)
        return floored.map { available * CGFloat($0 / flooredSum) }
    }
}
