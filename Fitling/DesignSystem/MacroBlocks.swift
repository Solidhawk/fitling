import SwiftUI
import FitlingCore

/// One macro as a block in its own colour: on the day it fills from the bottom as food is logged,
/// as a target it is full. Three of them stand side by side, like toy blocks, instead of the bars
/// every food app uses.
struct MacroBlock: View {
    enum Content {
        /// Eaten against the target, in grams.
        case progress(eaten: Double, target: Int)
        /// The target in grams and its share of the day's kcal.
        case target(grams: Int, share: Double)
    }

    let titleKey: LocalizedStringKey
    let content: Content
    let fill: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var fraction: Double {
        switch content {
        case let .progress(eaten, target): min(max(eaten / Double(max(target, 1)), 0), 1)
        case .target: 1
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // In a third of the width "Koolhydraten" shrinks a little rather than break mid-word;
            // stacked at the accessibility sizes it has the full width.
            Text(titleKey)
                .font(.subheadline.weight(.bold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: Spacing.s)
            switch content {
            case let .progress(eaten, target):
                Text(eaten.rounded(), format: .number)
                    .font(.title2.weight(.heavy))
                    .monospacedDigit()
                Text("day.macro.of \(target.formatted())")
                    .font(.footnote.weight(.semibold))
            case let .target(grams, share):
                Text(Measurement(value: Double(grams), unit: UnitMass.grams), format: .measurement(width: .abbreviated, usage: .asProvided))
                    .font(.title2.weight(.heavy))
                    .monospacedDigit()
                Text("targets.macro.share \(share.formatted(.percent.precision(.fractionLength(0))))")
                    .font(.footnote.weight(.semibold))
            }
        }
        .foregroundStyle(Color.onRibbon)
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: .infinity, alignment: .topLeading)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    // The empty part is a pale tint of the colour on white, in dark mode too: the ink
                    // lettering needs a light ground.
                    Rectangle().fill(Color.white)
                    Rectangle().fill(fill.opacity(0.35))
                    Rectangle()
                        .fill(fill)
                        .frame(height: proxy.size.height * fraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.ribbon, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Protein, carbs and fat as three blocks side by side; stacked at the accessibility sizes, where
/// three columns would leave a few letters per line.
struct MacroBlocks: View {
    let protein: MacroBlock.Content
    let carbs: MacroBlock.Content
    let fat: MacroBlock.Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Spacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.s))
        layout {
            MacroBlock(titleKey: "targets.protein", content: protein, fill: Color.protein)
            MacroBlock(titleKey: "targets.carbs", content: carbs, fill: Color.carbs)
            MacroBlock(titleKey: "targets.fat", content: fat, fill: Color.fat)
        }
        // Side by side the three blocks take the height of the tallest one.
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension MacroBlocks {
    /// The day's targets, each with its share of the kcal.
    init(targets: NutritionTargets) {
        let shares = NutritionEngine.kcalShares(of: targets)
        self.init(
            protein: .target(grams: targets.proteinG, share: shares.protein),
            carbs: .target(grams: targets.carbsG, share: shares.carbs),
            fat: .target(grams: targets.fatG, share: shares.fat)
        )
    }

    /// Eaten today against the targets.
    init(eaten totals: DayTotals, targets: NutritionTargets) {
        self.init(
            protein: .progress(eaten: totals.proteinG, target: targets.proteinG),
            carbs: .progress(eaten: totals.carbsG, target: targets.carbsG),
            fat: .progress(eaten: totals.fatG, target: targets.fatG)
        )
    }
}
