cmake_minimum_required(VERSION 3.22)
project(unitconverter_native C)

# Build the shared C brain + a thin JNI wrapper into one .so.
#
# convert.c is referenced BY RELATIVE PATH straight out of Examples/UnitConverter/
# shared/c - it is NOT copied. So the Android NDK compiles the exact same bytes
# that the Apple ConvertC SPM package compiles. native-lib.c is the only
# Android-specific code: a JNI shim that forwards into aui_convert.
#
# Path from this file (android/unitconverter/src/main/cpp/) up to the shared dir:
#   ../../../../../shared/c/convert.{c,h}
set(SHARED_C_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../shared/c)

add_library(unitconverter_native SHARED
    native-lib.c
    ${SHARED_C_DIR}/convert.c
)

# Let native-lib.c (and convert.c) find convert.h.
target_include_directories(unitconverter_native PRIVATE ${SHARED_C_DIR})

# Android log lib (used by the JNI wrapper for a one-time load breadcrumb).
find_library(log-lib log)
target_link_libraries(unitconverter_native ${log-lib})
