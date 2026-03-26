import AppKit
import SwiftUI

struct SpectrumWaterfallView: NSViewRepresentable {
    var centerFrequencyHz: Double
    var spanHz: Double
    var spectrumBins: [Double]
    var palette: WaterfallPalette
    var resolutionMultiplier: Int
    var onTuneRequest: (Double) -> Void
    var onPanRequest: (Double) -> Void
    var onZoomRequest: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTuneRequest: onTuneRequest,
            onPanRequest: onPanRequest,
            onZoomRequest: onZoomRequest
        )
    }

    func makeNSView(context: Context) -> SpectrumWaterfallNSView {
        let view = SpectrumWaterfallNSView()
        view.onTuneRequest = context.coordinator.handleTuneRequest
        view.onPanRequest = context.coordinator.handlePanRequest
        view.onZoomRequest = context.coordinator.handleZoomRequest
        return view
    }

    func updateNSView(_ nsView: SpectrumWaterfallNSView, context: Context) {
        nsView.centerFrequencyHz = centerFrequencyHz
        nsView.spanHz = spanHz
        nsView.palette = palette
        nsView.resolutionMultiplier = resolutionMultiplier
        nsView.updateSpectrumBins(spectrumBins)
        context.coordinator.onTuneRequest = onTuneRequest
        context.coordinator.onPanRequest = onPanRequest
        context.coordinator.onZoomRequest = onZoomRequest
    }

    final class Coordinator: NSObject {
        var onTuneRequest: (Double) -> Void
        var onPanRequest: (Double) -> Void
        var onZoomRequest: (Double) -> Void

        init(
            onTuneRequest: @escaping (Double) -> Void,
            onPanRequest: @escaping (Double) -> Void,
            onZoomRequest: @escaping (Double) -> Void
        ) {
            self.onTuneRequest = onTuneRequest
            self.onPanRequest = onPanRequest
            self.onZoomRequest = onZoomRequest
        }

        func handleTuneRequest(_ frequencyHz: Double) {
            onTuneRequest(frequencyHz)
        }

        func handlePanRequest(_ deltaHz: Double) {
            onPanRequest(deltaHz)
        }

        func handleZoomRequest(_ factor: Double) {
            onZoomRequest(factor)
        }
    }
}

@MainActor
final class SpectrumWaterfallNSView: NSView {
    var centerFrequencyHz: Double = 14_200_000
    var spanHz: Double = 10_000_000
    var palette: WaterfallPalette = .classic
    var resolutionMultiplier: Int = 16
    var onTuneRequest: ((Double) -> Void)?
    var onPanRequest: ((Double) -> Void)?
    var onZoomRequest: ((Double) -> Void)?

    private let scaleHeight: CGFloat = 52
    private let separatorHeight: CGFloat = 1
    private var currentSpectrum: [CGFloat] = Array(repeating: 0.12, count: 2_048)
    private var waterfallRows: [[CGFloat]] = Array(repeating: Array(repeating: 0.12, count: 2_048), count: 120)
    private var dragOriginX: CGFloat?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override var acceptsFirstResponder: Bool { true }

    private var waterfallRect: NSRect {
        NSRect(
            x: 0,
            y: scaleHeight + separatorHeight,
            width: bounds.width,
            height: max(bounds.height - scaleHeight - separatorHeight, 0)
        )
    }

    private var scaleRect: NSRect {
        NSRect(x: 0, y: 0, width: bounds.width, height: scaleHeight)
    }

    func updateSpectrumBins(_ bins: [Double]) {
        guard !bins.isEmpty else {
            needsDisplay = true
            return
        }

        let baseSpectrum = bins.map { CGFloat(max(0, min(1, $0))) }
        let normalized = resampledSpectrum(from: baseSpectrum, multiplier: resolutionMultiplier)
        if normalized.count != currentSpectrum.count {
            currentSpectrum = normalized
            waterfallRows = Array(repeating: normalized, count: 120)
            needsDisplay = true
            return
        }

        let changed = zip(normalized, currentSpectrum).contains { abs($0 - $1) > 0.008 }
        currentSpectrum = normalized

        if changed {
            waterfallRows.insert(normalized, at: 0)
            if waterfallRows.count > 120 {
                waterfallRows.removeLast(waterfallRows.count - 120)
            }
        }

        needsDisplay = true
    }

