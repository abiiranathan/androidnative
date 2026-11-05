package com.example.nativeapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

/** On-device test of the JNI boundary. Run with `make connected-test`. */
@RunWith(AndroidJUnit4.class)
public class NativeGreetingTest {
    @Test
    public void formatsGreeting() {
        assertEquals("Hello, Android, from C!", NativeGreeting.format("Android"));
    }

    @Test
    public void rejectsNull() {
        assertThrows(IllegalArgumentException.class, () -> NativeGreeting.format(null));
    }

    @Test
    public void rejectsOverlongName() {
        String overlong = new String(new char[512]).replace('\0', 'x');
        assertThrows(IllegalArgumentException.class, () -> NativeGreeting.format(overlong));
    }
}
