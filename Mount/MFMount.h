//
//  MFMount.h
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the
//  file LICENSE.txt.
//

#ifndef MFMOUNT_H
#define MFMOUNT_H

/*!
 * @header MFMount
 *
 * @abstract
 * Provides a C API for mounting FUSE volumes and exchanging FUSE messages with
 * the backend.
 *
 * @discussion
 * The MFMount API defines opaque reference types for channels and messages.
 * A channel is associated with a mounted volume and is used to send and receive
 * FUSE messages. A message body is the serialized FUSE message byte stream.
 * Message bodies may be inspected as one or more body buffers without copying
 * their contents.
 *
 * The backend may also attach a reply buffer to a received message. A reply
 * buffer is transport-provided storage for reply payload bytes. It is not part
 * of the message body and is not included in the message body size.
 *
 * Objects returned from functions whose names contain "Create" or "Copy" are
 * owned by the caller and must be released with MFRelease().
 *
 * @discussion Error Handling
 *
 * Unless otherwise documented, functions that fail return NULL, false, or a
 * negative value as appropriate for the function's return type and set errno to
 * indicate the cause of the failure.
 *
 * Each function documents the errno values it defines. Functions that operate
 * on device-backed channels may also propagate errno values from the underlying
 * system calls named in the function discussion.
 */

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/uio.h>

#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark Reference Types

/*!
 * @typedef MFTypeRef
 *
 * @abstract
 * An opaque reference to an object.
 *
 * @discussion
 * All MFMount reference types are represented as MFTypeRef-compatible opaque
 * references. Objects returned from functions whose names contain "Create" or
 * "Copy" are owned by the caller and must be released with MFRelease().
 */
typedef void *MFTypeRef;

/*!
 * @function MFRetain
 *
 * @abstract
 * Retains a MFMount object.
 *
 * @param reference
 * The object to retain. May not be NULL.
 *
 * @result
 * The retained object reference.
 *
 * @discussion
 * The returned reference must be balanced with a corresponding call to
 * MFRelease().
 *
 * If reference is NULL, this will cause a runtime error and your application
 * will crash.
 */
MFTypeRef _Nonnull MFRetain(MFTypeRef _Nonnull reference);

/*!
 * @function MFRelease
 *
 * @abstract
 * Releases a MFMount object.
 *
 * @param reference
 * The object to release. May not be NULL.
 *
 * @discussion
 * Releases a reference previously returned by a Create, Copy, or Retain
 * function. After the final release, the object is destroyed.
 *
 * If reference is NULL, this will cause a runtime error and your application
 * will crash.
 */

void MFRelease(MFTypeRef _Nonnull reference);

#pragma mark Messages

/*!
 * @typedef MFMessageRef
 *
 * @abstract
 * An opaque reference to a received message.
 *
 * @discussion
 * A message represents one complete FUSE message received from a channel.
 */
typedef MFTypeRef MFMessageRef;

/*!
 * @function MFMessageGetBodySize
 *
 * @abstract
 * Returns the size of a message body in bytes.
 *
 * @param message
 * The message whose body size should be returned. May not be NULL.
 *
 * @result
 * The message body size, in bytes, or -1 if an error occurs.
 *
 * @discussion
 * Returns the size of the serialized FUSE message body in bytes. On failure,
 * this function returns -1 and sets errno as follows:
 *
 * | Value | Description |
 * | --- | --- |
 * | EINVAL | message is NULL or does not identify a valid message object. |
 */
ssize_t MFMessageGetBodySize(MFMessageRef _Nonnull message);

/*!
 * @function MFMessageGetBodyBuffers
 *
 * @abstract
 * Returns the body buffers that make up a message body.
 *
 * @param message
 * The message whose body buffers should be returned. May not be NULL.
 *
 * @param buffers
 * On return, points to an array of struct iovec values representing the message
 * body. May not be NULL.
 *
 * @result
 * The number of body buffers, or -1 if an error occurs.
 *
 * @discussion
 * Each body buffer describes one contiguous byte range of the message body. The
 * first body buffer always contains the structured message data. For FUSE
 * requests this includes the FUSE input header and any fixed-size operation
 * structure, file name, or other structured request fields.
 *
 * A message may include a second body buffer. When present, the second body
 * buffer contains the variable-length operation payload. Payload buffers are
 * intended for raw data that can be passed to the request handler without
 * rewriting or skipping structured request fields. For example, a FUSE write
 * request may use the first body buffer for the FUSE header and write request
 * structure, and the second body buffer for the bytes to write.
 *
 * The complete message body is formed by concatenating the body buffers in
 * array order. Reply buffers are separate from body buffers and are never
 * returned by this function.
 *
 * Messages are never zero-length. On success, this function returns a positive
 * value and stores a non-NULL pointer in buffers.
 *
 * The returned array and the memory referenced by its entries are borrowed from
 * the message and remain valid only while message remains valid. The caller
 * must not modify or free the returned array.
 *
 * On failure, this function returns -1 and sets errno as follows:
 *
 * | Value | Description |
 * | --- | --- |
 * | EINVAL | message is NULL, message does not identify a valid message object, or buffers is NULL. |
 */