    private func resampledSpectrum(from source: [CGFloat], multiplier: Int) -> [CGFloat] {
        guard source.count > 1 else { return source }

        let clampedMultiplier = min(max(multiplier, 8), 64)
        let targetCount = source.count * clampedMultiplier
        guard targetCount > source.count else { return source }

        return (0..<targetCount).map { index in
            let position = CGFloat(index) * CGFloat(source.count - 1) / CGFloat(targetCount - 1)
            let lowerIndex = Int(position.rounded(.down))
            let upperIndex = min(lowerIndex + 1, source.count - 1)
            let fraction = position - CGFloat(lowerIndex)
            return source[lowerIndex] + (source[upperIndex] - source[lowerIndex]) * fraction
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if scaleRect.contains(point) {
            dragOriginX = point.x
            return
        }

        onTuneRequest?(frequency(at: point.x))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOriginX else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = point.x - dragOriginX
        self.dragOriginX = point.x
        let deltaHz = Double(-delta / max(bounds.width, 1)) * spanHz
        onPanRequest?(deltaHz)
    }

    override func mouseUp(with event: NSEvent) {
        dragOriginX = nil
    }

    override func scrollWheel(with event: NSEvent) {
        let horizontalMagnitude = abs(event.scrollingDeltaX)
        let verticalMagnitude = abs(event.scrollingDeltaY)

        if verticalMagnitude > horizontalMagnitude {
            let factor = event.scrollingDeltaY > 0 ? 0.88 : 1.14
            onZoomRequest?(factor)
        } else if horizontalMagnitude > 0 {
            let deltaHz = Double(event.scrollingDeltaX / max(bounds.width, 1)) * spanHz * 0.45
            onPanRequest?(deltaHz)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.setFill()
        bounds.fill()

        drawWaterfall()
        drawSpectrum()
        drawScaleBar()
        drawFrequencyMarker()
    }

    private func drawWaterfall() {
        let rect = waterfallRect
        guard rect.width > 0, rect.height > 0 else { return }

        let rowHeight = max(2, rect.height / CGFloat(max(waterfallRows.count, 1)))
        for (rowIndex, row) in waterfallRows.enumerated() {
            let y = rect.maxY - CGFloat(rowIndex + 1) * rowHeight
            for (columnIndex, value) in row.enumerated() {
                let x = rect.minX + CGFloat(columnIndex) / CGFloat(row.count) * rect.width
                let cellWidth = rect.width / CGFloat(row.count)
                color(for: value).setFill()
                NSBezierPath(rect: NSRect(x: x, y: y, width: cellWidth + 1, height: rowHeight + 1)).fill()
            }
        }
    }

    private func drawSpectrum() {
        let rect = waterfallRect
        let overlayHeight = min(rect.height * 0.22, 90)
        let spectrumRect = NSRect(x: rect.minX, y: rect.maxY - overlayHeight, width: rect.width, height: overlayHeight)

        NSColor.black.withAlphaComponent(0.7).setFill()
        spectrumRect.fill()

        let path = NSBezierPath()
        for index in currentSpectrum.indices {
            let x = spectrumRect.minX + CGFloat(index) / CGFloat(max(currentSpectrum.count - 1, 1)) * spectrumRect.width
            let y = spectrumRect.minY + currentSpectrum[index] * spectrumRect.height * 0.95
            if index == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        NSColor.white.setStroke()
        path.lineWidth = 1.8
        path.stroke()
    }

    private func drawScaleBar() {
        let rect = scaleRect
        NSColor.black.setFill()
        rect.fill()

        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY, width: rect.width, height: separatorHeight)).fill()

        let leftFrequency = centerFrequencyHz - spanHz / 2
        let rightFrequency = centerFrequencyHz + spanHz / 2

        let minorStep = niceStep(for: spanHz / 24)
        if minorStep > 0 {
            var tick = floor(leftFrequency / minorStep) * minorStep
            while tick <= rightFrequency {
                let x = xPosition(for: tick)
                if x >= rect.minX && x <= rect.maxX {
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: x, y: rect.maxY - 10))
                    path.line(to: NSPoint(x: x, y: rect.maxY - 24))
                    NSColor.white.setStroke()
                    path.lineWidth = 1
                    path.stroke()
                }
                tick += minorStep
            }
        }

