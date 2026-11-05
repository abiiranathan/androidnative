#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "core.h"

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    enum { MAX_NAME_SIZE = 4096, OUTPUT_SIZE = 64 };
    if (size > MAX_NAME_SIZE) {
        return 0;
    }

    char* name = malloc(size + 1);
    if (name == NULL) {
        return 0;
    }
    if (size > 0) {
        memcpy(name, data, size);
    }
    name[size] = '\0';

    char output[OUTPUT_SIZE];
    int result = nl_format_greeting(output, sizeof output, name);

    if (result >= 0) {
        if ((size_t)result >= sizeof output || output[result] != '\0') {
            abort();
        }
    } else if (result == NL_ERR_TRUNCATED && output[sizeof output - 1] != '\0') {
        abort();
    } else if (result != NL_ERR_TRUNCATED && result != NL_ERR_INVALID) {
        abort();
    }

    free(name);
    return 0;
}
