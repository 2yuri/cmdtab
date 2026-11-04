import AppKit
import QuartzCore
import SwiftUI

/// Rain, snow or fireflies, drawn by Core Animation's particle emitter: the GPU moves every particle,
/// nothing runs here per frame. Clicks pass through.
final class EffectEmitterView: NSView {
    /// The island's wings are small and close; the screen is big and far.
    enum Scale { case island, screen }

    let scale: Scale
    private let emitter = CAEmitterLayer()
    private let splash = CAEmitterLayer()
    /// What the particles were made for; a new size alone only retimes them, so they keep falling
    /// while the island grows.
    private var builtFor: (kind: EffectKind, style: EffectStyle, flipped: Bool)?

    var kind: EffectKind? { didSet { if kind != oldValue { configure() } } }
    var style = EffectStyle() { didSet { if style != oldValue { configure() } } }
    /// How far above the bottom things land (the top of the Dock on a screen).
    var floor: CGFloat = 0 { didSet { if floor != oldValue { configure() } } }

    init(scale: Scale) {
        self.scale = scale
        super.init(frame: .zero)
        // A layer-hosting view: its layers are ours to arrange.
        layer = CALayer()
        wantsLayer = true
        for layer in [emitter, splash] {
            layer.birthRate = 0
            self.layer?.addSublayer(layer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        configure()
    }

    private func configure() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let bounds = self.bounds
        emitter.frame = bounds
        splash.frame = bounds
        emitter.contentsScale = window?.backingScaleFactor ?? 2
        guard let kind, bounds.width > 0, bounds.height > 0 else {
            emitter.birthRate = 0
            splash.birthRate = 0
            builtFor = nil
            return
        }
        // Inside SwiftUI the layers may be flipped; "down" is whichever way the screen's down is.
        let flipped = layer?.contentsAreFlipped() ?? false
        let geometry = EffectGeometry(bounds: bounds, floor: floor, flipped: flipped, tilt: CGFloat(style.angle) * .pi / 180)
        let recipe = EffectRecipe(kind: kind, scale: scale, style: style, geometry: geometry)

        emitter.emitterShape = recipe.shape
        emitter.emitterMode = recipe.mode
        emitter.emitterPosition = recipe.position
        emitter.emitterSize = recipe.size
        emitter.birthRate = 1
        let cell = recipe.cell
        let splashCell = recipe.splash
        if let built = builtFor, built.kind == kind, built.style == style, built.flipped == flipped {
            // Same particles, new size: retime the ones on the layer by name.
            emitter.setValue(cell.lifetime, forKeyPath: "emitterCells.particle.lifetime")
            emitter.setValue(cell.birthRate, forKeyPath: "emitterCells.particle.birthRate")
            if let splashCell { splash.setValue(splashCell.birthRate, forKeyPath: "emitterCells.splash.birthRate") }
        } else {
            // A cell already handed to the layer ignores changes: give it a new one.
            emitter.emitterCells = [cell]
            splash.emitterCells = splashCell.map { [$0] }
            builtFor = (kind, style, flipped)
        }
        if splashCell != nil {
            splash.emitterShape = .line
            splash.emitterPosition = CGPoint(x: bounds.midX, y: geometry.floorY)
            splash.emitterSize = CGSize(width: bounds.width, height: 0)
            splash.birthRate = 1
        } else {
            splash.birthRate = 0
        }
    }
}

/// How it falls, from the Effects tab. Each 0…1 setting is about as designed in the middle.
struct EffectStyle: Equatable {
    var amount = 0.5
    var size = 0.5
    var speed = 0.5
    var opacity = 0.5
    /// Degrees from straight down; positive slants to the right.
    var angle = 0.0
    /// The fireflies' glow, "#RRGGBB".
    var fireflyColor = EffectStyle.defaultFireflyColor

    static let defaultFireflyColor = "#D9F25A"
    /// The colours offered beside the custom one.
    static let fireflyColors = ["#D9F25A", "#FFB547", "#FFE9C7", "#8FE3FF", "#FF8FC8"]

