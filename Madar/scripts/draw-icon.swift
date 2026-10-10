import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
let width = 1024
let context = CGContext(data: nil, width: width, height: width, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 238/255.0, green: 232/255.0, blue: 221/255.0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: width))
let brass = CGColor(red: 129/255.0, green: 99/255.0, blue: 43/255.0, alpha: 1)
context.setFillColor(brass); context.setStrokeColor(brass)
context.setLineWidth(13); context.strokeEllipse(in: CGRect(x: 208, y: 208, width: 608, height: 608))
context.setLineWidth(20); context.strokeEllipse(in: CGRect(x: 330, y: 330, width: 364, height: 364))
context.fillEllipse(in: CGRect(x: 453, y: 453, width: 118, height: 118))
context.fillEllipse(in: CGRect(x: 658, y: 704, width: 72, height: 72))
let target = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
