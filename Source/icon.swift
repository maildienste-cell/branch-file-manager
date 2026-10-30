import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(calibratedRed:r, green:g, blue:b, alpha:1) }
image.lockFocus()
let tile = NSBezierPath(roundedRect: NSRect(x:64,y:64,width:896,height:896),xRadius:202,yRadius:202)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.24); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width:0,height:-12); shadow.set()
color(0.04,0.13,0.22).setFill(); tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors:[color(0.035,0.12,0.23),color(0.06,0.29,0.36)])!.draw(in:tile,angle:65)
NSColor.white.withAlphaComponent(0.14).setStroke(); tile.lineWidth = 3; tile.stroke()
// A continuous branch visually joins the two destinations.
let branch = NSBezierPath(); branch.lineWidth = 40; branch.lineCapStyle = .round; branch.lineJoinStyle = .round
branch.move(to:NSPoint(x:300,y:747)); branch.line(to:NSPoint(x:300,y:330)); branch.curve(to:NSPoint(x:356,y:274),controlPoint1:NSPoint(x:300,y:292),controlPoint2:NSPoint(x:318,y:274)); branch.line(to:NSPoint(x:520,y:274))
branch.move(to:NSPoint(x:300,y:619)); branch.line(to:NSPoint(x:520,y:619))
color(0.42,0.94,0.80).setStroke(); branch.stroke()
color(0.70,1,0.90).setFill(); NSBezierPath(ovalIn:NSRect(x:273,y:720,width:54,height:54)).fill()
func folder(_ y: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.3); shadow.shadowBlurRadius = 22; shadow.shadowOffset = NSSize(width:0,height:-12); shadow.set()
    let back = NSBezierPath(roundedRect:NSRect(x:479,y:y+25,width:296,height:173),xRadius:26,yRadius:26)
    color(0.94,0.61,0.18).setFill(); back.fill()
    NSBezierPath(roundedRect:NSRect(x:479,y:y+153,width:128,height:76),xRadius:22,yRadius:22).fill()
    NSGraphicsContext.restoreGraphicsState()
    let front = NSBezierPath(roundedRect:NSRect(x:479,y:y,width:296,height:176),xRadius:28,yRadius:28)
    NSGradient(colors:[color(1,0.69,0.23),color(1,0.86,0.46)])!.draw(in:front,angle:90)
    NSColor.white.withAlphaComponent(0.35).setStroke(); front.lineWidth=3; front.stroke()
}
folder(530); folder(185)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
