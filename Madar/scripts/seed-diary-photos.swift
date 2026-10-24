// Synthetic simulator-only inputs for DiaryEditorUITests.testDayPhotosLinkOnce.
// Usage: swift scripts/seed-diary-photos.swift <booted simulator UUID> <artifact folder>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func run(_ arguments: [String]) throws -> Data {
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["simctl"] + arguments; process.standardOutput = output
    try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: "DiaryPhotosFixture", code: Int(process.terminationStatus)) }
    return data
}

guard CommandLine.arguments.count == 3 else { fatalError("Pass a booted simulator UUID and an artifact folder") }
let device = CommandLine.arguments[1], folder = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let devices = try JSONSerialization.jsonObject(with: run(["list", "devices", "available", "-j"])) as! [String: Any]
let all = (devices["devices"] as! [String: [[String: Any]]]).values.flatMap { $0 }
guard all.contains(where: { $0["udid"] as? String == device && $0["state"] as? String == "Booted" }) else {
    fatalError("This script only writes synthetic photos to an explicitly selected booted simulator")
}
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let stamp = folder.appendingPathComponent("seeded-\(device)")
if !FileManager.default.fileExists(atPath: stamp.path) {
    for day in [17, 18] {
        let context = CGContext(data: nil, width: 960, height: 720, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: day == 17 ? 0.15 : 0.7, green: 0.45, blue: 0.65, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 960, height: 720))
        context.setFillColor(CGColor(gray: 0.9, alpha: 1)); context.fillEllipse(in: CGRect(x: 300, y: 180, width: 360, height: 360))
        let file = folder.appendingPathComponent("madar-synthetic-2001-04-\(day).jpg")
        let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        let date = "2001:04:\(day) 12:00:00"
        let metadata: [CFString: Any] = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: date,
            kCGImagePropertyExifOffsetTimeOriginal: "+03:00"], kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: date]]
        CGImageDestinationAddImage(destination, context.makeImage()!, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write synthetic JPEG") }
        let instant = ISO8601DateFormatter().date(from: "2001-04-\(day)T12:00:00+03:00")!
        try FileManager.default.setAttributes([.creationDate: instant, .modificationDate: instant], ofItemAtPath: file.path)
        _ = try run(["addmedia", device, file.path])
    }
    try Data("Two synthetic photos, 17 and 18 April 2001, noon Riyadh.\n".utf8).write(to: stamp)
}
print("Synthetic Photos fixture ready: one photo on 2001-04-17, one on the following day. No real-device library is accessed.")
