import Foundation
import MobileCoreServices

enum SharedMediaType: String, Codable, CaseIterable {
    case text, url, image, video, gpx

    var toUTTypeIdentifier: String {
        switch self {
        case .text:
            return kUTTypeText as String
        case .url:
            return kUTTypeURL as String
        case .image:
            return kUTTypeImage as String
        case .video:
            return kUTTypeMovie as String
        case .gpx:
            return "org.gpx+xml"
        }
    }
}

struct SharedMediaFile: Codable {
    let path: String
    let mimeType: String?
    let thumbnail: String?
    let duration: Double?
    let type: SharedMediaType
}
