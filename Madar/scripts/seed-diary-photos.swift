// Synthetic simulator-only inputs for DiaryEditorUITests photo tests.
// Usage: swift scripts/seed-diary-photos.swift <booted simulator UUID> <artifact folder> [first day YYYY-MM-DD]
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

guard (3...4).contains(CommandLine.arguments.count) else { fatalError("Pass a booted simulator UUID, an artifact folder, and optionally the first day as YYYY-MM-DD") }
let device = CommandLine.arguments[1], folder = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let fixtureFirstDay = CommandLine.arguments.count == 4 ? CommandLine.arguments[3] : "2001-04-17"
let dayFormatter = DateFormatter()
dayFormatter.calendar = Calendar(identifier: .gregorian)
dayFormatter.locale = Locale(identifier: "en_US_POSIX")
dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
dayFormatter.dateFormat = "yyyy-MM-dd"
guard fixtureFirstDay.count == 10, let firstDate = dayFormatter.date(from: fixtureFirstDay),
      dayFormatter.string(from: firstDate) == fixtureFirstDay else {
    fatalError("The fixture day must be a valid Gregorian YYYY-MM-DD date")
}
let devices = try JSONSerialization.jsonObject(with: run(["list", "devices", "available", "-j"])) as! [String: Any]
let all = (devices["devices"] as! [String: [[String: Any]]]).values.flatMap { $0 }
guard all.contains(where: { $0["udid"] as? String == device && $0["state"] as? String == "Booted" }) else {
    fatalError("This script only writes synthetic photos to an explicitly selected booted simulator")
}
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let stamp = folder.appendingPathComponent("seeded-\(device)-\(fixtureFirstDay)")
let legacyStamp = folder.appendingPathComponent("seeded-\(device)")
if !FileManager.default.fileExists(atPath: stamp.path)
    && !(fixtureFirstDay == "2001-04-17" && FileManager.default.fileExists(atPath: legacyStamp.path)) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    for offset in 0...1 {
        let date = calendar.date(byAdding: .day, value: offset, to: firstDate)!
        let day = dayFormatter.string(from: date)
        let exifDay = day.replacingOccurrences(of: "-", with: ":")
        let context = CGContext(data: nil, width: 960, height: 720, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: offset == 0 ? 0.15 : 0.7, green: 0.45, blue: 0.65, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 960, height: 720))
        context.setFillColor(CGColor(gray: 0.9, alpha: 1)); context.fillEllipse(in: CGRect(x: 300, y: 180, width: 360, height: 360))
        let file = folder.appendingPathComponent("madar-synthetic-\(day).jpg")
        let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        let exifDateTime = exifDay + " 12:00:00"
        let metadata: [CFString: Any] = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: exifDateTime,
            kCGImagePropertyExifOffsetTimeOriginal: "+03:00"], kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: exifDateTime]]
        CGImageDestinationAddImage(destination, context.makeImage()!, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write synthetic JPEG") }
        let instant = ISO8601DateFormatter().date(from: "\(day)T12:00:00+03:00")!
        try FileManager.default.setAttributes([.creationDate: instant, .modificationDate: instant], ofItemAtPath: file.path)
        _ = try run(["addmedia", device, file.path])
    }
    try Data("Two synthetic photos, \(fixtureFirstDay) and the following day, noon Riyadh.\n".utf8).write(to: stamp)
}
print("Synthetic Photos fixture ready: one photo on \(fixtureFirstDay), one on the following day. No real-device library is accessed.")
