import SwiftUI

/// Narrow bars with dotted gridlines at round values, labelled on the right,
/// for charts with too many bars to print a value on each (12 months).
/// The bars scale to the top gridline; labels go under the bars.
struct AxisBarChart: View {
    var values: [Double]
    var labels: [String]
    /// From `AxisBarChart.ticks`; empty draws flat placeholder bars.
    var ticks: [Double]
    var tickLabel: (Double) -> String
    /// Height of the bar area; the top gridline sits here.
    var plotHeight: CGFloat
    var spacing: CGFloat
    /// Width kept on the right for the gridline labels.
    var axisWidth: CGFloat = 44

    private let minBar: CGFloat = 3

    var body: some View {
        let top = ticks.last ?? 0
        VStack(spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                ForEach(ticks, id: \.self) { tick in
                    HStack(spacing: 6) {
                        DottedLine()
                            .stroke(.stroke, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .frame(height: 1)
                        Text(tickLabel(tick))
                            .font(.number(.caption2, weight: .regular))
                            .foregroundStyle(.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: axisWidth, alignment: .leading)
                    }
                    // Centre each line on its value.
                    .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
                    .offset(y: -plotHeight * CGFloat(tick / top))
                }
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(value > 0 ? AnyShapeStyle(.dataBlue) : AnyShapeStyle(.surfaceRaised))
                            .frame(height: top > 0 ? max(minBar, plotHeight * CGFloat(value / top)) : minBar)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.trailing, axisWidth + 6)
            }
            // Room above the top gridline for half its label.
            .frame(height: plotHeight + 8, alignment: .bottom)
            HStack(spacing: spacing) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.label)
            .foregroundStyle(.textSecondary)
            .padding(.trailing, axisWidth + 6)
        }
    }

    /// Round values from zero to at or just above `peak`, in at most three
    /// equal steps of 1, 2 or 5 times a power of ten, never smaller than
    /// `minStep`. Empty when `peak` is zero.
    static func ticks(peak: Double, minStep: Double) -> [Double] {
        guard peak > 0 else { return [] }
        let rough = max(minStep, peak / 3)
        let magnitude = pow(10, floor(log10(rough)))
        let step = [1.0, 2, 5, 10].map { $0 * magnitude }.first { $0 >= rough } ?? 10 * magnitude
        let count = max(1, Int((peak / step).rounded(.up)))
        return (0...count).map { Double($0) * step }
    }

    private struct DottedLine: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}
