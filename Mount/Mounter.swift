//
//  Mounter.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import Foundation
import OSLog
import System
import XPC

internal enum Mounter {
    internal enum InstallCommandError: Swift.Error {
        case status(Int32)
        case unknown
    }

    internal enum MountCommandError: Swift.Error {
        case status(Int32)
        case unknown
    }

    internal enum MountError: Swift.Error {
        case illegalArguments
        case fileSystemExtensionNotFound
        case fileSystemExtensionRequiresApproval
        case activatingDeviceFailed
        case initializingVolumeFailed
        case mountCommandFailed(MountCommandError)
        case unknown

        init(error: Int32, mountCommandStatus: Int32) {
            self = switch error {
            case 1:
                .illegalArguments
            case 2:
                .fileSystemExtensionNotFound
            case 3:
                .fileSystemExtensionRequiresApproval
            case 4:
                .activatingDeviceFailed
            case 5:
                .initializingVolumeFailed
            case 6:
                .mountCommandFailed(.status(mountCommandStatus))
            case 7:
                .mountCommandFailed(.unknown)
            default:
                .unknown
            }
        }
    }

    internal enum Error: Swift.Error {
        case installingFailed(InstallCommandError)
        case settingPeerCodeSigningRequirementFailed
        case decodingReplyFailed
        case mountingFailed(MountError)
    }
}

extension Mounter {
    public static func install(force: Bool = false, components: [String] = ["all"]) throws(Error) {
        guard let executableURL = Bundle.app.executableURL else {
            fatalError()
        }

        var arguments = ["install"]

        if force {
            arguments.append("--force")
        }

        arguments.append("--components")
        arguments.append(contentsOf: components)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        do {
            try process.run()
        } catch {
            throw .installingFailed(.unknown)
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw .installingFailed(.status(process.terminationStatus))
        }
    }
}

extension Mounter {
    private static func connect() throws(Error) -> xpc_connection_t {
        let connection = xpc_connection_create_mach_service(Variant.mountMachService, nil, 0)

        guard xpc_connection_set_peer_code_signing_requirement(
            connection,
            """
            anchor apple generic and \
            certificate leaf[subject.OU] = "\(Variant.developmentTeam)"
            """
        ) == 0 else {
            Logger.mount.error("Failed to set peer code signing requirement")
            throw .settingPeerCodeSigningRequirementFailed
        }

        xpc_connection_set_event_handler(connection) { _ in }
        xpc_connection_activate(connection)

        return connection
    }

    private static func pack(
        mountPoint: FilePath,
        options: [String],
        socket: FileDescriptor
    ) throws(Error) -> xpc_object_t {
        /*
         * Note: The mount API will change in future releases. Use the framework's exported
         * functions instead of calling the XPC API directly.
         */

        let message = xpc_dictionary_create_empty()
        xpc_dictionary_set_string(message, "method", "mount")

        let input = xpc_dictionary_create_empty()
        xpc_dictionary_set_value(message, "input", input)

        mountPoint.withPlatformString {
            xpc_dictionary_set_string(input, "mountPoint", $0)
        }

        xpc_dictionary_set_value(
            input,
            "options",
            options.reduce(into: xpc_array_create_empty()) {
                xpc_array_set_string($0, XPC_ARRAY_APPEND, $1)
            }
        )

        xpc_dictionary_set_fd(input, "socket", socket.rawValue)

        return message
    }

    private static func unpack(reply: xpc_object_t) throws(Error) {
        /*
         * Note: The mount API will change in future releases. Use the framework's exported
         * functions instead of calling the XPC API directly.
         */

        guard let output = xpc_dictionary_get_dictionary(reply, "output"),
              let e = xpc_dictionary_get_value(output, "error"),
              let s = xpc_dictionary_get_value(output, "mountCommandStatus") else {
            Logger.mount.error("Failed to unpack reply")
            throw .decodingReplyFailed
        }

        let error = Int32(xpc_int64_get_value(e))
        let mountCommandStatus = Int32(xpc_int64_get_value(s))

        guard error == 0 else {
            throw .mountingFailed(MountError(error: error, mountCommandStatus: mountCommandStatus))
        }
    }
}

extension Mounter {
    internal static func mount(
        mountPoint: FilePath,
        options: [String],
        socket: FileDescriptor
    ) throws(Error) {
        /*
         * Install or update the XPC mount service, if needed. To install or update the launch
         * daemon that provides the mount service, the user needs to enter the password for an
         * account with administrator privileges. By default, the launch daemon is installed or
         * updated when installing a new macFUSE release.
         */

        try install()

        /*
         * Connect to mount service over XPC and perform the mount operation. The mount API will
         * change in future releases. Use the framework's exported functions instead of calling the
         * XPC API directly.
         */

        let connection = try connect()

        let message = try pack(mountPoint: mountPoint, options: options, socket: socket)
        let reply = xpc_connection_send_message_with_reply_sync(connection, message)

        try unpack(reply: reply)
    }
}
