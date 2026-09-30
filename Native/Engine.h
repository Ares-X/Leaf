#pragma once
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <stdint.h>
#include <limits.h>
#define API __attribute__((visibility("default")))
#define LEAF_MAX_DECODED_BYTES ((size_t)512u*1024u*1024u)
