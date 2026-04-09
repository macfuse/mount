//
//  Channel.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import AppKit
import Foundation
import OSLog
import System

private func log(level: OSLogType, _ message: String) {
    Logger.mount.log(level: level, "\(message)")
    FileHandle.standardError.write(Data("MFMount: \(message)\n".utf8))
}

@c(MFMount)
public func mount(
    _ mountPoint: UnsafePointer<CChar>!,
    _ options: UnsafePointer<CChar>!,
    _ quiet: Bool,
    _ socket: Int32
) -> Int32 {
    guard #available(macOS 15.4, *) else {
        log(level: .error, "Unsupported version of macOS")
        return -1
    }
    guard let mountPoint else {
        log(level: .error, "Mount point not specified")
        return -1
    }
    guard let options else {
        log(level: .error, "Mount options not specified")
        return -1
    }
    guard socket >= 0, fcntl(socket, F_GETFD) != -1 || errno != EBADF else {
        log(level: .error, "Invalid file descriptor")
        return -1
    }

    let optionsArray = String(cString: options)
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

    while true {
        do throws(Mounter.Error) {
            try Mounter.mount(
                mountPoint: FilePath(platformString: mountPoint),
                options: optionsArray,
                socket: FileDescriptor(rawValue: socket)
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

            log(level: .error, "Failed to install helper tools")
            return 1
        } catch .installingFailed(.unknown) {
            /*
             * This is an unexpected error which is most likely the result of macfuse.app being
             * unable to communicate with its installer XPC service. In case macfuse.app has been
             * damaged, reinstalling macFUSE might help.
             */

            log(level: .error, "Failed to install helper tools")
        } catch .settingPeerCodeSigningRequirementFailed {
            /*
             * This is an unexpected error that is most likely the result of by a malformed or
             * illegal peer code signing requirement string. There is no way for users to resolve
             * this.
             */

            log(level: .error, "Failed to set peer code signing requirements for mount service")
        } catch .decodingReplyFailed {
            /*
             * This is an unexpected error, most likely caused by a version mismatch between the
             * mount service and this framework.
             */

            log(level: .error, "Failed to decode reply from mount service")
        } catch .mountingFailed(.illegalArguments) {
            /*
             * This is an unexpected error, most likely caused by a version mismatch between the
             * mount service and this framework.
             */

            log(level: .error, "Illegal arguments passed to mount service")
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

            log(level: .error, "File system extension not found")
            return 2
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
                     * Note: We could use SMAppService.openSystemSettingsLoginItems() to open System
                     * Settings. However, using the URL below scrolls down to the "Extensions" of the
                     * preference pane.
                     */
                    NSWorkspace.shared.open(Parameters.extensionsSystemSettingsURL)
                case kCFUserNotificationAlternateResponse:
                    NSWorkspace.shared.open(Parameters.gettingStartedURL)
                default:
                    break
                }
            }

            log(level: .error, "File system extension not enabled")
            return 3
        } catch .mountingFailed(.activatingDeviceFailed) {
            /*
             * This is an unexpected error. The mount service failed to create, activate and
             * initialize a virtual volume needed for mounting "local" volumes.
             */

            log(level: .error, "Failed to activate virtual device for local mount")
        } catch .mountingFailed(.initializingVolumeFailed) {
            /*
             * This is an unexpected error. The mount service failed to connect to the file system
             * extension to initialize the mounted volume.
             */

            log(level: .error, "Failed to initialize volume")
        } catch .mountingFailed(.mountCommandFailed(.status(let status))) {
            /*
             * The mount(8) system command called by the mount service on behalf of the user
             * returned an error.
             */

            log(level: .error, "Failed to mount volume: mount(8) returned \(status)")
        } catch .mountingFailed(.mountCommandFailed(.unknown)) {
            /*
             * This is an unexpected error. The mount service failed to call the mount(8) system
             * command on behalf of the user.
             */

            log(level: .error, "Failed to call mount(8)")
        } catch {
            log(level: .error, "Failed to mount volume")
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

        return -1
    }

    return 0
}
