// Draws the Flipside app icon (vintage sampler vibe): cream chassis, a small
// green LCD with a waveform + red record dot, and a 4x4 grid of charcoal pads
// with one lit amber. Renders a 1024×1024 PNG.
//
//   swift tools/make-icon.swift /tmp/flipside-icon-1024.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/flipside-icon-1024.png"
let S = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}
func rr(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func fillGrad(_ rect: CGRect, _ radius: CGFloat, _ top: CGColor, _ bottom: CGColor) {
    ctx.saveGState()
    ctx.addPath(rr(rect, radius)); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    ctx.restoreGState()
}

ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

// Chassis — warm cream, subtle top-down gradient + a darker rim.
let margin: CGFloat = 56
let chassis = CGRect(x: margin, y: margin, width: CGFloat(S) - 2*margin, height: CGFloat(S) - 2*margin)
fillGrad(chassis, 200, c(234, 224, 199), c(206, 192, 160))
ctx.saveGState()
ctx.addPath(rr(chassis, 200)); ctx.setStrokeColor(c(150, 136, 108)); ctx.setLineWidth(6); ctx.strokePath()
ctx.restoreGState()

let inset: CGFloat = 92
let inner = chassis.insetBy(dx: inset, dy: inset)

// --- Top band: green LCD + red record dot ---
let bandH = inner.height * 0.20
let lcd = CGRect(x: inner.minX, y: inner.maxY - bandH, width: inner.width * 0.74, height: bandH)
fillGrad(lcd, 26, c(20, 30, 22), c(10, 18, 13))
ctx.saveGState()
ctx.addPath(rr(lcd, 26)); ctx.setStrokeColor(c(70, 90, 72)); ctx.setLineWidth(4); ctx.strokePath()
// waveform polyline
ctx.addPath(rr(lcd.insetBy(dx: 10, dy: 10), 18)); ctx.clip()
ctx.setStrokeColor(c(120, 232, 150)); ctx.setLineWidth(7); ctx.setLineJoin(.round); ctx.setLineCap(.round)
let midY = lcd.midY
let amps: [CGFloat] = [0.12, 0.5, 0.22, 0.78, 0.35, 0.62, 0.18, 0.9, 0.3, 0.55, 0.15, 0.7, 0.25]
let stepX = lcd.width / CGFloat(amps.count - 1)
ctx.move(to: CGPoint(x: lcd.minX, y: midY))
for (i, a) in amps.enumerated() {
    let x = lcd.minX + CGFloat(i) * stepX
    let y = midY + (i % 2 == 0 ? -1 : 1) * a * (lcd.height * 0.36)
    ctx.addLine(to: CGPoint(x: x, y: y))
}
ctx.strokePath()
ctx.restoreGState()

// Record dot
let dotR: CGFloat = bandH * 0.34
let dotC = CGPoint(x: inner.maxX - dotR - 6, y: lcd.midY)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 24, color: c(220, 50, 45, 0.7))
ctx.setFillColor(c(208, 52, 46)); ctx.fillEllipse(in: CGRect(x: dotC.x - dotR, y: dotC.y - dotR, width: 2*dotR, height: 2*dotR))
ctx.restoreGState()
ctx.setFillColor(c(255, 150, 140, 0.85))
ctx.fillEllipse(in: CGRect(x: dotC.x - dotR*0.4, y: dotC.y + dotR*0.1, width: dotR*0.55, height: dotR*0.45))

// --- 4x4 pad grid ---
let gridTop = lcd.minY - inner.height * 0.06
let gridRect = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: gridTop - inner.minY)
let gap: CGFloat = 26
let pad = (min(gridRect.width, gridRect.height) - 3*gap) / 4
let gridW = 4*pad + 3*gap
let originX = gridRect.midX - gridW/2
let originY = gridRect.midY - gridW/2

// One lit pad (row 2, col 1 — zero-based from bottom-left) for a focal point.
let litRow = 2, litCol = 1
for row in 0..<4 {
    for col in 0..<4 {
        let x = originX + CGFloat(col) * (pad + gap)
        let y = originY + CGFloat(row) * (pad + gap)
        let r = CGRect(x: x, y: y, width: pad, height: pad)
        let lit = (row == litRow && col == litCol)
        if lit {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 40, color: c(255, 170, 60, 0.9))
            fillGrad(r, 26, c(255, 206, 120), c(240, 150, 44))
            ctx.restoreGState()
        } else {
            fillGrad(r, 26, c(78, 74, 70), c(44, 41, 38))
        }
        // rim
        ctx.saveGState()
        ctx.addPath(rr(r, 26))
        ctx.setStrokeColor(lit ? c(255, 226, 170) : c(96, 91, 84))
        ctx.setLineWidth(4); ctx.strokePath()
        ctx.restoreGState()
        // top sheen
        ctx.saveGState()
        ctx.addPath(rr(r, 26)); ctx.clip()
        let sheen = CGGradient(colorsSpace: cs, colors: [c(255,255,255,0.18), c(255,255,255,0)] as CFArray, locations: [0,1])!
        ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.midY), options: [])
        ctx.restoreGState()
    }
}

guard let img = ctx.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: outPath)
guard let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no dest")
}
CGImageDestinationAddImage(dst, img, nil)
if !CGImageDestinationFinalize(dst) { fatalError("write failed") }
print("wrote \(outPath)")
