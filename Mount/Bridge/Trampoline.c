//
//  Trampoline.c
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the
//  file LICENSE.txt.
//

#include <errno.h>
#include <pthread.h>

#include "MFMount-Swift.h"

#define MFCancelSafe(expression)                                    \
	do {                                                            \
		int oldstate;                                               \
		pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &oldstate);  \
		__auto_type result = (expression);                          \
		int saved_errno = errno;                                    \
		pthread_setcancelstate(oldstate, NULL);                     \
		errno = saved_errno;                                        \
		return result;                                              \
	} while (0)

#define MFCancelSafeVoid(expression)                                \
	do {                                                            \
		int oldstate;                                               \
		pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &oldstate);  \
		(expression);                                               \
		int saved_errno = errno;                                    \
		pthread_setcancelstate(oldstate, NULL);                     \
		errno = saved_errno;                                        \
		return;                                                     \
	} while (0)

MFTypeRef MFRetain(MFTypeRef reference)
{
	MFCancelSafe(_MFRetain(reference));
}

void MFRelease(MFTypeRef reference)
{
	MFCancelSafeVoid(_MFRelease(reference));
}

ssize_t MFMessageGetBodySize(MFMessageRef message)
{
	MFCancelSafe(_MFMessageGetBodySize(message));
}

ssize_t MFMessageGetBodyBuffers(
    MFMessageRef message,
    const struct iovec **buffers
) {
	MFCancelSafe(_MFMessageGetBodyBuffers(message, buffers));
}

ssize_t MFMessageGetReplyBuffer(MFMessageRef message, void **buffer)
{
	MFCancelSafe(_MFMessageGetReplyBuffer(message, buffer));
}

MFChannelRef MFChannelCreate(void)
{
	MFCancelSafe(_MFChannelCreate());
}

MFChannelRef MFChannelCreateWithDeviceFileDescriptor(int fileDescriptor)
{
	MFCancelSafe(_MFChannelCreateWithDeviceFileDescriptor(fileDescriptor));
}

int MFChannelGetFileDescriptor(MFChannelRef channel)
{
	MFCancelSafe(_MFChannelGetFileDescriptor(channel));
}

bool MFChannelGetFlags(MFChannelRef channel, MFChannelFlags *flags)
{
	MFCancelSafe(_MFChannelGetFlags(channel, flags));
}

bool MFChannelSetFlags(MFChannelRef channel, MFChannelFlags flags)
{
	MFCancelSafe(_MFChannelSetFlags(channel, flags));
}

int32_t MFChannelWaitForNextMessage(MFChannelRef channel, int32_t timeout)
{
	MFCancelSafe(_MFChannelWaitForNextMessage(channel, timeout));
}

MFMessageRef MFChannelCopyNextMessage(MFChannelRef channel)
{
	MFCancelSafe(_MFChannelCopyNextMessage(channel));
}

ssize_t MFChannelSendMessage(
    MFChannelRef channel,
    const struct iovec *buffers,
    size_t count
) {
	MFCancelSafe(_MFChannelSendMessage(channel, buffers, count));
}

bool MFChannelClose(MFChannelRef channel)
{
	MFCancelSafe(_MFChannelClose(channel));
}

MFMountResult MFMount(
    MFChannelRef channel,
    const char *mountPoint,
    const char *options,
    bool quiet
) {
	MFCancelSafe(_MFMount(channel, mountPoint, options, quiet));
}
