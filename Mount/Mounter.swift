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

/// Installs the helper tools and asks the mount service to mount volumes.
enum Mounter {
    /// An error returned by the install command.
    enum InstallCommandError: Swift.Error {
        /// The command exited with a nonzero status.
        case status(Int32)

        /// The command failed before returning a usable status.
        case unknown
    }

    /// An error returned by the system `mount` command.
    enum MountCommandError: Swift.Error {
        /// The command exited with a nonzero status.
        case status(Int32)

        /// The command failed before returning a usable status.
        case unknown
    }

    /// An error reported by the mount service while mounting a volume.
    enum MountError: Swift.Error {
        /// The mount service rejected the request arguments.
        case illegalArguments

        /// The required file system extension was not found.
        case fileSystemExtensionNotFound

        /// The file system extension requires user approval before it can run.
        case fileSystemExtensionRequiresApproval

        /// The mount service failed to activate the virtual device.
        case activatingDeviceFailed

        /// The mount service failed to initialize the mounted volume.
        case initializingVolumeFailed

        /// The system `mount` command failed.
        case mountCommandFailed(MountCommandError)

        /// The mount service reported an unknown failure.
        case unknown

        /// Creates a mount error from the numeric error values returned by the mount service.
        ///
        /// - Parameters:
        ///   - error: The mount-service error code.
        ///   - mountCommandStatus: The status returned by the system `mount` command.
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

    /// An error thrown while preparing or performing a mount operation.
    enum Error: Swift.Error {
        /// Installing or updating the helper tools failed.
        case installingFailed(InstallCommandError)

        /// The peer code-signing requirement could not be configured on the XPC connection.
        case settingPeerCodeSigningRequirementFailed

        /// The mount service reply could not be decoded.
        case unpackingReplyFailed

        /// The mount service failed to mount the volume.
        case mountingFailed(MountError)
    }

    /// The mount backend used by the mount service.
    enum Backend {
        /// Mount using the FSKit backend and connect through the supplied XPC endpoint.
        case fskit(endpoint: xpc_endpoint_t)

        /// Mount using the kernel backend.
        case kernel
    }

    /// Installs or updates helper components.
    ///
    /// This method runs the application executable with the install command. The application is
    /// responsible for prompting the user for administrator credentials when installation requires
    /// authorization.
    ///
    /// - Parameters:
    ///   - force: A Boolean value that indicates whether installation should be forced.
    ///   - components: The helper components to install.
    /// - Throws: ``InstallCommandError/status(_:)`` if the install command exits with a nonzero
    ///   status, or ``InstallCommandError/unknown`` if the command cannot be run.
    public static func install(
        force: Bool = false,
        components: [String] = ["all"]
    ) throws(InstallCommandError) {
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
            throw .unknown
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw .status(process.terminationStatus)
        }
    }

    /// Creates an XPC connection to the mount service.
    ///
    /// - Returns: An activated XPC connection to the mount service.
    /// - Throws: ``Error/settingPeerCodeSigningRequirementFailed`` if the peer code-signing
    ///   requirement cannot be configured.
    private static func connect() throws(Error) -> xpc_connection_t {
        let connection = xpc_connection_create_mach_service(Variant.mountMachServiceName, nil, 0)

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

    /// Packs a mount request for the mount service.
    ///
    /// - Parameters:
    ///   - backend: The backend to use for the mount.
    ///   - mountPoint: The file system path where the volume should be mounted.
    ///   - options: The mount options to pass to the mount service.
    /// - Returns: An XPC dictionary containing the mount request.
    /// - Throws: ``Error`` if the request cannot be encoded.
    private static func pack(
        backend: Backend,
        mountPoint: FilePath,
        options: [String]
    ) throws(Error) -> xpc_object_t {
        /*
         * Note: The mount API will change in future releases. Use the framework's exported
         * functions instead of calling the XPC API directly.
         */

        let message = xpc_dictionary_create_empty()
        xpc_dictionary_set_string(message, "method", "mount")

        let input = xpc_dictionary_create_empty()
        xpc_dictionary_set_value(message, "input", input)

        switch backend {
        case .fskit(let endpoint):
            xpc_dictionary_set_string(input, "backend", "fskit")
            xpc_dictionary_set_value(input, "endpoint", endpoint)
        case .kernel:
            xpc_dictionary_set_string(input, "backend", "kernel")
        }

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

        return message
    }

    /// Unpacks and validates a mount-service reply.
    ///
    /// - Parameter reply: The XPC reply from the mount service.
    /// - Throws: ``Error/unpackingReplyFailed`` if the reply is malformed, or
    ///   ``Error/mountingFailed(_:)`` if the mount service reports a mount failure.
    private static func unpack(reply: xpc_object_t) throws(Error) {
        /*
         * Note: The mount API will change in future releases. Use the framework's exported
         * functions instead of calling the XPC API directly.
         */

        guard let output = xpc_dictionary_get_dictionary(reply, "output"),
              let e = xpc_dictionary_get_value(output, "error"),
              let s = xpc_dictionary_get_value(output, "mountCommandStatus") else {
            Logger.mount.error("Failed to unpack reply")
            throw .unpackingReplyFailed
        }

        let error = Int32(xpc_int64_get_value(e))
        let mountCommandStatus = Int32(xpc_int64_get_value(s))

        guard error == 0 else {
            throw .mountingFailed(MountError(error: error, mountCommandStatus: mountCommandStatus))
        }
    }

    /// Mounts a volume through the mount service.
    ///
    /// This method installs or updates the helper tools before connecting to the mount service.
    ///
    /// - Parameters:
    ///   - backend: The backend to use for the mount.
    ///   - mountPoint: The file system path where the volume should be mounted.
    ///   - options: The mount options to pass to the mount service.
    /// - Throws: ``Error`` if helper installation, mount-service communication, or mounting fails.
    static func mount(
        backend: Backend,
        mountPoint: FilePath,
        options: [String]
    ) throws(Error) {
        /*
         * Install or update the XPC mount service, if needed. To install or update the launch
         * daemon that provides the mount service, the user needs to enter the password for an
         * account with administrator privileges. By default, the launch daemon is installed or
         * updated when installing a new macFUSE release.
         */

        do {
            try install()
        } catch {
            throw .installingFailed(error)
        }

        /*
         * Connect to mount service over XPC and perform the mount operation. The mount API will
         * change in future releases. Use the framework's exported functions instead of calling the
         * XPC API directly.
         */

        let connection = try connect()

        let message = try pack(
            backend: backend,
            mountPoint: mountPoint,
            options: options,
        )
        let reply = xpc_connection_send_message_with_reply_sync(connection, message)

        try unpack(reply: reply)
    }
}
