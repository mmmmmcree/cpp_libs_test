# deps_vcpkg.cmake — install dependencies via vcpkg manifest mode.
#
# Reads each dep's "name" plus optional "version". When "version" is set, we
# pin via vcpkg's overrides mechanism, which requires a `builtin-baseline`
# (we synthesize it from VCPKG_ROOT's git HEAD). This keeps dependency.json
# the single source of truth for cross-backend version pinning.

function(deps_install_vcpkg DEPS_JSON)
    if(WIN32)
        find_program(VCPKG_EXE vcpkg.exe HINTS "$ENV{VCPKG_ROOT}" NO_DEFAULT_PATH)
    else()
        find_program(VCPKG_EXE vcpkg     HINTS "$ENV{VCPKG_ROOT}" NO_DEFAULT_PATH)
    endif()
    if(NOT VCPKG_EXE)
        message(FATAL_ERROR "DEPS_BACKEND=vcpkg but no vcpkg executable; set VCPKG_ROOT")
    endif()

    if(NOT VCPKG_TARGET_TRIPLET)
        if(MINGW OR (CMAKE_CXX_COMPILER_ID STREQUAL "GNU" AND WIN32))
            set(VCPKG_TARGET_TRIPLET x64-mingw-dynamic CACHE STRING "")
        elseif(WIN32)
            set(VCPKG_TARGET_TRIPLET x64-windows       CACHE STRING "")
        elseif(APPLE)
            set(VCPKG_TARGET_TRIPLET x64-osx           CACHE STRING "")
        else()
            set(VCPKG_TARGET_TRIPLET x64-linux         CACHE STRING "")
        endif()
    endif()

    # Try to obtain a builtin-baseline from VCPKG_ROOT's git HEAD. Required
    # any time we use overrides (which is whenever a dep specifies a version).
    execute_process(
        COMMAND git -C "$ENV{VCPKG_ROOT}" rev-parse HEAD
        OUTPUT_VARIABLE _baseline
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _git_rc
        ERROR_QUIET
    )
    if(NOT _git_rc EQUAL 0)
        set(_baseline "")
    endif()

    string(JSON _len LENGTH "${DEPS_JSON}" dependencies)
    math(EXPR _last "${_len} - 1")

    set(_dep_entries "")
    set(_override_entries "")
    foreach(_i RANGE 0 ${_last})
        string(JSON _name GET "${DEPS_JSON}" dependencies ${_i} name)
        string(JSON _ver  ERROR_VARIABLE _e GET "${DEPS_JSON}" dependencies ${_i} version)
        list(APPEND _dep_entries "    \"${_name}\"")
        if(NOT _e AND _ver)
            if(_baseline)
                list(APPEND _override_entries
                    "    { \"name\": \"${_name}\", \"version\": \"${_ver}\" }")
            else()
                message(WARNING "vcpkg version pin ${_name}=${_ver} ignored: "
                                "VCPKG_ROOT is not a git checkout (no baseline)")
            endif()
        endif()
    endforeach()
    list(REMOVE_DUPLICATES _dep_entries)
    list(JOIN _dep_entries ",\n" _deps_block)

    set(_baseline_field "")
    if(_baseline)
        set(_baseline_field "  \"builtin-baseline\": \"${_baseline}\",\n")
    endif()

    set(_overrides_field "")
    if(_override_entries)
        list(REMOVE_DUPLICATES _override_entries)
        list(JOIN _override_entries ",\n" _ovr_block)
        set(_overrides_field ",\n  \"overrides\": [\n${_ovr_block}\n  ]")
    endif()

    set(_dir "${CMAKE_BINARY_DIR}/_vcpkg_aggregate")
    file(MAKE_DIRECTORY "${_dir}")
    file(WRITE "${_dir}/vcpkg.json"
"{
  \"name\": \"aggregate\",
  \"version-string\": \"0.0.0\",
${_baseline_field}  \"dependencies\": [
${_deps_block}
  ]${_overrides_field}
}
")

    execute_process(
        COMMAND "${VCPKG_EXE}" install
                "--x-manifest-root=${_dir}"
                "--x-install-root=${CMAKE_BINARY_DIR}/vcpkg_installed"
                "--triplet=${VCPKG_TARGET_TRIPLET}"
                "--feature-flags=manifests,versions"
        RESULT_VARIABLE _rc
    )
    if(NOT _rc EQUAL 0)
        message(FATAL_ERROR "vcpkg install failed (rc=${_rc})")
    endif()

    list(APPEND CMAKE_PREFIX_PATH
         "${CMAKE_BINARY_DIR}/vcpkg_installed/${VCPKG_TARGET_TRIPLET}")
    set(CMAKE_PREFIX_PATH "${CMAKE_PREFIX_PATH}" PARENT_SCOPE)
endfunction()
