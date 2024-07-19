import Flutter
import UIKit
import Photos

public let kSchemePrefix = "ShareMedia"
public let kUserDefaultsKey = "ShareKey"
public let kUserDefaultsMessageKey = "ShareMessageKey"
public let kAppGroupIdKey = "AppGroupId"

public class SwiftReceiveSharingIntentPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let kMessagesChannel = "receive_sharing_intent/messages"
    static let kEventsChannelMedia = "receive_sharing_intent/events-media"

    private var initialMedia: [SharedMediaFile]?
    private var latestMedia: [SharedMediaFile]?

    private var eventSinkMedia: FlutterEventSink?

    public static let instance = SwiftReceiveSharingIntentPlugin()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: kMessagesChannel, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)

        let chargingChannelMedia = FlutterEventChannel(name: kEventsChannelMedia, binaryMessenger: registrar.messenger())
        chargingChannelMedia.setStreamHandler(instance)

        registrar.addApplicationDelegate(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("1")
        switch call.method {
        case "getInitialMedia":
            result(toJson(data: self.initialMedia))
        case "reset":
            self.initialMedia = nil
            self.latestMedia = nil
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func hasMatchingSchemePrefix(url: URL?) -> Bool {
        print("0: ", url)
        if let url = url, let appDomain = Bundle.main.bundleIdentifier {
            return url.absoluteString.hasPrefix("\(kSchemePrefix)-\(appDomain)")
        }
        return false
    }

    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable : Any] = [:]) -> Bool {
        print("2")
        if let url = launchOptions[UIApplication.LaunchOptionsKey.url] as? URL {
            if (hasMatchingSchemePrefix(url: url)) {
                return handleUrl(url: url, setInitialData: true)
            }
            return true
        } else if let activityDictionary = launchOptions[UIApplication.LaunchOptionsKey.userActivityDictionary] as? [AnyHashable: Any] {
            for key in activityDictionary.keys {
                if let userActivity = activityDictionary[key] as? NSUserActivity {
                    if let url = userActivity.webpageURL {
                        if (hasMatchingSchemePrefix(url: url)) {
                            return handleUrl(url: url, setInitialData: true)
                        }
                        return true
                    }
                }
            }
        }
        return true
    }

    public func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("3, ", url)
        if (hasMatchingSchemePrefix(url: url)) {
            return handleUrl(url: url, setInitialData: false)
        }
        return false
    }

    public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]) -> Void) -> Bool {
        print("4")
        if let url = userActivity.webpageURL {
            if (hasMatchingSchemePrefix(url: url)) {
                return handleUrl(url: url, setInitialData: true)
            }
        }
        return false
    }

    private func handleUrl(url: URL?, setInitialData: Bool) -> Bool {
        // Fetch the app group identifier from the Info.plist or use a default
        let appGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        let defaultGroupId = "group.\(Bundle.main.bundleIdentifier!)"
        let userDefaults = UserDefaults(suiteName: appGroupId ?? defaultGroupId)
        
        // Print the app group information and UserDefaults object
        print("App Group ID: ", appGroupId ?? "nil", ", Default Group ID: ", defaultGroupId)
        print("UserDefaults: ", userDefaults?.dictionaryRepresentation() ?? "nil")
        
        // Retrieve and print the message stored in UserDefaults
        let message = userDefaults?.string(forKey: kUserDefaultsMessageKey)
        print("Message: ", message ?? "nil")
        
        // Retrieve the JSON data stored in UserDefaults
        if let jsonData = userDefaults?.object(forKey: kUserDefaultsKey) as? Data {
            print("Raw jsonData: ", jsonData)
            print("jsonData as String: ", String(data: jsonData, encoding: .utf8) ?? "nil")
            
            // Decode the JSON data into an array of SharedMediaFile objects
            let sharedArray = decode(data: jsonData)
            let sharedMediaFiles: [SharedMediaFile] = sharedArray.compactMap { mediaFile in
                print("Mediafile: ", mediaFile)
                // Resolve the path for each media file
                guard let path = mediaFile.type == .text || mediaFile.type == .url ? mediaFile.path : getAbsolutePath(for: mediaFile.path) else {
                    return nil
                }
                
                // Create a new SharedMediaFile object with the resolved path
                return SharedMediaFile(
                    path: path,
                    mimeType: mediaFile.mimeType,
                    thumbnail: getAbsolutePath(for: mediaFile.thumbnail),
                    duration: mediaFile.duration,
                    type: mediaFile.type
                )
            }
            
            // Update the latest media files and initial media files if needed
            latestMedia = sharedMediaFiles
            if(setInitialData) {
                initialMedia = latestMedia
            }
            eventSinkMedia?(toJson(data: latestMedia))
        } else {
            print("No shared media files found in UserDefaults.")
        }
        
        return true
    }



    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSinkMedia = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSinkMedia = nil
        return nil
    }

    private func getAbsolutePath(for identifier: String?) -> String? {
        guard let identifier else {
            return nil
        }

        if (identifier.starts(with: "file://") || identifier.starts(with: "/var/mobile/Media") || identifier.starts(with: "/private/var/mobile")) {
            return identifier.replacingOccurrences(of: "file://", with: "")
        }

        guard let phAsset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: .none).firstObject else {
            return nil
        }

        let (url, _) = getFullSizeImageURLAndOrientation(for: phAsset)
        return url
    }

    private func getFullSizeImageURLAndOrientation(for asset: PHAsset) -> (String?, Int) {
        var url: String? = nil
        var orientation: Int = 0
        let semaphore = DispatchSemaphore(value: 0)
        let options2 = PHContentEditingInputRequestOptions()
        options2.isNetworkAccessAllowed = true
        asset.requestContentEditingInput(with: options2) { (input, info) in
            orientation = Int(input?.fullSizeImageOrientation ?? 0)
            url = input?.fullSizeImageURL?.path
            semaphore.signal()
        }
        semaphore.wait()
        return (url, orientation)
    }

    private func decode(data: Data) -> [SharedMediaFile] {
        let encodedData = try? JSONDecoder().decode([SharedMediaFile].self, from: data)
        return encodedData!
    }

    private func toJson(data: [SharedMediaFile]?) -> String? {
        if data == nil {
            return nil
        }
        let encodedData = try? JSONEncoder().encode(data)
        let json = String(data: encodedData!, encoding: .utf8)!
        return json
    }
}
