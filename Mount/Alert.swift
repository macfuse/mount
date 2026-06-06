//
//  Alert.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import CoreFoundation
import Foundation

/// Displays user-facing alerts for mount setup and recovery workflows.
enum Alert {
    /// Displays a caution alert and returns the selected response.
    ///
    /// - Parameters:
    ///   - header: The alert title.
    ///   - message: The alert message.
    ///   - defaultButtonTitle: The title of the default button.
    ///   - alternateButtonTitle: The title of the alternate button, or `nil` to omit it.
    ///   - otherButtonTitle: The title of the other button, or `nil` to omit it.
    /// - Returns: The response flags from `CFUserNotificationDisplayAlert`.
    @discardableResult
    static func display(
        header: String,
        message: String,
        defaultButtonTitle: String,
        alternateButtonTitle: String? = nil,
        otherButtonTitle: String? = nil
    ) -> CFOptionFlags {
        var options: CFOptionFlags = 0
        CFUserNotificationDisplayAlert(
            0,
            kCFUserNotificationCautionAlertLevel,
            Bundle.app.url(forResource: "AppIcon", withExtension: "icns") as CFURL?,
            nil,
            nil,
            header as CFString,
            message as CFString,
            defaultButtonTitle as CFString,
            alternateButtonTitle as CFString?,
            otherButtonTitle as CFString?,
            &options
        )
        return options
    }
}
