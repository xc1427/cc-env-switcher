import AppKit

private enum Palette {
    static let clay = NSColor(srgbRed: 206 / 255, green: 109 / 255, blue: 77 / 255, alpha: 1)
    static let clayDark = NSColor(srgbRed: 135 / 255, green: 85 / 255, blue: 64 / 255, alpha: 1)
    static let clayLight = NSColor(srgbRed: 219 / 255, green: 137 / 255, blue: 105 / 255, alpha: 1)
    static let parchment = NSColor(srgbRed: 251 / 255, green: 246 / 255, blue: 241 / 255, alpha: 1)
    static let parchmentDark = NSColor(srgbRed: 237 / 255, green: 216 / 255, blue: 202 / 255, alpha: 1)
    static let warmWhite = NSColor(srgbRed: 255 / 255, green: 247 / 255, blue: 241 / 255, alpha: 1)
    static let softStroke = NSColor(srgbRed: 213 / 255, green: 167 / 255, blue: 146 / 255, alpha: 1)
    static let lineSoft = NSColor(srgbRed: 233 / 255, green: 180 / 255, blue: 157 / 255, alpha: 0.35)
}

private func applyShadow(color: NSColor, blur: CGFloat, y: CGFloat, alpha: CGFloat, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: y)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

private func fillRoundedRect(
    _ rect: CGRect,
    radius: CGFloat,
    colors: [NSColor],
    angle: CGFloat,
    stroke: NSColor? = nil,
    lineWidth: CGFloat = 0
) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()
    NSGradient(colors: colors)?.draw(in: path, angle: angle)
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

private func fillPill(_ rect: CGRect, color: NSColor) {
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
    color.setFill()
    path.fill()
}

private func fillCircle(center: CGPoint, radius: CGFloat, color: NSColor) {
    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    let path = NSBezierPath(ovalIn: rect)
    color.setFill()
    path.fill()
}

private func strokePath(
    points: [CGPoint],
    lineWidth: CGFloat,
    color: NSColor,
    lineJoin: NSBezierPath.LineJoinStyle = .round,
    lineCap: NSBezierPath.LineCapStyle = .round
) {
    guard let first = points.first else {
        return
    }

    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.lineWidth = lineWidth
    path.lineJoinStyle = lineJoin
    path.lineCapStyle = lineCap
    color.setStroke()
    path.stroke()
}

private func drawCardRows(in card: CGRect, mirrored: Bool) {
    let top = card.minY + 96
    let spacing: CGFloat = 82
    let dotRadius: CGFloat = 18
    let rowHeight: CGFloat = 30

    for index in 0..<3 {
        let y = top + CGFloat(index) * spacing
        if mirrored {
            let baseWidth: CGFloat = index == 1 ? 146 : (index == 0 ? 112 : 94)
            fillPill(
                CGRect(x: card.minX + 30, y: y - rowHeight / 2, width: baseWidth, height: rowHeight),
                color: Palette.clay
            )
            fillCircle(center: CGPoint(x: card.minX + 176 + CGFloat(index == 1 ? 28 : 0), y: y), radius: dotRadius, color: index == 1 ? Palette.parchmentDark : Palette.clay)
        } else {
            let baseWidth: CGFloat = index == 1 ? 124 : (index == 0 ? 94 : 88)
            fillCircle(center: CGPoint(x: card.minX + 76, y: y), radius: dotRadius, color: index == 1 ? Palette.parchmentDark : Palette.warmWhite)
            fillPill(
                CGRect(x: card.minX + 114, y: y - rowHeight / 2, width: baseWidth, height: rowHeight),
                color: Palette.warmWhite
            )
            if index != 1 {
                fillPill(
                    CGRect(x: card.minX + 220, y: y - rowHeight / 2, width: index == 0 ? 28 : 42, height: rowHeight),
                    color: Palette.parchmentDark.withAlphaComponent(0.9)
                )
            }
        }
    }
}

private func drawDiamond(center: CGPoint, size: CGFloat) {
    guard let context = NSGraphicsContext.current?.cgContext else {
        return
    }

    NSGraphicsContext.saveGraphicsState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: .pi / 4)

    let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
    let path = NSBezierPath(roundedRect: rect, xRadius: 70, yRadius: 70)
    path.addClip()
    NSGradient(colors: [Palette.clayDark, Palette.clay])?.draw(in: path, angle: -90)
    Palette.warmWhite.withAlphaComponent(0.34).setStroke()
    path.lineWidth = 6
    path.stroke()

    NSGraphicsContext.restoreGraphicsState()
}

