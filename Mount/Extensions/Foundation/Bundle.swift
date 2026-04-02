//
//  Bundle.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import Foundation

extension Bundle {
    private class MountFrameworkMarker { }

    internal static var app: Bundle {
        let framework = Bundle(for: MountFrameworkMarker.self)

        let fileSystemBundleUrl = framework
            .bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        guard let fileSystmeBundle = Bundle(url: fileSystemBundleUrl),
              let appUrl = fileSystmeBundle.url(forResource: Variant.name, withExtension: "app"),
              let appBundle = Bundle(url: appUrl) else {
                fatalError()
        }
        return appBundle
    }
}
