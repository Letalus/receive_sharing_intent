//
//  UrlExtension.swift
//  receive_sharing_intent
//
//  Created by Christian Eichmueller on 19.07.24.
//

import MobileCoreServices

extension URL {
    func mimeType() -> String {
        let pathExtension = self.pathExtension as NSString
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension, nil)?.takeRetainedValue() {
            if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                return mimetype as String
            }
        }
        return "application/octet-stream"
    }
}