private func drawArrows(center: CGPoint) {
    strokePath(
        points: [
            CGPoint(x: center.x - 70, y: center.y + 38),
            CGPoint(x: center.x + 54, y: center.y + 38)
        ],
        lineWidth: 24,
        color: Palette.warmWhite
    )
    strokePath(
        points: [
            CGPoint(x: center.x + 24, y: center.y + 68),
            CGPoint(x: center.x + 56, y: center.y + 38),
            CGPoint(x: center.x + 24, y: center.y + 8)
        ],
        lineWidth: 24,
        color: Palette.warmWhite
    )

    strokePath(
        points: [
            CGPoint(x: center.x + 68, y: center.y - 38),
            CGPoint(x: center.x - 54, y: center.y - 38)
        ],
        lineWidth: 24,
        color: Palette.parchmentDark
    )
    strokePath(
        points: [
            CGPoint(x: center.x - 24, y: center.y - 8),
            CGPoint(x: center.x - 56, y: center.y - 38),
            CGPoint(x: center.x - 24, y: center.y - 68)
        ],
        lineWidth: 24,
        color: Palette.parchmentDark
    )
}

private func drawConnector(from start: CGPoint, to end: CGPoint, via control1: CGPoint, _ control2: CGPoint, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: start)
    path.curve(to: end, controlPoint1: control1, controlPoint2: control2)
    path.lineWidth = 24
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}

private func drawIcon(size: CGFloat) {
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let background = CGRect(x: 44, y: 44, width: 936, height: 936)
    fillRoundedRect(
        background,
        radius: 224,
        colors: [Palette.parchment, Palette.parchmentDark],
        angle: -55,
        stroke: Palette.warmWhite.withAlphaComponent(0.9),
        lineWidth: 10
    )

    NSColor.white.withAlphaComponent(0.72).setFill()
    NSBezierPath(ovalIn: CGRect(x: 146, y: 612, width: 500, height: 332)).fill()
    Palette.parchmentDark.withAlphaComponent(0.42).setFill()
    NSBezierPath(ovalIn: CGRect(x: 472, y: 140, width: 436, height: 316)).fill()

    let leftCard = CGRect(x: 184, y: 346, width: 276, height: 404)
    let rightCard = CGRect(x: 564, y: 274, width: 276, height: 404)
    let center = CGPoint(x: 512, y: 512)

    applyShadow(color: Palette.clayDark, blur: 28, y: -22, alpha: 0.12) {
        drawConnector(
            from: CGPoint(x: leftCard.maxX - 28, y: leftCard.midY - 4),
            to: CGPoint(x: center.x - 6, y: center.y + 52),
            via: CGPoint(x: leftCard.maxX + 34, y: leftCard.midY + 12),
            CGPoint(x: center.x - 54, y: center.y + 56),
            color: Palette.softStroke.withAlphaComponent(0.46)
        )
        drawConnector(
            from: CGPoint(x: center.x - 10, y: center.y - 50),
            to: CGPoint(x: rightCard.minX + 78, y: rightCard.midY + 14),
            via: CGPoint(x: center.x + 36, y: center.y - 84),
            CGPoint(x: rightCard.minX + 34, y: rightCard.midY - 18),
            color: Palette.softStroke.withAlphaComponent(0.62)
        )

        applyShadow(color: Palette.clayDark, blur: 20, y: -12, alpha: 0.10) {
            fillRoundedRect(
                leftCard,
                radius: 96,
                colors: [Palette.clayLight, Palette.clay],
                angle: -90,
                stroke: Palette.lineSoft,
                lineWidth: 6
            )
            fillRoundedRect(
                rightCard,
                radius: 96,
                colors: [Palette.parchment, Palette.warmWhite],
                angle: -90,
                stroke: Palette.softStroke,
                lineWidth: 6
            )
        }

        drawCardRows(in: leftCard, mirrored: false)
        drawCardRows(in: rightCard, mirrored: true)
        drawDiamond(center: center, size: 232)
        drawArrows(center: center)
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift script/generate-app-icon.swift <output-png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
drawIcon(size: size)
image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL, options: .atomic)
