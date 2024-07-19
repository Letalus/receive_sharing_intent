import UIKit
import Social
import MobileCoreServices
import Photos
import Foundation
import ObjectiveC

@available(swift, introduced: 5.0)
open class RSIShareViewController: SLComposeServiceViewController {
    var hostAppBundleIdentifier = ""
    var appGroupId = ""
    var sharedMedia: [SharedMediaFile] = []

    open override func isContentValid() -> Bool {
        return true
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        loadIds()
    }

    open override func didSelectPost() {
        // This method won't be called because we handle media automatically in viewDidAppear
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Automatically handle and redirect without showing the dialog
        handleMediaAutomatically()
    }

    open override func configurationItems() -> [Any]! {
        return []
    }

    private func loadIds() {
        let shareExtensionAppBundleIdentifier = Bundle.main.bundleIdentifier!
        let lastIndexOfPoint = shareExtensionAppBundleIdentifier.lastIndex(of: ".")
        hostAppBundleIdentifier = String(shareExtensionAppBundleIdentifier[..<lastIndexOfPoint!])
        let defaultAppGroupId = "group.\(hostAppBundleIdentifier)"
        let customAppGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        appGroupId = customAppGroupId ?? defaultAppGroupId
    }

    private func handleMediaAutomatically() {
        print("0 Starting to handle media automatically")

        guard let content = extensionContext!.inputItems[0] as? NSExtensionItem,
                let contents = content.attachments else {
            dismissWithError()
            return
        }
        print("Starting to handle media automatically, content: \(content)")

        let group = DispatchGroup()
        for (index, attachment) in contents.enumerated() {
            for type in SharedMediaType.allCases {
                print("Checking for type: \(type)")
                if attachment.hasItemConformingToTypeIdentifier(type.toUTTypeIdentifier) {
                    print("Found matching type: \(type)")
                    group.enter()
                    attachment.loadItem(forTypeIdentifier: type.toUTTypeIdentifier) { [weak self] data, error in
                        guard let this = self, error == nil else {
                            self?.dismissWithError()
                            group.leave()
                            return
                        }
                        switch type {
                        case .text:
                            if let text = data as? String {
                                print("Handling text data: \(text)")
                                this.handleMedia(forLiteral: text, type: type, index: index, content: content)
                            }
                        case .url:
                            if let url = data as? URL {
                                print("Handling URL data: \(url)")
                                this.handleMedia(forLiteral: url.absoluteString, type: type, index: index, content: content)
                            }
                        case .gpx:
                            if let url = data as? URL {
                                print("Handling GPX data: \(url)")
                                this.handleMedia(forFile: url, type: type, index: index, content: content)
                            }
                        default:
                            if let url = data as? URL {
                                print("Handling file data: \(url)")
                                this.handleMedia(forFile: url, type: type, index: index, content: content)
                            } else if let image = data as? UIImage {
                                print("Handling image data")
                                this.handleMedia(forUIImage: image, type: type, index: index, content: content)
                            }
                        }
                        group.leave()
                    }
                    break
                }
            }
        }
        group.notify(queue: .main) {
            print("Finished handling all attachments, sharedMedia: \(self.sharedMedia)")
            self.saveAndRedirect()
        }
    }


    private func handleMedia(forLiteral item: String, type: SharedMediaType, index: Int, content: NSExtensionItem) {
        sharedMedia.append(SharedMediaFile(
            path: item,
            mimeType: type == .text ? "text/plain" : nil,
            thumbnail: nil,
            duration: nil,
            type: type
        ))
    }

    private func handleMedia(forUIImage image: UIImage, type: SharedMediaType, index: Int, content: NSExtensionItem) {
        let tempPath = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)!.appendingPathComponent("TempImage.png")
        if self.writeTempFile(image, to: tempPath) {
            let newPathDecoded = tempPath.absoluteString.removingPercentEncoding!
            sharedMedia.append(SharedMediaFile(
                path: newPathDecoded,
                mimeType: type == .image ? "image/png" : nil,
                thumbnail: nil,
                duration: nil,
                type: type
            ))
        }
    }

    private func handleMedia(forFile url: URL, type: SharedMediaType, index: Int, content: NSExtensionItem) {
        let fileName = getFileName(from: url, type: type)
        let newPath = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)!.appendingPathComponent(fileName)

        if copyFile(at: url, to: newPath) {
            let newPathDecoded = newPath.absoluteString.removingPercentEncoding!
            sharedMedia.append(SharedMediaFile(
                path: newPathDecoded,
                mimeType: url.mimeType(),
                thumbnail: nil,
                duration: nil,
                type: type
            ))
        }
    }

    private func saveAndRedirect(message: String? = nil) {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            print("[ERROR] Could not create UserDefaults with app group \(appGroupId)")
            return
        }
        userDefaults.set(toData(data: sharedMedia), forKey: kUserDefaultsKey)
        userDefaults.set(message, forKey: kUserDefaultsMessageKey)
        userDefaults.synchronize()
        print("Saved media files to UserDefaults: \(sharedMedia)")
        redirectToHostApp()
    }

    private func redirectToHostApp() {
        loadIds()
        guard let url = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):share") else {
            print("[ERROR] Could not create URL for redirect")
            return
        }
        var responder = self as UIResponder?
        let selectorOpenURL = sel_registerName("openURL:")

        while (responder != nil) {
            if (responder?.responds(to: selectorOpenURL))! {
                _ = responder?.perform(selectorOpenURL, with: url)
            }
            responder = responder!.next
        }
        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func dismissWithError() {
        print("[ERROR] Error loading data!")
        let alert = UIAlertController(title: "Error", message: "Error loading data", preferredStyle: .alert)

        let action = UIAlertAction(title: "Error", style: .cancel) { _ in
            self.dismiss(animated: true, completion: nil)
        }

        alert.addAction(action)
        present(alert, animated: true, completion: nil)
        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func getFileName(from url: URL, type: SharedMediaType) -> String {
        var name = url.lastPathComponent
        if name.isEmpty {
            switch type {
            case .image:
                name = UUID().uuidString + ".png"
            case .video:
                name = UUID().uuidString + ".mp4"
            case .text:
                name = UUID().uuidString + ".txt"
            case .gpx:
                name = UUID().uuidString + ".gpx"
            default:
                name = UUID().uuidString
            }
        }
        return name
    }

    private func writeTempFile(_ image: UIImage, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            let pngData = image.pngData()
            try pngData?.write(to: dstURL)
            return true
        } catch (let error) {
            print("Cannot write to temp file: \(error)")
            return false
        }
    }

    private func copyFile(at srcURL: URL, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
            return true
        } catch (let error) {
            print("Cannot copy item at \(srcURL) to \(dstURL): \(error)")
            return false
        }
    }

    private func toData(data: [SharedMediaFile]) -> Data {
        do {
            let encodedData = try JSONEncoder().encode(data)
            return encodedData
        } catch {
            print("Error encoding shared media files: \(error)")
            return Data()
        }
    }
}
