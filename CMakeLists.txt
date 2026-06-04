cmake_minimum_required(VERSION 3.21)

# Load deps before project() so the toolchain (vcpkg.cmake) is set up before
# enable_language() — that's the only way the toolchain's per-target
# applocal-deploy / find_package wrappers can hook into our targets.
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/scripts")
include(deps)

project(cpp_libs_test LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

# Pre-warm Threads while CMAKE_CXX_COMPILER is fresh from project(); some
# vcpkg ports' transitive find_dependency(Threads) chokes on CMake 4.3 RC's
# nested try_compile otherwise.
find_package(Threads)

add_subdir(efsw_demo)
add_subdir(sdl_vulkan_demo)

install_dependencies()
add_pending_subdirs()