ssize_t MFMessageGetBodyBuffers(
    MFMessageRef _Nonnull message,
    const struct iovec * _Nonnull * _Nonnull buffers
);

/*!
 * @function MFMessageGetReplyBuffer
 *
 * @abstract
 * Returns the optional reply buffer associated with a message.
 *
 * @param message
 * The message whose reply buffer should be returned. May not be NULL.
 *
 * @param buffer
 * On return, points to the borrowed reply buffer, or NULL if the message does
 * not have a reply buffer. May not be NULL.
 *
 * @result
 * The size of the reply buffer in bytes, 0 if the message does not have a reply
 * buffer, or -1 if an error occurs.
 *
 * @discussion
 * The returned reply buffer is borrowed from the message and remains valid only
 * while message remains valid. The caller must not free the memory it
 * references.
 *
 * The reply buffer is transport-provided storage for reply payload bytes. It is
 * not part of the serialized message body and is not included in
 * MFMessageGetBodySize().
 *
 * If the message does not have a reply buffer, this function stores NULL in
 * buffer and returns 0.
 *
 * On failure, this function returns -1 and sets errno as follows:
 *
 * | Value | Description |
 * | --- | --- |
 * | EINVAL | message is NULL, message does not identify a valid message object, or buffer is NULL. |
 */
ssize_t MFMessageGetReplyBuffer(
    MFMessageRef _Nonnull message,
    void * _Nullable * _Nonnull buffer
);

#pragma mark Channels

/*!
 * @typedef MFChannelRef
 *
 * @abstract
 * An opaque reference to a MFMount channel.
 *
 * @discussion
 * A channel is a message-oriented communication endpoint.
 */
typedef MFTypeRef MFChannelRef;

/*!
 * @function MFChannelCreate
 *
 * @abstract
 * Creates a new channel.
 *
 * @result
 * A newly created channel, or NULL if the channel could not be created.
 *
 * @discussion
 * A channel created by this function is not associated with a transport until
 * MFMount() succeeds. Channel operations that require a transport may block
 * until the association is complete or the channel is closed.
 *
 * The caller owns the returned channel and must release it with MFRelease().
 * Use MFChannelClose() to close the channel when unmounting the volume.
 *
 * This function has no defined errno failure values.
 */
MFChannelRef _Nullable MFChannelCreate(void);

/*!
 * @function MFChannelCreateWithDeviceFileDescriptor
 *
 * @abstract
 * Creates a channel using an existing device file descriptor.
 *
 * @param fileDescriptor
 * The device file descriptor to use.
 *
 * @result
 * A newly created channel, or NULL if the channel could not be created.
 *
 * @discussion
 * The caller owns the returned channel and must release it with MFRelease().
 *
 * Ownership of the file descriptor is transferred to the channel. The
 * descriptor is closed when the channel is closed. Destroying the channel
 * without closing it can result in undefined behavior.
 *
 * On failure, this function returns NULL and sets errno as follows:
 *
 * | Value | Description |
 * | --- | --- |
 * | EINVAL | fileDescriptor is invalid. |
 *
 * If this function fails, ownership of fileDescriptor remains with the caller.
 *
 * Note: This function will be removed once MFMount() supports mounting volumes
 * using the kernel backend.
 */
MFChannelRef _Nullable MFChannelCreateWithDeviceFileDescriptor(
    int fileDescriptor
);

/*!
 * @function MFChannelGetFileDescriptor
 *
 * @abstract
 * Returns the file descriptor associated with a channel.
 *
 * @param channel
 * The channel whose file descriptor should be returned. May not be NULL.
 *
 * @result
 * The channel's file descriptor, or -1 if the channel has no associated file
 * descriptor or an error occurs.
 *
 * @discussion
 * The returned file descriptor is borrowed. The caller must not close it.
 *
 * On failure, this function returns -1 and sets errno as follows:
 *
 * | Value | Description |
 * | --- | --- |
 * | EINVAL | channel is NULL or does not identify a valid channel object. |
 * | ENOTSUP | channel is not backed by a device file descriptor. |
 */
int MFChannelGetFileDescriptor(MFChannelRef _Nonnull channel);

/*!
 * @typedef MFChannelFlags
 *
 * @abstract
 * Flags that control channel behavior.
 */