    /// "#RRGGBB" to red, green and blue, 0…1.
    static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (Double(value >> 16 & 0xFF) / 255, Double(value >> 8 & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    static func hex(red: Double, green: Double, blue: Double) -> String {
        let byte = { (value: Double) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// 0…1 to a multiplier: `low` at 0, 1 in the middle, `high` at 1.
    static func factor(_ value: Double, low: Double, high: Double) -> Double {
        let value = min(max(value, 0), 1)
        return value < 0.5 ? low + (1 - low) * value * 2 : 1 + (high - 1) * (value - 0.5) * 2
    }

    var density: Double { Self.factor(amount, low: 0.15, high: 2) }
    var bigness: Double { Self.factor(size, low: 0.4, high: 2.2) }
    var pace: Double { Self.factor(speed, low: 0.35, high: 2) }
    var strength: Double { Self.factor(opacity, low: 0.25, high: 1.8) }
}

/// Where things start and land in the emitter's own coordinates.
struct EffectGeometry {
    let bounds: CGRect
    let floor: CGFloat
    let flipped: Bool

    init(bounds: CGRect, floor: CGFloat, flipped: Bool, tilt: CGFloat = 0) {
        self.bounds = bounds
        self.floor = floor
        self.flipped = flipped
        self.tilt = tilt
    }

    /// −1 is down on screen when y grows upwards, +1 when the layers are flipped.
    var down: CGFloat { flipped ? 1 : -1 }
    var topY: CGFloat { flipped ? bounds.minY : bounds.maxY }
    var floorY: CGFloat { flipped ? bounds.maxY - floor : bounds.minY + floor }
    /// From the top to where things land.
    var fall: CGFloat { max(bounds.height - floor, 1) }
    /// The emitter's angle for "straight down": its angle 0 points to −y, so down on screen when y
    /// grows upwards.
    var downAngle: CGFloat { flipped ? .pi : 0 }
    var upAngle: CGFloat { flipped ? 0 : .pi }
    /// Radians from straight down; positive slants to the right on screen.
    var tilt: CGFloat = 0
    /// The emitter's angle for falling with the slant: its angles turn the other way when flipped.
    var fallAngle: CGFloat { flipped ? .pi - tilt : tilt }
    /// How far sideways things drift on their way down.
    var drift: CGFloat { fall * tan(tilt) }
}

/// The particles for one kind at one scale.
@MainActor
struct EffectRecipe {
    let kind: EffectKind
    let scale: EffectEmitterView.Scale
    let style: EffectStyle
    let geometry: EffectGeometry

    private var density: Float { Float(style.density) }
    private var onScreen: Bool { scale == .screen }

    var shape: CAEmitterLayerEmitterShape { kind == .fireflies ? .rectangle : .line }
    var mode: CAEmitterLayerEmitterMode { kind == .fireflies ? .surface : .outline }

    var position: CGPoint {
        let bounds = geometry.bounds
        switch kind {
        case .fireflies:
            // The lower part of the screen, or the whole wing.
            let height = onScreen ? geometry.fall * 0.6 : bounds.height
            let y = geometry.flipped ? geometry.floorY - height / 2 : geometry.floorY + height / 2
            return CGPoint(x: bounds.midX, y: y)
        case .rain, .snow:
            // Just above the top, so nothing pops in, and upwind by the drift so a slant still covers
            // the whole width.
            return CGPoint(x: bounds.midX - geometry.drift / 2, y: geometry.topY - geometry.down * (onScreen ? 20 : 4))
        }
    }

    var size: CGSize {
        let bounds = geometry.bounds
        switch kind {
        case .fireflies: return CGSize(width: bounds.width, height: onScreen ? geometry.fall * 0.6 : bounds.height)
        case .rain, .snow: return CGSize(width: bounds.width * (onScreen ? 1.1 : 1) + abs(geometry.drift), height: 0)
        }
    }

    var cell: CAEmitterCell {
        let cell = CAEmitterCell()
        cell.name = "particle"
        apply(to: cell)
        return cell
    }

    func apply(to cell: CAEmitterCell) {
        let width = Float(geometry.bounds.width)
        cell.contentsScale = 2
        cell.emissionLongitude = kind == .fireflies ? geometry.downAngle : geometry.fallAngle
        // Slanted, things travel further to reach the floor.
        let slant = max(cos(geometry.tilt), 0.3)
        switch kind {
        case .rain:
            let speed: CGFloat = onScreen ? 1100 : 150
            cell.contents = EffectImages.drop(tilt: geometry.tilt, flipped: geometry.flipped)
            cell.color = CGColor(red: 0.78, green: 0.86, blue: 1, alpha: onScreen ? 0.55 : 0.7)
            cell.velocity = speed
            cell.velocityRange = speed * 0.15
            cell.emissionRange = 0
            cell.lifetime = Float((geometry.fall + (onScreen ? 20 : 4)) / (speed * slant))
            cell.scale = onScreen ? 1 : 0.4
            cell.scaleRange = onScreen ? 0.35 : 0.1
            // About 120 drops a second across a 1500-point screen at the middle setting.
            cell.birthRate = (onScreen ? width * 0.08 : width * 0.35) * density
        case .snow:
            let speed: CGFloat = onScreen ? 70 : 14
            cell.contents = EffectImages.flake
            cell.color = CGColor(gray: 1, alpha: 0.9)
            cell.alphaRange = 0.3
            cell.velocity = speed
            cell.velocityRange = speed * 0.4
            cell.emissionRange = 0.35
            cell.lifetime = Float((geometry.fall + (onScreen ? 20 : 4)) / (speed * 0.6 * slant))
            cell.scale = onScreen ? 0.7 : 0.3
            cell.scaleRange = onScreen ? 0.4 : 0.12
            cell.spinRange = 1
            cell.birthRate = (onScreen ? width * 0.02 : width * 0.08) * density
        case .fireflies:
            cell.contents = EffectImages.glow
            let glow = EffectStyle.components(style.fireflyColor) ?? EffectStyle.components(EffectStyle.defaultFireflyColor)!
            cell.color = CGColor(red: glow.red, green: glow.green, blue: glow.blue, alpha: 0.95)
            cell.alphaSpeed = -0.22
            cell.velocity = onScreen ? 10 : 3
            cell.velocityRange = onScreen ? 8 : 2
            cell.emissionRange = .pi * 2
            cell.yAcceleration = onScreen ? -geometry.down * 2 : 0
            cell.lifetime = onScreen ? 5 : 3
            cell.lifetimeRange = 1.5
            cell.scale = onScreen ? 0.6 : 0.3
            cell.scaleRange = onScreen ? 0.3 : 0.1
            cell.birthRate = (onScreen ? width * 0.002 : width * 0.02) * density
        }
        // Faster or slower: things cover the same ground in less or more time.
        let pace = CGFloat(style.pace)
        cell.velocity *= pace
        cell.velocityRange *= pace
        if kind != .fireflies { cell.lifetime /= Float(pace) }
        cell.color = Self.strengthened(cell.color, by: style.strength)
        cell.scale *= CGFloat(style.bigness)
        cell.scaleRange *= CGFloat(style.bigness)
    }

    /// The colour with its alpha scaled, never past opaque.
    nonisolated static func strengthened(_ color: CGColor?, by strength: Double) -> CGColor? {
        guard let color else { return nil }
        return color.copy(alpha: min(color.alpha * strength, 1))
    }

    /// Rain splashes where it lands.
    var splash: CAEmitterCell? {
        guard kind == .rain else { return nil }
        let cell = CAEmitterCell()
        cell.name = "splash"
        cell.contents = EffectImages.dot
        cell.contentsScale = 2
        cell.color = Self.strengthened(CGColor(red: 0.78, green: 0.86, blue: 1, alpha: 0.6), by: style.strength)
        cell.alphaSpeed = onScreen ? -2.4 : -4
        cell.emissionLongitude = geometry.upAngle
        cell.emissionRange = .pi / 2.6
        cell.velocity = onScreen ? 70 : 14
        cell.velocityRange = onScreen ? 35 : 6
        cell.yAcceleration = geometry.down * (onScreen ? 420 : 90)
        cell.lifetime = onScreen ? 0.4 : 0.25
        cell.scale = onScreen ? 0.5 : 0.25
        cell.scaleRange = 0.15
        let width = Float(geometry.bounds.width)
        cell.birthRate = (onScreen ? width * 0.12 : width * 0.25) * density
        return cell
    }
}

/// The particle pictures, drawn once.
@MainActor
enum EffectImages {
    private static var drops: [Int: CGImage] = [:]

    /// A thin streak along the way it falls, faint at both ends. Contents of a flipped layer show
    /// upside down, so there it's drawn the other way round.
    static func drop(tilt: CGFloat, flipped: Bool) -> CGImage? {
        let degrees = Int((tilt * 180 / .pi).rounded())
        let key = flipped ? -degrees : degrees
        if let cached = drops[key] { return cached }
        let length: CGFloat = 34
        let slant = CGFloat(key) * .pi / 180
        let run = length * sin(slant)
        let rise = length * cos(slant)
        let image = draw(width: Int(abs(run).rounded(.up)) + 4, height: Int(rise.rounded(.up)) + 2) { context, size in
            // Top of the streak (y up) at one side, its foot downwind.
            let top = CGPoint(x: run >= 0 ? 2 : size.width - 2, y: size.height - 1)
            let foot = CGPoint(x: top.x + run, y: top.y - rise)
            let middle = CGPoint(x: top.x + run * 0.55, y: top.y - rise * 0.55)
            context.setLineWidth(2.4)
            context.setLineCap(.round)
            context.move(to: top)
            context.addLine(to: foot)
            context.replacePathWithStrokedPath()
            context.clip()
            let colors = [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 1)] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            context.drawLinearGradient(gradient, start: top, end: middle, options: [])
            context.drawLinearGradient(gradient, start: foot, end: middle, options: [])
        }
        drops[key] = image
        return image
    }

    static let flake: CGImage? = radial(diameter: 14, core: 0.45)
    static let glow: CGImage? = radial(diameter: 24, core: 0.18)
    static let dot: CGImage? = radial(diameter: 6, core: 0.6)

    private static func radial(diameter: Int, core: CGFloat) -> CGImage? {
        draw(width: diameter, height: diameter) { context, size in
            let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, core, 1]) else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width / 2, options: [])
        }
    }

    private static func draw(width: Int, height: Int, _ body: (CGContext, CGSize) -> Void) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        body(context, CGSize(width: width, height: height))
        return context.makeImage()
    }
}

/// The effect in the island's wings.
struct IslandEffectView: NSViewRepresentable {
    let kind: EffectKind?
    let style: EffectStyle
    /// The open island is big enough for the screen's particles.
    var scale: EffectEmitterView.Scale = .island

    func makeNSView(context: Context) -> EffectEmitterView {
        EffectEmitterView(scale: scale)
    }

    func updateNSView(_ view: EffectEmitterView, context: Context) {
        view.kind = kind
        view.style = style
    }
}

/// The whole screen, under the island and over every window, never taking a click.
@MainActor
final class ScreenEffectPanel {
    private let panel: NSPanel
    private let view = EffectEmitterView(scale: .screen)

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = view
    }

    func show(_ kind: EffectKind, style: EffectStyle, on screen: NSScreen) {
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
        // Things land on the Dock when it's at the bottom.
        view.floor = max(screen.visibleFrame.minY - screen.frame.minY, 0)
        view.style = style
        view.kind = kind
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        view.kind = nil
        panel.orderOut(nil)
    }
}
