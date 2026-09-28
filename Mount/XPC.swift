//
//  XPC.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import OSLog
import Security
import System
import XPC

enum XPC {
    /// Verifies the code signature of the peer associated with an XPC message.
    ///
    /// The peer must have a valid signature issued to the macFUSE development team. This check
    /// authenticates the peer associated with `message`. It does not validate later messages on
    /// the same connection.
    ///
    /// - Parameter message: A received XPC dictionary from a peer connection.
    /// - Throws: `Errno.permissionDenied` if the peer cannot be identified, the signature
    ///   requirement cannot be created, or the peer does not satisfy the requirement.
    static func verifyPeer(from message: xpc_object_t) throws(Errno) {
        var code: SecCode?

        let codeStatus = SecCodeCreateWithXPCMessage(message, SecCSFlags(), &code)
        guard codeStatus == errSecSuccess, let code else {
            Logger.mount.error("Failed to identify peer: \(codeStatus)")
            throw .permissionDenied
        }

        let text = """
            anchor apple generic and \
            certificate leaf[subject.OU] = "\(Variant.developmentTeam)"
            """
        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(
            text as CFString,
            SecCSFlags(),
            &requirement
        )
        guard requirementStatus == errSecSuccess, let requirement else {
            Logger.mount.error("Failed to create peer requirement: \(requirementStatus)")
            throw .permissionDenied
        }

        let status = SecCodeCheckValidity(code, SecCSFlags(), requirement)
        guard status == errSecSuccess else {
            Logger.mount.error("Peer signature is invalid: \(status)")
            throw .permissionDenied
        }
    }
}
