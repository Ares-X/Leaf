#!/usr/bin/env swift
import AppKit
import Foundation

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/Leaf.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let outer:[(CGFloat,CGFloat)] = [
    (0.741627,0.242424),(0.723285,0.273525),(0.688995,0.301435),(0.507177,0.381978),
    (0.425040,0.452951),(0.393142,0.518341),(0.392344,0.596491),(0.417863,0.514354),
    (0.465710,0.455343),(0.517544,0.417863),(0.708931,0.318182),(0.669856,0.442584),
    (0.610845,0.540670),(0.550239,0.590909),(0.417863,0.651515),(0.580542,0.610845),
    (0.626794,0.585327),(0.676236,0.539075),(0.710526,0.483254),(0.733652,0.413078)
]
let stem:[(CGFloat,CGFloat)] = [
    (0.535885,0.490431),(0.456938,0.535885),(0.397129,0.601276),(0.358852,0.681021),
    (0.346890,0.763955),(0.379585,0.679426),(0.431419,0.587719),(0.483254,0.528708)
]

func path(_ points:[(CGFloat,CGFloat)], _ size:CGFloat)->NSBezierPath {
    let p=NSBezierPath()
    guard let first=points.first else{return p}
    p.move(to:NSPoint(x:first.0*size,y:(1-first.1)*size))
    for q in points.dropFirst(){p.line(to:NSPoint(x:q.0*size,y:(1-q.1)*size))}
    p.close()
    return p
}

func draw(_ pixels:Int, to url:URL)throws {
    let size=CGFloat(pixels)
    guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0) else{throw NSError(domain:"LeafIcon",code:1)}
    rep.size=NSSize(width:size,height:size)
    NSGraphicsContext.saveGraphicsState()
    guard let context=NSGraphicsContext(bitmapImageRep:rep) else{throw NSError(domain:"LeafIcon",code:2)}
    NSGraphicsContext.current=context
    context.shouldAntialias=true
    NSColor.clear.setFill();NSRect(x:0,y:0,width:size,height:size).fill()

    let inset=size*0.065
    let tile=NSBezierPath(roundedRect:NSRect(x:inset,y:inset,width:size-2*inset,height:size-2*inset),xRadius:size*0.145,yRadius:size*0.145)
    let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.16);shadow.shadowBlurRadius=size*0.028;shadow.shadowOffset=NSSize(width:0,height:-size*0.012)
    shadow.set()
    NSColor(calibratedWhite:0.992,alpha:1).setFill();tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=context
    context.shouldAntialias=true
    NSColor(calibratedWhite:0.055,alpha:1).setFill()
    path(outer,size).fill()
    path(stem,size).fill()
    NSGraphicsContext.restoreGraphicsState()

    guard let data=rep.representation(using:.png,properties:[.compressionFactor:1]) else{throw NSError(domain:"LeafIcon",code:3)}
    try data.write(to:url)
}

let specs:[(String,Int)] = [
    ("icon_16x16.png",16),("icon_16x16@2x.png",32),
    ("icon_32x32.png",32),("icon_32x32@2x.png",64),
    ("icon_128x128.png",128),("icon_128x128@2x.png",256),
    ("icon_256x256.png",256),("icon_256x256@2x.png",512),
    ("icon_512x512.png",512),("icon_512x512@2x.png",1024)
]
for (name,size) in specs{try draw(size,to:out.appendingPathComponent(name))}
