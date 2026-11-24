import Foundation
import SwiftData
import UIKit
import FitlingCore

/// What can be measured (FitlingCore), for pickers.
extension MeasurementKind: @retroactive Identifiable {
    public var id: String { rawValue }
}

/// Body weight and circumferences (TASKS 4.8). The user types in their own units; the store
/// keeps kilograms and centimetres.
@MainActor
struct BodyLog {
    let context: ModelContext
    let userID: UUID
    var usesMetric = Locale.current.measurementSystem == .metric
    var timeZone: TimeZone = .current
    var now: () -> Date = Date.init

    /// Oldest first, so a chart can draw them in order.
    func measurements(of kind: MeasurementKind) -> [BodyMeasurement] {
        let userID = userID
        let raw = kind.rawValue
        return (try? context.fetch(FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate<BodyMeasurement> { $0.userID == userID && $0.kind == raw && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.measuredOn), SortDescriptor(\.updatedAt)]
        ))) ?? []
    }

    /// From the user's unit to kilograms or centimetres. Nil outside what the database accepts (FitlingCore).
    func storedValue(_ value: Double, kind: MeasurementKind) -> Double? {
        BodyMeasurements.storedValue(value, kind: kind, usesMetric: usesMetric)
    }

    func displayValue(_ measurement: BodyMeasurement) -> Double {
        BodyMeasurements.displayValue(measurement.value, kind: MeasurementKind(rawValue: measurement.kind) ?? .waist, usesMetric: usesMetric)
    }

    var weightSymbol: String { usesMetric ? UnitMass.kilograms.symbol : UnitMass.pounds.symbol }
    var lengthSymbol: String { usesMetric ? UnitLength.centimeters.symbol : UnitLength.inches.symbol }

    @discardableResult
    func add(_ value: Double, kind: MeasurementKind, on day: Day) -> BodyMeasurement? {
        guard let stored = storedValue(value, kind: kind), day <= Day(now(), timeZone: timeZone) else { return nil }
        let measurement = BodyMeasurement(id: UUID(), userID: userID, measuredOn: day, kind: kind.rawValue, value: stored, updatedAt: now())
        context.insert(measurement)
        try? context.save()
        return measurement
    }

    func delete(_ measurement: BodyMeasurement) {
        measurement.deletedAt = now()
        measurement.updatedAt = now()
        measurement.needsPush = true
        try? context.save()
    }
}

/// Progress photos (TASKS 4.9): only on this device, in the app's own folder, left out of
/// backups and never uploaded. The store keeps the file name; the image is the file.
@MainActor
struct ProgressPhotoStore {
    let context: ModelContext
    var folder: URL = ProgressPhotoStore.defaultFolder
    var timeZone: TimeZone = .current
    var now: () -> Date = Date.init

    static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "ProgressPhotos", directoryHint: .isDirectory)
    }

    /// Newest first.
    func photos() -> [ProgressPhoto] {
        (try? context.fetch(FetchDescriptor<ProgressPhoto>(sortBy: [SortDescriptor(\.takenOn, order: .reverse)]))) ?? []
    }

    func url(of photo: ProgressPhoto) -> URL {
        folder.appending(path: photo.fileName)
    }

    /// The photo itself, for the grid and the detail. The file path without percent encoding: the folder is in
    /// "Application Support", and "%20" is not a space to the file system.
    static func image(at url: URL) -> UIImage? {
        UIImage(contentsOfFile: url.path(percentEncoded: false))
    }

    @discardableResult
    func add(_ jpeg: Data, on day: Day? = nil) throws -> ProgressPhoto {
        try prepareFolder()
        let photo = ProgressPhoto(id: UUID(), takenOn: day ?? Day(now(), timeZone: timeZone), fileName: "\(UUID().uuidString).jpg")
        var url = url(of: photo)
        try jpeg.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        context.insert(photo)
        try context.save()
        return photo
    }

    func delete(_ photo: ProgressPhoto) {
        try? FileManager.default.removeItem(at: url(of: photo))
        context.delete(photo)
        try? context.save()
    }

    /// Signing out removes every photo: they belong to the account that took them.
    func removeAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func prepareFolder() throws {
        var folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }
}
