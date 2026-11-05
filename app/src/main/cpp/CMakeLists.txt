cmake_minimum_required(VERSION 3.22.1)
project(nativeapp C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# core.c is platform-independent; jni_bridge.c is the only Android-specific file.
add_library(nativeapp SHARED core.c jni_bridge.c)

target_compile_options(nativeapp PRIVATE -Wall -Wextra -Werror -fvisibility=hidden)
target_link_libraries(nativeapp PRIVATE log)
# max-page-size=16384: required for 16 KB-page devices (Android 15+) on NDK r27.
target_link_options(nativeapp PRIVATE -Wl,--no-undefined -Wl,-z,max-page-size=16384)