typedef CF_OPTIONS(uint32_t, MFChannelFlags) {
    /*!
     * No channel flags are set.
     */
    MFChannelFlagNone = 0,

    /*!
     * The channel operates in non-blocking receive mode.
     *
     * When this flag is set, MFChannelCopyNextMessage() does not block if no
     * complete message is available. Instead, it returns NULL and sets errno to
     * EAGAIN.
     */
    MFChannelFlagNonBlocking = 1 << 0
};

/*!
 * @function MFChannelGetFlags
 *
 * @abstract
 * Returns the current channel flags.
 *
 * @param channel
 * The channel whose flags should be returned. May not be NULL.
 *
 * @param flags
 * On return, contains the current channel flags. May not be NULL.
 *
 * @result
 * true if the flags were returned successfully; otherwise false.
 *
 * @discussion
 * The value stored in flags is a bit mask composed of MFChannelFlag values.
 *
 * On failure, this function returns false and sets errno as follows:
 *
 * | Value | Description |
 * | --- | --- |
 * | EINVAL | channel is NULL, channel does not identify a valid channel object, or flags is NULL. |
 * | ENODEV | channel is closed. |
 *
 * For a device-backed channel, this function may also fail with an errno value
 * returned by fcntl(2) using F_GETFL.
 *
 * The value stored in flags is undefined on failure.
 */
bool MFChannelGetFlags(
    MFChannelRef _Nonnull channel,
    MFChannelFlags * _Nonnull flags
);

/*!
 * @function MFChannelSetFlags
 *
 * @abstract
 * Sets the channel flags.
 *
 * @param channel
 * The channel whose flags should be changed. May not be NULL.
 *
 * @param flags
 * A bit mask composed of MFChannelFlag values.
 *
 * @result
 * true if the flags were set successfully; otherwise false.
 *
 * @discussion
 * This function replaces the channel's current flags with flags.
 *
 * To enable non-blocking receive mode, include MFChannelFlagNonBlocking.
 *
 * On failure, this function returns false and sets errno as follows:
 *
 * | Value | Description |
 * | --- | --- |
 * | EINVAL | channel is NULL, channel does not identify a valid channel object, or flags contains unsupported flag bits. |
 * | ENODEV | channel is closed. |
 *
 * For a device-backed channel, this function may also fail with an errno value
 * returned by fcntl(2) using F_GETFL or F_SETFL.
 */
bool MFChannelSetFlags(MFChannelRef _Nonnull channel, MFChannelFlags flags);

/*!
 * @function MFChannelWaitForNextMessage
 *
 * @abstract
 * Waits until the next complete message is available.
 *
 * @param channel
 * The channel to wait on. May not be NULL.
 *
 * @param timeout
 * The timeout value, in milliseconds. Pass 0 to poll without blocking. Pass a
 * negative value to wait indefinitely.
 *
 * @result
 * A positive value if a complete message is available, 0 if the operation timed
 * out, or -1 if an error occurs.
 *
 * @discussion
 * This function waits for receive-side message availability. After this function
 * reports success, the caller can call MFChannelCopyNextMessage() to retrieve
 * the next complete message.
 *
 * Message availability may change before MFChannelCopyNextMessage() is called,
 * especially when the same channel is used from multiple threads.
 *
 * On failure, this function returns -1 and sets errno as follows:
 *
 * | Value | Description |
 * | --- | --- |
 * | EINVAL | channel is NULL or does not identify a valid channel object. |
 * | EINTR | The wait was interrupted. |
 * | ENODEV | channel is closed. |
 *
 * For a device-backed channel, this function may also fail with an errno value
 * returned by poll(2).
 */
int32_t MFChannelWaitForNextMessage(
    MFChannelRef _Nonnull channel,
    int32_t timeout
);

/*!
 * @function MFChannelCopyNextMessage
 *
 * @abstract
 * Copies the next complete message from a channel.
 *
 * @param channel
 * The channel from which to receive the next FUSE message. May not be NULL.
 *
 * @result
 * A retained message reference, or NULL if an error occurs.
 *
 * @discussion
 * On success, this function returns a retained message reference. The caller
 * owns the returned message and must release it with MFRelease().
 *
 * If no complete message is available, the behavior depends on the channel's
 * blocking mode. In blocking mode, this function waits until a message is
 * available or the channel is interrupted or closed. In non-blocking mode, this
 * function returns NULL and sets errno to EAGAIN.
 *
 * On failure, this function returns NULL and sets errno as follows:
 *
 * | Value | Description |
 * | --- | --- |
 * | EAGAIN | The channel is in non-blocking mode and no complete message is available. |
 * | EINVAL | channel is NULL or does not identify a valid channel object. |
 * | EINTR | The receive operation was interrupted. |
 * | ENODEV | channel is closed. |
 *
 * For a device-backed channel, this function may also fail with an errno value
 * returned by read(2).
 */
MFMessageRef _Nullable MFChannelCopyNextMessage(MFChannelRef _Nonnull channel);

