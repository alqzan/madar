import Foundation
import SwiftData

/// Where the synced configuration lives. Device rows are never mirrored.
public enum CloudMirrorTarget: Equatable, Sendable {
    case local
    case privateDatabase(String)
    var database: ModelConfiguration.CloudKitDatabase {
        switch self { case .local: .none; case .privateDatabase(let id): .private(id) }
    }
}

public enum MadarCloudMirror {
    /// Set once by the app before the store opens, from the signed build's `MadarCloudKitContainer`
    /// Info.plist key. It stays nil in builds without the iCloud entitlement: `CKContainer`
    /// traps for an unentitled identifier, so nothing may open a mirror then.
    @MainActor public static var provisionedContainerIdentifier: String?

    /// A generation mirrors only when its pointer was bound to the very container this build is
    /// entitled for. Older pointers carry the identifier as compatibility metadata only.
    public static func target(pointerIdentifier: String?, provisioned: String?) -> CloudMirrorTarget {
        guard let id = pointerIdentifier, !id.isEmpty, id == provisioned else { return .local }
        return .privateDatabase(id)
    }
}
