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

    /// The macFUSE application bundle associated with the mount framework.
    ///
    /// In debug builds, this resolves the application inside the installed file system bundle. In
    /// release builds, it derives the file system bundle location from the framework bundle.
    static var app: Bundle {
        #if DEBUG
        let fileSystemBundleURL = URL(
            fileURLWithPath: "/Library/Filesystems/macfuse.fs",
            isDirectory: true
        )
        #else
        let framework = Bundle(for: MountFrameworkMarker.self)

        let fileSystemBundleURL = framework
            .bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        #endif

        guard let fileSystmeBundle = Bundle(url: fileSystemBundleURL),
              let appURL = fileSystmeBundle.url(forResource: Variant.name, withExtension: "app"),
              let appBundle = Bundle(url: appURL) else {
                fatalError()
        }
        return appBundle
    }
}
