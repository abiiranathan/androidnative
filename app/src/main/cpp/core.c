#include "core.h"

#include <stdio.h> // for snprintf

int nl_format_greeting(char *out, size_t out_len, const char *name)
{
    if (out == NULL || out_len == 0 || name == NULL) {
        return NL_ERR_INVALID;
    }

    int n = snprintf(out, out_len, "Hello, %s, from C!", name);
    if (n < 0) {
        return NL_ERR_INVALID; // encoding error; out contents are unspecified
    }
    // snprintf returns the length it *wanted* to write; compare as unsigned
    // after the negative check above to detect truncation.
    if ((size_t)n >= out_len) {
        return NL_ERR_TRUNCATED;
    }
    return n;
}
