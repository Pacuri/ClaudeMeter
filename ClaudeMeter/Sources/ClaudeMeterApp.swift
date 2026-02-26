import SwiftUI
import AppKit

@main
struct ClaudeMeterApp: App {
    @StateObject private var viewModel = ClaudeUsageViewModel()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(viewModel: viewModel, settings: settings)
                .frame(width: 320, height: 500)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @ObservedObject var viewModel: ClaudeUsageViewModel

    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: GaugeRenderer.render(
                percent: viewModel.usage?.sessionPercentUsed ?? 0,
                size: 16
            ))
            if let usage = viewModel.usage {
                Text("\(usage.sessionPercentUsed)%")
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Gauge Renderer (draws a live arc gauge for the menu bar)

enum GaugeRenderer {

    /// Renders a tiny gauge icon as an NSImage (template-mode for menu bar)
    static func render(percent: Int, size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = (min(rect.width, rect.height) / 2) - 1.5
            let lineWidth: CGFloat = 2.0

            // Gauge arc spans from 225 degrees (bottom-left) to -45 degrees (bottom-right)
            // That's a 270-degree sweep, like a real gauge
            let startAngle: CGFloat = 225
            let endAngle: CGFloat = -45
            let totalSweep: CGFloat = 270

            // Background track (full arc)
            let trackPath = NSBezierPath()
            trackPath.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: true
            )
            trackPath.lineWidth = lineWidth
            trackPath.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.25).setStroke()
            trackPath.stroke()

            // Filled arc (usage amount)
            if percent > 0 {
                let fillAngle = startAngle - (totalSweep * CGFloat(min(percent, 100)) / 100)
                let fillPath = NSBezierPath()
                fillPath.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: fillAngle,
                    clockwise: true
                )
                fillPath.lineWidth = lineWidth
                fillPath.lineCapStyle = .round
                NSColor.white.setStroke()
                fillPath.stroke()
            }

            // Needle dot at current position
            if percent > 0 && percent < 100 {
                let needleAngle = startAngle - (totalSweep * CGFloat(min(percent, 100)) / 100)
                let radians = needleAngle * .pi / 180
                let dotX = center.x + radius * cos(radians)
                let dotY = center.y + radius * sin(radians)
                let dotSize: CGFloat = 3.0
                let dotRect = NSRect(
                    x: dotX - dotSize / 2,
                    y: dotY - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                let dotPath = NSBezierPath(ovalIn: dotRect)
                NSColor.white.setFill()
                dotPath.fill()
            }

            return true
        }

        img.isTemplate = true  // Adapts to light/dark menu bar automatically
        return img
    }
}
