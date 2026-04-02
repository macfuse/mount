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

internal enum Alert {
    @discardableResult
    internal static func display(
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
