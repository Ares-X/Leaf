#pragma once
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#define API __attribute__((visibility("default")))
// All returned byte buffers are malloc-owned. A document stays on one serial worker.
API int lf_abi(void) { return 1; }
