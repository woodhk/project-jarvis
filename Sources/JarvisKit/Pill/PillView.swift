import SwiftUI

@MainActor final class PillModel: ObservableObject {
    @Published var state: PillState = .hidden
    /// How long two choices wait for an answer; the bar under them empties over this time.
    var choiceSeconds: TimeInterval = 8
    /// How long the list of all sessions waits for a number.
    var listSeconds: TimeInterval = 20
    /// Changes each time choices are shown, so the bar starts full again.
    @Published var choiceShownAt = Date()
}

/// The small dark panel at the bottom of the screen. It only draws a `PillState`.
struct PillView: View {
    @ObservedObject var model: PillModel
    static let maxWidth: CGFloat = 440

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .hidden:
            EmptyView()
        case .listening:
            HStack(spacing: 10) {
                LevelBars()
                Text(PillCopy.listening).font(.system(size: 14, weight: .semibold))
            }
        case .hint(let text):
            Text(text).font(.system(size: 14, weight: .medium))
        case .working(let heard):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(heard ?? "…").font(.system(size: 14)).lineLimit(2)
            }
        case .opened(let heard, let title, let subtitle, let note):
            VStack(alignment: .leading, spacing: 4) {
                HeardLine(text: heard)
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                Text(note).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).padding(.top, 2)
            }
        case .choices(let heard, let options):
            VStack(alignment: .leading, spacing: 6) {
                HeardLine(text: heard)
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white.opacity(0.18)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                            Text(option.subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
                Text(options.count == 1 ? PillCopy.oneChoiceTip : PillCopy.choicesTip)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).padding(.top, 2)
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { DrainBar(seconds: model.choiceSeconds).id(model.choiceShownAt) }
        case .list(let options, let more, let listening):
            VStack(alignment: .leading, spacing: 6) {
                // The same height with and without the meter, so the list does not jump when fn goes down.
                HStack(spacing: 8) {
                    if listening { LevelBars() }
                    Text(listening ? PillCopy.listening : PillCopy.listTitle)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                }
                .frame(height: 18)
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    HStack(alignment: .center, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white.opacity(0.18)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(option.subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                        }
                    }
                }
                if more > 0 {
                    Text(PillCopy.moreNotShown(more)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                }
                Text(PillCopy.listTip).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).padding(.top, 2)
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { DrainBar(seconds: model.listSeconds).id(model.choiceShownAt) }
        case .nothing(let heard, let message):
            VStack(alignment: .leading, spacing: 4) {
                HeardLine(text: heard)
                Text(message).font(.system(size: 14, weight: .medium))
            }
        }
    }
}

private struct HeardLine: View {
    let text: String
    var body: some View {
        if !text.isEmpty {
            Text("“\(text)”").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
        }
    }
}

/// A moving meter that shows the microphone is live.
private struct LevelBars: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    let phase = sin(t * 7 + Double(i) * 1.3)
                    Capsule().fill(Color.red.opacity(0.9)).frame(width: 3, height: 6 + 10 * abs(phase))
                }
            }
            .frame(height: 18)
        }
    }
}

/// A thin bar that empties over the time the choices stay open. It is drawn over the bottom edge of the choices,
/// so it is exactly as wide as they are and does not change the pill's size.
private struct DrainBar: View {
    let seconds: TimeInterval
    @State private var remaining: CGFloat = 1

    var body: some View {
        Capsule().fill(Color.white.opacity(0.35))
            .frame(height: 2)
            .scaleEffect(x: remaining, y: 1, anchor: .leading)
            .onAppear {
                withAnimation(.linear(duration: seconds)) { remaining = 0 }
            }
    }
}
