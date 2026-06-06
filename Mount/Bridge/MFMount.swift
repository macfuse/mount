//
//  MFMount.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import AppKit
import OSLog
import System

/// Uses `unexpectedFailure` as the C API failure sentinel for mount results.
extension MFMountResult: Bridge.PerformReturnValue {
    static var defaultErrorValue: MFMountResult { .unexpectedFailure }
}

/// Mounts a volume and associates it with a channel.
///
/// This function mounts a volume at `mountPoint` and associates the supplied channel with the
/// volume. The channel may not be closed or released for the lifetime of the mount.
///
/// If `quiet` is `false`, the implementation may present user-facing dialogs to help diagnose or
/// resolve mount issues. If `quiet` is `true`, failures are reported only through the return value.
///
/// If this function returns `unexpectedFailure`, it sets `errno` as follows:
///
/// | Value | Description |
/// | --- | --- |
/// | `EINVAL` | `channel` is `nil`, `channel` does not identify a valid channel object, `mountPoint` is `nil`, or `options` is `nil`. |
/// | `EAGAIN` | An unexpected failure occurred. |
///
/// For all other result values, `errno` is not meaningful.
///
/// - Parameters:
///   - channel: The channel to associate with the mounted volume. May not be `nil`.
///   - mountPoint: The path at which the volume should be mounted. May not be `nil`.
///   - options: A comma-separated string containing FUSE mount options. Pass an empty string if no
///     options are required. May not be `nil`.
///   - quiet: A Boolean value that suppresses user-facing recovery dialogs when set to `true`.
/// - Returns: A result value indicating whether the volume was mounted successfully or why the
///   mount operation failed.
@c(MFMount)
public func MFMount(
    _ channel: MFChannelRef!,
    _ mountPoint: UnsafePointer<CChar>!,
    _ options: UnsafePointer<CChar>!,
    _ quiet: Bool
) -> MFMountResult {
    Bridge.perform { () throws(Errno) in
        guard #available(macOS 15.4, *) else {
            Bridge.log(level: .error, "Unsupported version of macOS")
            return .unsupporteOSVersion
        }

        guard let channel = Bridge.unwrap(reference: channel, as: Channel.self) else {
            Bridge.log(level: .error, "Invalid argument channel")
            throw .invalidArgument
        }

        let mountPoint = mountPoint.map(FilePath.init(platformString:))
        guard let mountPoint else {
            Bridge.log(level: .error, "Invalid argument mountPoint")
            throw .invalidArgument
        }

        let options = options
            .map(String.init(cString:))?
            .split(separator: ",")
            .map(String.init)
            .map {
                $0.replacing(/\\(?<octal>[0-3][0-7]{2})/) {
                    guard let value = Int($0.output.octal, radix: 8),
                          let scalar = Unicode.Scalar(value) else {
                        fatalError()
                    }
                    return String(scalar)
                }
            }
        guard let options else {
            Bridge.log(level: .error, "Invalid argument options")
            throw .invalidArgument
        }

        let transport = XPCTransport()

        do throws(Errno) {
            try channel.open(with: transport)
        } catch {
            Bridge.log(level: .error, "Failed to open channel")
            throw error
        }

        while true {
            do throws(Mounter.Error) {
                try Mounter.mount(
                    backend: .fskit(endpoint: transport.endpoint),
                    mountPoint: mountPoint,
                    options: options
                )
                break
            } catch .installingFailed(.status(_)) {
                if !quiet {
                    let options = Alert.display(
                        header: String(localized: .installHelperToolsHeader),
                        message: String(
                            localized: .installHelperToolsMessage(productName: Variant.productName)
                        ),
                        defaultButtonTitle: String(localized: .installHelperToolsInstall),
                        alternateButtonTitle: String(localized: .installHelperToolsGettingStarted),
                        otherButtonTitle: String(localized: .installHelperToolsCancel)
                    )

                    switch options {
                    case kCFUserNotificationDefaultResponse:
                        continue
                    case kCFUserNotificationAlternateResponse:
                        NSWorkspace.shared.open(Parameters.gettingStartedURL)
                    default:
                        break
                    }
                }

                Bridge.log(level: .error, "Failed to install helper tools")
                return .helperToolsInstallationFailed
            } catch .installingFailed(.unknown) {
                /*
                 * This is an unexpected error which is most likely the result of macfuse.app being
                 * unable to communicate with its installer XPC service. In case macfuse.app has
                 * been damaged, reinstalling macFUSE might help.
                 */

                Bridge.log(level: .error, "Failed to install helper tools")
            } catch .settingPeerCodeSigningRequirementFailed {
                /*
                 * This is an unexpected error that is most likely the result of by a malformed or
                 * illegal peer code signing requirement string. There is no way for users to
                 * resolve this.
                 */

                Bridge.log(level: .error,
                           "Failed to set peer code signing requirements for mount service")
            } catch .unpackingReplyFailed {
                /*
                 * This is an unexpected error, most likely caused by a version mismatch between the
                 * mount service and this framework.
                 */

                Bridge.log(level: .error, "Failed to unpack reply from mount service")
            } catch .mountingFailed(.illegalArguments) {
                /*
                 * This is an unexpected error, most likely caused by a version mismatch between the
                 * mount service and this framework.
                 */

                Bridge.log(level: .error, "Illegal arguments passed to mount service")
            } catch .mountingFailed(.fileSystemExtensionNotFound) {
                if !quiet {
                    let options = Alert.display(
                        header: String(localized: .registerFileSystemExtensionHeader),
                        message: String(
                            localized: .registerFileSystemExtensionMessage(
                                productName: Variant.productName
                            )
                        ),
                        defaultButtonTitle: String(localized: .registerFileSystemExtensionRegister),
                        alternateButtonTitle: String(
                            localized: .registerFileSystemExtensionGettingStarted
                        ),
                        otherButtonTitle: String(localized: .registerFileSystemExtensionCancel)
                    )

                    switch options {
                    case kCFUserNotificationDefaultResponse:
                        try? Mounter.install(force: true, components: ["file-system-extensions"])
                    case kCFUserNotificationAlternateResponse:
                        NSWorkspace.shared.open(Parameters.gettingStartedURL)
                    default:
                        break
                    }
                }

                Bridge.log(level: .error, "File system extension not found")
                return .fileSystemExtensionNotFound
            } catch .mountingFailed(.fileSystemExtensionRequiresApproval) {
                if !quiet {
                    let options = Alert.display(
                        header: String(localized: .enableFileSystemExtensionHeader),
                        message: String(
                            localized: .enableFileSystemExtensionMessage(
                                productName: Variant.productName
                            )
                        ),
                        defaultButtonTitle: String(
                            localized: .enableFileSystemExtensionSystemSettings
                        ),
                        alternateButtonTitle: String(
                            localized: .enableFileSystemExtensionGettingStarted
                        ),
                        otherButtonTitle: String(localized: .enableFileSystemExtensionCancel)
                    )

                    switch options {
                    case kCFUserNotificationDefaultResponse:
                        /*
                         * Note: We could use SMAppService.openSystemSettingsLoginItems() to open
                         * System Settings. However, using the URL below scrolls down to the
                         * "Extensions" of the preference pane.
                         */
                        NSWorkspace.shared.open(Parameters.extensionsSystemSettingsURL)
                    case kCFUserNotificationAlternateResponse:
                        NSWorkspace.shared.open(Parameters.gettingStartedURL)
                    default:
                        break
                    }
                }

                Bridge.log(level: .error, "File system extension not enabled")
                return .fileSystemExtensionRequiresApproval
            } catch .mountingFailed(.activatingDeviceFailed) {
                /*
                 * This is an unexpected error. The mount service failed to create, activate and
                 * initialize a virtual volume needed for mounting "local" volumes.
                 */

                Bridge.log(level: .error, "Failed to activate virtual device for local mount")
            } catch .mountingFailed(.initializingVolumeFailed) {
                /*
                 * This is an unexpected error. The mount service failed to connect to the file
                 * system extension to initialize the mounted volume.
                 */

                Bridge.log(level: .error, "Failed to initialize volume")
            } catch .mountingFailed(.mountCommandFailed(.status(let status))) {
                /*
                 * The mount(8) system command called by the mount service on behalf of the user
                 * returned an error.
                 */

                Bridge.log(level: .error, "Failed to mount volume: mount(8) returned \(status)")
            } catch .mountingFailed(.mountCommandFailed(.unknown)) {
                /*
                 * This is an unexpected error. The mount service failed to call the mount(8) system
                 * command on behalf of the user.
                 */

                Bridge.log(level: .error, "Failed to call mount(8)")
            } catch {
                Bridge.log(level: .error, "Failed to mount volume")
            }

            if !quiet {
                let options = Alert.display(
                    header: String(localized: .unexpectedErrorHeader),
                    message: String(
                        localized: .unexpectedErrorMessage(productName: Variant.productName)
                    ),
                    defaultButtonTitle: String(localized: .unexpectedErrorTroubleshooting),
                    alternateButtonTitle: String(localized: .unexpectedErrorCancel)
                )

                switch options {
                case kCFUserNotificationDefaultResponse:
                    NSWorkspace.shared.open(Parameters.troubleshootingURL)
                default:
                    break
                }
            }

            throw .resourceTemporarilyUnavailable
        }

        return .success
    }
}
