package com.example.nativeapp;

/**
 * Thin, testable facade over the native library.
 *
 * <p>Kept separate from {@link MainActivity} so instrumentation tests can
 * exercise the JNI boundary without launching an Activity. The class is public
 * because the instrumentation APK accesses it from a different APK.
 */
public final class NativeGreeting {
    static {
        // Loads libnativeapp.so from the APK's lib/<abi>/ directory.
        System.loadLibrary("nativeapp");
    }

    private NativeGreeting() {
    }

    /**
     * Formats a greeting in native code.
     *
     * @param name Non-null name to greet.
     * @return The greeting.
     * @throws IllegalArgumentException if {@code name} is null or too long.
     */
    public static native String format(String name);
}
