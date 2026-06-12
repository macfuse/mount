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

/// Shared parameters used by mount setup and troubleshooting flows.
enum Parameters {
    /// The incoming device message buffer byte count, consisting of 4 KiB for structured and 32 MiB
    /// for unstructured message data.
    static let deviceMessageBufferByteCount = 0x2001000

    /// The System Settings URL for the extension approval pane.
    static let extensionsSystemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension?ExtensionItems"
    )!

    /// The Getting Started guide URL.
    static let gettingStartedURL = URL(
        string: "https://github.com/macfuse/macfuse/wiki/Getting-Started"
    )!

    /// The Troubleshooting guide URL.
    static let troubleshootingURL = URL(
        string: "https://github.com/macfuse/macfuse/wiki/Troubleshooting"
    )!
}
