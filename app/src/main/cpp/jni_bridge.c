#include <android/log.h> // for __android_log_print
#include <jni.h>         // for JNIEnv, jstring, JNIEXPORT, JNICALL
#include <stddef.h>      // for NULL

#include "core.h"

#define LOG_TAG "NativeApp"

/** Capacity of the stack buffer used to build the greeting. */
enum { GREETING_BUF_LEN = 256 };

/** Throws java.lang.IllegalArgumentException; no-op if the class is missing. */
static void throw_iae(JNIEnv *env, const char *msg)
{
    jclass cls = (*env)->FindClass(env, "java/lang/IllegalArgumentException");
    if (cls == NULL) {
        return; // NoClassDefFoundError is already pending
    }
    (void)(*env)->ThrowNew(env, cls, msg);
    (*env)->DeleteLocalRef(env, cls);
}

/**
 * JNI binding for NativeGreeting.format(String).
 *
 * @param env   JNI environment of the calling thread.
 * @param clazz Unused (static method).
 * @param jname Name to greet; null raises IllegalArgumentException.
 * @return New Java string, or NULL with a pending exception on failure.
 */
JNIEXPORT jstring JNICALL
Java_com_example_nativeapp_NativeGreeting_format(JNIEnv *env, jclass clazz, jstring jname)
{
    (void)clazz;

    if (jname == NULL) {
        throw_iae(env, "name must not be null");
        return NULL;
    }

    const char *name = (*env)->GetStringUTFChars(env, jname, NULL);
    if (name == NULL) {
        return NULL; // OutOfMemoryError is pending
    }

    char buf[GREETING_BUF_LEN];
    int rc = nl_format_greeting(buf, sizeof buf, name);
    (*env)->ReleaseStringUTFChars(env, jname, name);

    if (rc < 0) {
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "nl_format_greeting failed: %d", rc);
        throw_iae(env, "name is invalid or too long");
        return NULL;
    }
    return (*env)->NewStringUTF(env, buf);
}
