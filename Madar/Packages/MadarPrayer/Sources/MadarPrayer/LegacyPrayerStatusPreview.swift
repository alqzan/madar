import MadarCore

/// A read-only preview of how a legacy Arabic prayer status maps to the v1 model.
/// It deliberately does not create records or infer any timestamps.
public enum LegacyPrayerStatusPreview {
    public enum Disposition: Equatable, Sendable {
        case mapped
        case omittedUnloggedPrayer
        case preserveRawUnsupportedStatus
    }

    public enum RequiredFact: Hashable, Sendable {
        case adhanInstant
        case timeZoneID
        case qadaMadeUpAt
    }

    public struct Result: Equatable, Sendable {
        public let rawValue: String
        public let status: PrayerStoredStatus?
        public let disposition: Disposition
        public let requiredFacts: Set<RequiredFact>

        fileprivate init(
            rawValue: String,
            status: PrayerStoredStatus?,
            disposition: Disposition,
            requiredFacts: Set<RequiredFact> = []
        ) {
            self.rawValue = rawValue
            self.status = status
            self.disposition = disposition
            self.requiredFacts = requiredFacts
        }
    }

    /// Compares the preserved legacy civil day directly; it does not recalculate a prayer day.
    public static func preview(
        _ rawValue: String,
        legacyDay: GregorianDay,
        trackingStart: GregorianDay
    ) -> Result {
        switch rawValue {
        case "جماعة":
            return mapped(rawValue, as: .jamaah)
        case "منفردة":
            return mapped(rawValue, as: .alone)
        case "فائتة":
            return mapped(rawValue, as: .missed)
        case "قضاء":
            return mapped(rawValue, as: .qada, alsoRequires: .qadaMadeUpAt)
        case "لم":
            if legacyDay < trackingStart {
                return mapped(rawValue, as: .unrecordedHistory)
            }
            return Result(rawValue: rawValue, status: nil, disposition: .omittedUnloggedPrayer)
        default:
            return Result(rawValue: rawValue, status: nil, disposition: .preserveRawUnsupportedStatus)
        }
    }

    private static func mapped(
        _ rawValue: String,
        as status: PrayerStoredStatus,
        alsoRequires additionalFact: RequiredFact? = nil
    ) -> Result {
        var requiredFacts: Set<RequiredFact> = [.adhanInstant, .timeZoneID]
        if let additionalFact { requiredFacts.insert(additionalFact) }
        return Result(rawValue: rawValue, status: status, disposition: .mapped, requiredFacts: requiredFacts)
    }
}
