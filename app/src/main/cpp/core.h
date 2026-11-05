#ifndef NATIVEAPP_CORE_H
#define NATIVEAPP_CORE_H

#include <stddef.h> // for size_t

/** Error codes returned by the core API (always negative). */
enum {
    NL_ERR_INVALID   = -1, /**< NULL argument or zero-length buffer. */
    NL_ERR_TRUNCATED = -2, /**< Output buffer too small; result is truncated. */
};

/**
 * Writes a greeting for @p name into @p out.
 *
 * Platform-independent: no JNI or Android dependencies, so it is unit-testable
 * on the host. Thread-safe (no shared state).
 *
 * @param out     Destination buffer. Always NUL-terminated on return when
 *                @p out_len > 0 and @p out is non-NULL.
 * @param out_len Size of @p out in bytes, including the terminator.
 * @param name    NUL-terminated name. Must not be NULL.
 * @return Number of characters written (excluding NUL) on success,
 *         NL_ERR_INVALID on bad arguments, NL_ERR_TRUNCATED if the output
 *         did not fit.
 */
int nl_format_greeting(char *out, size_t out_len, const char *name);

#endif /* NATIVEAPP_CORE_H */
