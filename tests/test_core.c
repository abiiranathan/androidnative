#include <stdio.h>  // for fprintf, stderr, puts
#include <string.h> // for strcmp, strlen

#include "core.h"

/** Fails the test (returns 1 from the enclosing function) if cond is false. */
#define CHECK(cond)                                                          \
    do {                                                                     \
        if (!(cond)) {                                                       \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);  \
            return 1;                                                        \
        }                                                                    \
    } while (0)

static int test_ok(void)
{
    char buf[64];
    int n = nl_format_greeting(buf, sizeof buf, "Ada");
    CHECK(n > 0);
    CHECK(strcmp(buf, "Hello, Ada, from C!") == 0);
    CHECK((size_t)n == strlen(buf));
    return 0;
}

static int test_invalid(void)
{
    char buf[8];
    CHECK(nl_format_greeting(NULL, sizeof buf, "x") == NL_ERR_INVALID);
    CHECK(nl_format_greeting(buf, 0, "x") == NL_ERR_INVALID);
    CHECK(nl_format_greeting(buf, sizeof buf, NULL) == NL_ERR_INVALID);
    return 0;
}

static int test_truncation(void)
{
    char buf[8];
    CHECK(nl_format_greeting(buf, sizeof buf, "Ada") == NL_ERR_TRUNCATED);
    CHECK(buf[sizeof buf - 1] == '\0'); // still terminated
    return 0;
}

int main(void)
{
    int failures = test_ok() + test_invalid() + test_truncation();
    puts(failures == 0 ? "all tests passed" : "tests FAILED");
    return failures == 0 ? 0 : 1;
}
