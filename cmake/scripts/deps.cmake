# deps.cmake — entry point.
# Public API: deps_install("<json>")
#   <json> is a JSON object: { "dependencies": [ { "name": "...", ... }, ... ] }
#
# Backend resolution (highest priority first):
#   1. -DDEPS_BACKEND=<vcpkg|conan|fetch> on the command line
#   2. cacheVariables in the active CMake preset
#      (CMakePresets.json's _base sets DEPS_BACKEND=auto, individual presets
#       may override with a concrete backend name)
#   3. unset / "auto" -> environment detection in this order:
#        a. vcpkg  — VCPKG_ROOT env var + vcpkg executable
#        b. conan  — `conan` 2.x on PATH
#        c. fetch  — always available (CMake FetchContent)

include("${CMAKE_CURRENT_LIST_DIR}/deps_vcpkg.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/deps_conan.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/deps_fetch.cmake")

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

function(deps_install DEPS_JSON)
    string(JSON _len ERROR_VARIABLE _err LENGTH "${DEPS_JSON}" dependencies)
    if(_err OR _len EQUAL 0)
        return()
    endif()

    # Treat unset and the explicit "auto" sentinel the same: run detection.
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

    # Propagate any CMAKE_PREFIX_PATH update from the backend.
    set(CMAKE_PREFIX_PATH "${CMAKE_PREFIX_PATH}" PARENT_SCOPE)
endfunction()



# install_dependencies()
# 1. Walks each subdir registered via add_subdir(), recursively finds every
#    dependencies.json under it.
# 2. Merges their "dependencies" arrays (dedup by name).
# 3. Calls deps_install() which dispatches to vcpkg / conan / fetch.
# 4. Performs the real add_subdirectory() for each registered subdir.
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

    deps_install("{\"dependencies\":[${_deps_inline}]}")

    foreach(_d IN LISTS _dirs)
        add_subdirectory(${_d})
    endforeach()
endfunction()