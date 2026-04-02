//
//  Parameters.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import Foundation

internal enum Parameters {
    static let extensionsSystemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension?ExtensionItems"
    )!
    static let gettingStartedURL = URL(
        string: "https://github.com/macfuse/macfuse/wiki/Getting-Started"
    )!
    static let troubleshootingURL = URL(
        string: "https://github.com/macfuse/macfuse/wiki/Troubleshooting"
    )!
}
