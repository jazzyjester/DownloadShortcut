import SwiftUI

/// The content hosted inside the `NSStatusItem`: an idle glyph, a circular progress
/// ring with a percentage while downloading, or a checkmark flourish once finished.
public struct StatusBarIconView: View {
  public let phase: StatusBarFeature.State.Phase

  public init(phase: StatusBarFeature.State.Phase) {
    self.phase = phase
  }

  public var body: some View {
    switch phase {
    case .idle:
      Image(systemName: "arrow.down.circle")
        .font(.system(size: 16, weight: .medium))

    case let .downloading(activeCount, overallFraction):
      HStack(spacing: 3) {
        ProgressRing(fractionCompleted: overallFraction)
          .frame(width: 15, height: 15)
        Text("\(Int((overallFraction * 100).rounded()))%")
          .font(.system(size: 11, weight: .semibold).monospacedDigit())
        if activeCount > 1 {
          Text("(\(activeCount))")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
      }

    case .justFinished:
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.green)
    }
  }
}

/// A simple ring drawn with `Circle().trim`, avoiding any AppKit/Core Graphics
/// drawing code so it's testable/previewable like any other SwiftUI view.
struct ProgressRing: View {
  let fractionCompleted: Double

  var body: some View {
    ZStack {
      Circle()
        .stroke(.tertiary, lineWidth: 2)
      Circle()
        .trim(from: 0, to: max(0.02, min(1, fractionCompleted)))
        .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
  }
}

// See QuickAddView.swift for why this uses `PreviewProvider` instead of `#Preview`.
struct StatusBarIconView_Previews: PreviewProvider {
  static var previews: some View {
    VStack(spacing: 12) {
      StatusBarIconView(phase: .idle)
      StatusBarIconView(phase: .downloading(activeCount: 2, overallFraction: 0.42))
      StatusBarIconView(phase: .justFinished(fileName: "example.zip"))
    }
    .padding()
  }
}