        let quantum = niceStep(for: spanHz / 9)
        for index in 0..<10 {
            let fraction = CGFloat(index) / 9
            let x = rect.minX + fraction * rect.width
            let target = leftFrequency + (spanHz * Double(fraction))
            let quantized = (target / quantum).rounded() * quantum

            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: x, y: rect.maxY - 4))
            tick.line(to: NSPoint(x: x, y: rect.minY + 18))
            NSColor.systemRed.setStroke()
            tick.lineWidth = 1.2
            tick.stroke()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let label = formattedScaleFrequency(quantized) as NSString
            let labelSize = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(
                    x: min(max(rect.minX + 4, x - labelSize.width / 2), rect.maxX - labelSize.width - 4),
                    y: rect.minY + 4
                ),
                withAttributes: attributes
            )
        }
    }

    private func drawFrequencyMarker() {
        let rect = waterfallRect
        let x = xPosition(for: centerFrequencyHz)
        let marker = NSBezierPath()
        marker.move(to: NSPoint(x: x, y: rect.minY))
        marker.line(to: NSPoint(x: x, y: rect.maxY))
        NSColor.systemRed.setStroke()
        marker.lineWidth = 1.6
        marker.stroke()
    }

    private func xPosition(for frequencyHz: Double) -> CGFloat {
        let leftFrequency = centerFrequencyHz - spanHz / 2
        let ratio = (frequencyHz - leftFrequency) / max(spanHz, 1)
        return CGFloat(ratio) * bounds.width
    }

    private func frequency(at xPosition: CGFloat) -> Double {
        let leftFrequency = centerFrequencyHz - spanHz / 2
        let ratio = max(0, min(1, xPosition / max(bounds.width, 1)))
        return leftFrequency + spanHz * Double(ratio)
    }

    private func niceStep(for rawStep: Double) -> Double {
        guard rawStep > 0 else { return 1 }
        let exponent = floor(log10(rawStep))
        let magnitude = pow(10, exponent)
        let normalized = rawStep / magnitude
        let niceNormalized: Double
        switch normalized {
        case ..<1.5:
            niceNormalized = 1
        case ..<3.5:
            niceNormalized = 2
        case ..<7.5:
            niceNormalized = 5
        default:
            niceNormalized = 10
        }
        return niceNormalized * magnitude
    }

    private func formattedScaleFrequency(_ frequencyHz: Double) -> String {
        if spanHz >= 1_000_000 {
            return String(format: "%.3f", frequencyHz / 1_000_000)
        }
        if spanHz >= 10_000 {
            return String(format: "%.0f k", frequencyHz / 1_000)
        }
        if spanHz >= 1_000 {
            return String(format: "%.1f k", frequencyHz / 1_000)
        }
        return String(format: "%.0f", frequencyHz)
    }

    private func color(for value: CGFloat) -> NSColor {
        let clamped = max(0, min(1, value))
        let stops: [NSColor]
        switch palette {
        case .classic:
            stops = [.black, .systemBlue, .systemGreen, .systemYellow, .systemRed, .white]
        case .ice:
            stops = [.black, .systemIndigo, .systemTeal, .white]
        case .ember:
            stops = [.black, .systemPurple, .systemOrange, .systemRed, .white]
        }

        let scaled = clamped * CGFloat(stops.count - 1)
        let lowerIndex = min(Int(floor(scaled)), stops.count - 1)
        let upperIndex = min(lowerIndex + 1, stops.count - 1)
        let fraction = scaled - CGFloat(lowerIndex)

        return interpolate(from: stops[lowerIndex], to: stops[upperIndex], fraction: fraction)
    }

    private func interpolate(from: NSColor, to: NSColor, fraction: CGFloat) -> NSColor {
        let fromRGB = from.usingColorSpace(.deviceRGB) ?? from
        let toRGB = to.usingColorSpace(.deviceRGB) ?? to

        let red = fromRGB.redComponent + (toRGB.redComponent - fromRGB.redComponent) * fraction
        let green = fromRGB.greenComponent + (toRGB.greenComponent - fromRGB.greenComponent) * fraction
        let blue = fromRGB.blueComponent + (toRGB.blueComponent - fromRGB.blueComponent) * fraction

        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}
