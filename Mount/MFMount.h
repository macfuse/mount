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

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int MFMount(const char *mountpoint, const char *options, bool quiet, int socket);

#ifdef __cplusplus
}
#endif

#endif