/*!
 * @function MFChannelSendMessage
 *
 * @abstract
 * Sends a FUSE message body on a channel.
 *
 * @param channel
 * The channel on which to send the message. May not be NULL.
 *
 * @param buffers
 * An array of struct iovec values representing the message body. May not be
 * NULL.
 *
 * @param count
 * The number of buffers. Must be greater than 0.
 *
 * @result
 * The number of bytes sent, or -1 if an error occurs.
 *
 * @discussion
 * The buffers array represents one complete serialized message body. The
 * channel preserves the message boundary when sending.
 *
 * The buffers array and the memory it references are not retained by this
 * function and need only remain valid for the duration of the call.
 *
 * On failure, this function returns -1 and sets errno as follows:
 *
 * | Value | Description |
 * | --- | --- |
 * | EINVAL | channel is NULL, channel does not identify a valid channel object, buffers is NULL, or count is 0. |
 * | ENODEV | channel is closed. |
 *
 * For a device-backed channel, this function may also fail with an errno value
 * returned by writev(2).
 */
ssize_t MFChannelSendMessage(
    MFChannelRef _Nonnull channel,
    const struct iovec * _Nonnull buffers,
    size_t count
);

/*!
 * @function MFChannelClose
 *
 * @abstract
 * Closes a channel.
 *
 * @param channel
 * The channel to close. May not be NULL.
 *
 * @result
 * true if the channel was closed successfully; otherwise false.
 *
 * @discussion
 * Closing a channel prevents further message transmission.
 *
 * Calling this function on an already closed channel should be treated as a
 * programming error.
 *
 * On failure, this function returns false and sets errno as follows:
 *
 * | Value | Description |
 * | --- | --- |
 * | EINVAL | channel is NULL or does not identify a valid channel object. |
 *
 * For a device-backed channel, this function may also fail with an errno value
 * returned by close(2).
 */
bool MFChannelClose(MFChannelRef _Nonnull channel);

#pragma mark Volumes

/*!
 * @typedef MFMountResult
 *
 * @abstract
 * A result code indicating whether a mount operation succeeded or why it failed.
 */
typedef CF_ENUM(int32_t, MFMountResult) {
    /*!
     * The volume was mounted successfully.
     */
    MFMountResultSuccess = 0,

    /*!
     * The currently running version of macOS is unsupported.
     */
    MFMountResultUnsupporteOSVersion = 1,

    /*!
     * The required helper tools could not be installed.
     *
     * User action may be required to install or repair the required helper
     * tools.
     */
    MFMountResultHelperToolsInstallationFailed = 2,

    /*!
     * The file system extension could not be found.
     *
     * User action may be required to install or register the file system
     * extension.
     */
    MFMountResultFileSystemExtensionNotFound = 3,

    /*!
     * The file system extension requires user approval.
     *
     * User action is required to enable or approve the file system extension in
     * System Settings.
     */
    MFMountResultFileSystemExtensionRequiresApproval = 4,

    /*!
     * An unexpected failure occurred. errno contains one of the values
     * documented for MFMount().
     */
    MFMountResultUnexpectedFailure = -1
};

/*!
 * @function MFMount
 *
 * @abstract
 * Mounts a volume and associates it with a channel.
 *
 * @param channel
 * The channel to associate with the mounted volume. It is used for sending and
 * receiving FUSE messages. May not be NULL.
 *
 * @param mountPoint
 * The path at which the volume should be mounted. May not be NULL.
 *
 * @param options
 * A comma-separated string containing FUSE mount options. Pass an empty string
 * if no options are required. May not be NULL.
 *
 * @param quiet
 * If true, suppresses user-facing dialogs that would otherwise help the user
 * troubleshoot mount failures or guide the user to perform required setup
 * steps.
 *
 * @result
 * An MFMountResult value indicating whether the volume was mounted successfully
 * or why the mount operation failed.
 *
 * @discussion
 * This function mounts a volume at mountPoint and associates the supplied
 * channel with the volume. The channel may not be closed or released for the
 * lifetime of the mount.
 *
 * If quiet is false, the implementation may present user-facing dialogs to help
 * diagnose or resolve mount issues. If quiet is true, failures are reported
 * only through the return value.
 *
 * If this function returns MFMountResultUnexpectedFailure, it sets errno as
 * follows:
 *
 * | Value | Description |
 * | --- | --- |
 * | EINVAL | channel is NULL, channel does not identify a valid channel object, mountPoint is NULL, or options is NULL. |
 * | EAGAIN | An unexpected failure occurred. |
 *
 * For all other MFMountResult values, errno is not meaningful.
 */
MFMountResult MFMount(
    MFChannelRef _Nonnull channel,
    const char * _Nonnull mountPoint,
    const char * _Nonnull options,
    bool quiet
);

#ifdef __cplusplus
}
#endif

#endif
