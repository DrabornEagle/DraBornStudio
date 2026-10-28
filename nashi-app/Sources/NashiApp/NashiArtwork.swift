import AppKit

/// Coconut artwork shared by the app, menu bar and brand exports.
enum NashiArtwork {
    static let gold=NSColor(srgbRed:0.45,green:0.88,blue:0.77,alpha:1)
    static let ink=NSColor(srgbRed:0.20,green:0.25,blue:0.14,alpha:1)
    static func bodyPath()->CGPath {
        let p=CGMutablePath();p.move(to:CGPoint(x:0.50,y:0.235))
        p.addCurve(to:CGPoint(x:0.865,y:0.36),control1:CGPoint(x:0.60,y:0.17),control2:CGPoint(x:0.79,y:0.23))
        p.addCurve(to:CGPoint(x:0.66,y:0.905),control1:CGPoint(x:0.99,y:0.56),control2:CGPoint(x:0.85,y:0.85))
        p.addCurve(to:CGPoint(x:0.13,y:0.64),control1:CGPoint(x:0.43,y:0.99),control2:CGPoint(x:0.16,y:0.88))
        p.addCurve(to:CGPoint(x:0.43,y:0.228),control1:CGPoint(x:0.08,y:0.39),control2:CGPoint(x:0.26,y:0.18))
        p.addQuadCurve(to:CGPoint(x:0.50,y:0.235),control:CGPoint(x:0.468,y:0.25));p.closeSubpath();return p
    }
    static func leafPath()->CGPath {
        let p=CGMutablePath();p.move(to:CGPoint(x:0.49,y:0.17))
        p.addCurve(to:CGPoint(x:0.74,y:0.115),control1:CGPoint(x:0.53,y:0.03),control2:CGPoint(x:0.73,y:0.065))
        p.addCurve(to:CGPoint(x:0.49,y:0.17),control1:CGPoint(x:0.66,y:0.24),control2:CGPoint(x:0.56,y:0.23));p.closeSubpath();return p
    }
    static func draw(in rect:NSRect,happy:Bool=false,monochrome:Bool=false) {
        if !monochrome, let url=Bundle.main.url(forResource:"NashiIcon",withExtension:"icns"), let image=NSImage(contentsOf:url) {
            image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1);return
        }
        guard let c=NSGraphicsContext.current?.cgContext else {return}
        c.saveGState();defer{c.restoreGState()}
        c.translateBy(x:rect.minX,y:rect.maxY);c.scaleBy(x:rect.width,y:-rect.height)
        c.setFillColor((monochrome ? NSColor.black:NSColor(srgbRed:0.45,green:0.25,blue:0.12,alpha:1)).cgColor)
        c.fillEllipse(in:CGRect(x:0.12,y:0.19,width:0.78,height:0.69))
        if monochrome {c.setBlendMode(.clear)} else {c.setFillColor(NSColor(srgbRed:0.98,green:0.96,blue:0.89,alpha:1).cgColor)}
        c.fillEllipse(in:CGRect(x:0.25,y:0.24,width:0.56,height:0.48));c.setBlendMode(.normal)
        c.setFillColor((monochrome ? NSColor.black:gold).cgColor);c.addPath(leafPath());c.fillPath()
    }
    static func mark(size:CGFloat,happy:Bool=false)->NSImage {
        NSImage(size:NSSize(width:size,height:size),flipped:false) { rect in draw(in:rect,happy:happy);return true }
    }
    static func menuIcon(updateAvailable:Bool=false)->NSImage {
        let image=NSImage(size:NSSize(width:20,height:20),flipped:false) { rect in
            draw(in:rect.insetBy(dx:0.5,dy:0.5),monochrome:true)
            if updateAvailable { NSColor.black.setFill();NSBezierPath(ovalIn:NSRect(x:15,y:15,width:4,height:4)).fill() }
            return true
        }
        image.isTemplate=true;image.accessibilityDescription=updateAvailable ? "Coconut-app update available":"Coconut-app";return image
    }
}
