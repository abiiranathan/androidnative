package com.example.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class KotlinSmokeTest {
    @Test
    fun compilesAndRunsKotlinCode() {
        assertEquals("Hello, Android from Kotlin", kotlinSmokeMessage("Android"))
    }
}
