# deps.cmake — entry point for dependency management.
#
# Public API (intended call order from the top-level CMakeLists):
#
#   add_subdir(<path>)              # register a module subdir
#   add_subdir(<path>)
#   ...
#   install_dependencies()          # walk registered dirs, merge their
#                                   # dependencies.json files, install via
#                                   # vcpkg/conan/fetch backend, populate
#                                   # CMAKE_PREFIX_PATH. Does NOT add_subdirectory.
#   include(<config>)               # any cmake config that calls find_package
#                                   # (window_config, profiling_config, ...)
#   add_pending_subdirs()           # finally, run add_subdirectory() for each
#                                   # registered dir
#
# Backend resolution (highest priority first):
#   1. -DDEPS_BACKEND=<vcpkg|conan|fetch> on the command line
#   2. cacheVariables in the active CMake preset
#   3. unset / "auto" -> environment detection in this order:
#        a. vcpkg  — VCPKG_ROOT env var + vcpkg executable
#        b. conan  — `conan` 2.x on PATH
#        c. fetch  — always available (CMake FetchContent)

include("${CMAKE_CURRENT_LIST_DIR}/deps_vcpkg.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/deps_conan.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/deps_fetch.cmake")

# When ON, the vcpkg backend forces from-source rebuilds (no binary cache)
# and keeps extracted port sources under build/<preset>/vcpkg_installed/
# vcpkg/blds/. Lets you step into vcpkg-built libraries during debugging,
# at the cost of compile time on first configure. Conan/fetch ignore.
option(DEPS_KEEP_SOURCES
    "Force from-source rebuilds and keep extracted port sources under the build dir (vcpkg backend)"
    OFF)

function(add_subdir PATH)
    set_property(GLOBAL APPEND PROPERTY _PROJECT_PENDING_SUBDIRS "${PATH}")
endfunction()

function(_deps_detect_backend OUT_VAR)
    if(DEFINED ENV{VCPKG_ROOT})
        if(WIN32)
            find_program(_v vcpkg.exe HINTS "$ENV{VCPKG_ROOT}" NO_DEFAULT_PATH)
        else()
            find_program(_v vcpkg     HINTS "$ENV{VCPKG_ROOT}" NO_DEFAULT_PATH)
        endif()
        if(_v)
            set(${OUT_VAR} "vcpkg" PARENT_SCOPE)
            return()
        endif()
    endif()

    find_program(_c conan)
    if(_c)
        execute_process(COMMAND ${_c} --version
                        OUTPUT_VARIABLE _ver ERROR_QUIET
                        OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(_ver MATCHES "Conan version 2")
            set(${OUT_VAR} "conan" PARENT_SCOPE)
            return()
        endif()
    endif()

    set(${OUT_VAR} "fetch" PARENT_SCOPE)
endfunction()

function(_deps_dispatch DEPS_JSON)
    string(JSON _len ERROR_VARIABLE _err LENGTH "${DEPS_JSON}" dependencies)
    if(_err OR _len EQUAL 0)
        return()
    endif()

    if(NOT DEPS_BACKEND OR DEPS_BACKEND STREQUAL "auto")
        _deps_detect_backend(_detected)
        set(DEPS_BACKEND "${_detected}" CACHE STRING
            "Dependency backend: vcpkg | conan | fetch | auto" FORCE)
        message(STATUS "Dependency backend : ${DEPS_BACKEND} (auto-detected)")
    else()
        message(STATUS "Dependency backend : ${DEPS_BACKEND} (user-specified)")
    endif()

    if(DEPS_BACKEND STREQUAL "vcpkg")
        deps_install_vcpkg("${DEPS_JSON}")
    elseif(DEPS_BACKEND STREQUAL "conan")
        deps_install_conan("${DEPS_JSON}")
    elseif(DEPS_BACKEND STREQUAL "fetch")
        deps_install_fetch("${DEPS_JSON}")
    else()
        message(FATAL_ERROR "Unknown DEPS_BACKEND: ${DEPS_BACKEND}")
    endif()

    set(CMAKE_PREFIX_PATH "${CMAKE_PREFIX_PATH}" PARENT_SCOPE)
    set(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH}" PARENT_SCOPE)
endfunction()

# install_dependencies()
#   1. Walks each subdir registered via add_subdir(), recursively finds every
#      dependencies.json under it.
#   2. Merges their "dependencies" arrays (dedup by name).
#   3. Calls the active backend (vcpkg/conan/fetch).
# Does NOT call add_subdirectory — that's add_pending_subdirs()'s job.
function(install_dependencies)
    get_property(_dirs GLOBAL PROPERTY _PROJECT_PENDING_SUBDIRS)
    if(NOT _dirs)
        return()
    endif()

    set(_seen_names "")
    set(_deps_inline "")
    foreach(_d IN LISTS _dirs)
        file(GLOB_RECURSE _files
             "${CMAKE_SOURCE_DIR}/${_d}/dependencies.json")
        foreach(_file IN LISTS _files)
            file(READ "${_file}" _content)
            string(JSON _len ERROR_VARIABLE _err
                   LENGTH "${_content}" dependencies)
            if(_err)
                continue()
            endif()
            math(EXPR _last "${_len} - 1")
            foreach(_i RANGE 0 ${_last})
                string(JSON _item GET "${_content}" dependencies ${_i})
                string(JSON _name GET "${_item}" name)
                if(_name IN_LIST _seen_names)
                    continue()
                endif()
                list(APPEND _seen_names "${_name}")
                if(_deps_inline)
                    string(APPEND _deps_inline ",${_item}")
                else()
                    set(_deps_inline "${_item}")
                endif()
            endforeach()
        endforeach()
    endforeach()

    _deps_dispatch("{\"dependencies\":[${_deps_inline}]}")

    # Propagate CMAKE_PREFIX_PATH / CMAKE_MODULE_PATH updates from backend
    # through the function-scope chain to the caller.
    set(CMAKE_PREFIX_PATH "${CMAKE_PREFIX_PATH}" PARENT_SCOPE)
    set(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH}" PARENT_SCOPE)
endfunction()

# add_pending_subdirs()
#   Runs add_subdirectory() for each path registered via add_subdir().
#   Call this AFTER install_dependencies() and AFTER any include(<config>) that
#   calls find_package — so module CMakeLists see fully-resolved deps and
#   shared interface targets.
function(add_pending_subdirs)
    get_property(_dirs GLOBAL PROPERTY _PROJECT_PENDING_SUBDIRS)
    foreach(_d IN LISTS _dirs)
        add_subdirectory(${_d})
    endforeach()
endfunction()
