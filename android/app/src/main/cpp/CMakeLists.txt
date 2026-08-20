cmake_minimum_required(VERSION 3.22.1)
project("panghuplayer_native" LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_C_STANDARD 11)

# ===== libass JNI 桥接 =====
#
# libass 依赖链: libass -> freetype + fribidi + harfbuzz
# 编译方式: 使用 build_native_deps.sh 交叉编译所有依赖
# 编译产物放在 android/app/src/main/cpp/libs/<ABI>/
#
# 如果 libs 目录不存在（首次构建或未运行编译脚本），
# 则跳过 libass 编译，仅提供 JNI 桩代码。

set(NATIVE_LIBS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/libs/${ANDROID_ABI}")

# JNI 桥接库（始终编译）
add_library(panghuplayer_jni SHARED
    panghuplayer_jni.cpp
)

# 查找 Android 日志库
find_library(log-lib log)
target_link_libraries(panghuplayer_jni ${log-lib})

# ===== libass 集成 =====
if(EXISTS "${NATIVE_LIBS_DIR}/libass.a")
    message(STATUS "Found libass (static) for ${ANDROID_ABI}, enabling ASS subtitle rendering")

    # 预编译的静态库
    add_library(ass STATIC IMPORTED)
    set_target_properties(ass PROPERTIES
        IMPORTED_LOCATION "${NATIVE_LIBS_DIR}/libass.a")

    add_library(freetype STATIC IMPORTED)
    set_target_properties(freetype PROPERTIES
        IMPORTED_LOCATION "${NATIVE_LIBS_DIR}/libfreetype.a")

    add_library(fribidi STATIC IMPORTED)
    set_target_properties(fribidi PROPERTIES
        IMPORTED_LOCATION "${NATIVE_LIBS_DIR}/libfribidi.a")

    add_library(harfbuzz STATIC IMPORTED)
    set_target_properties(harfbuzz PROPERTIES
        IMPORTED_LOCATION "${NATIVE_LIBS_DIR}/libharfbuzz.a")

    # 头文件路径
    target_include_directories(panghuplayer_jni PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
        "${NATIVE_LIBS_DIR}/include"
    )

    # 链接
    target_link_libraries(panghuplayer_jni
        ass freetype fribidi harfbuzz
        ${log-lib}
    )

    target_compile_definitions(panghuplayer_jni PRIVATE HAS_LIBASS=1)

elseif(EXISTS "${NATIVE_LIBS_DIR}/libass.so")
    message(STATUS "Found libass (dynamic) for ${ANDROID_ABI}, enabling ASS subtitle rendering")

    # 预编译的动态库（如 ChaiChaiEmbyTV 提取的 libass.so，内含 freetype/fribidi/harfbuzz）
    add_library(ass SHARED IMPORTED)
    set_target_properties(ass PROPERTIES
        IMPORTED_LOCATION "${NATIVE_LIBS_DIR}/libass.so")

    # 头文件路径
    target_include_directories(panghuplayer_jni PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
    )

    # 链接动态库
    target_link_libraries(panghuplayer_jni
        ass
        ${log-lib}
    )

    target_compile_definitions(panghuplayer_jni PRIVATE HAS_LIBASS=1)

else()
    message(STATUS "libass not found for ${ANDROID_ABI}, building stub only")
    target_compile_definitions(panghuplayer_jni PRIVATE HAS_LIBASS=0)
endif()
