# deps_vcpkg.cmake — install dependencies via vcpkg manifest mode.
#
# Reads each dep's "name" plus optional "version". When "version" is set, we
# pin via vcpkg's overrides mechanism, which requires a `builtin-baseline`
# (synthesized from the active vcpkg's HEAD/embeddedsha). This keeps
# dependency.json the single source of truth for cross-backend version pinning.
#
# Structure: all platform/compiler/env-specific routing lives in the private
# helpers below. The public deps_install_vcpkg() consumes only normalized
# variables (VCPKG_ROOT_DIR, VCPKG_TARGET_TRIPLET, VCPKG_EXE, VCPKG_BASELINE)
# and otherwise contains no platform conditionals.

# --- Helpers: platform / environment / vcpkg-deployment routing ----------------

# Resolve which vcpkg installation to use. Order:
#   1. -DVCPKG_ROOT_OVERRIDE=<path>           (explicit project override)
#   2. $ENV{VCPKG_ROOT}, unless it's VS-bundled (read-only snapshot under VS).
#   3. Windows persistent VCPKG_ROOT — User scope first (HKCU\Environment),
#      then Machine scope (HKLM\...\Environment). Both bypass VS Dev Cmd's
#      process-env hijack; this is the value the user set in System
#      Properties → Environment Variables.
#   4. The hijacked process VCPKG_ROOT (last-resort fallback).
#   5. vcpkg(.exe) on PATH; its containing directory.
function(_vcpkg_locate_root OUT_VAR)
    if(VCPKG_ROOT_OVERRIDE AND EXISTS "${VCPKG_ROOT_OVERRIDE}")
        set(${OUT_VAR} "${VCPKG_ROOT_OVERRIDE}" PARENT_SCOPE)
        return()
    endif()

    set(_proc "$ENV{VCPKG_ROOT}")
    set(_is_bundled FALSE)
    if(_proc AND EXISTS "${_proc}/vcpkg-bundle.json")
        set(_is_bundled TRUE)
    endif()
    if(_proc AND NOT _is_bundled)
        set(${OUT_VAR} "${_proc}" PARENT_SCOPE)
        return()
    endif()

    if(WIN32)
        # User scope first (personal override beats system-wide), then
        # Machine scope. Both are registry-backed and immune to VS Dev Cmd's
        # process-env modifications.
        foreach(_scope IN ITEMS User Machine)
            execute_process(
                COMMAND powershell -NoProfile -ExecutionPolicy Bypass -Command
                        "[System.Environment]::GetEnvironmentVariable('VCPKG_ROOT','${_scope}')"
                OUTPUT_VARIABLE _persistent_root
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
            )
            if(_persistent_root AND EXISTS "${_persistent_root}")
                if(_is_bundled)
                    message(STATUS
                        "vcpkg: process VCPKG_ROOT='${_proc}' is the VS-bundled "
                        "deployment (read-only). Using ${_scope}-scope VCPKG_ROOT "
                        "'${_persistent_root}' so all presets share one vcpkg.")
                endif()
                set(${OUT_VAR} "${_persistent_root}" PARENT_SCOPE)
                return()
            endif()
        endforeach()
    endif()

    if(_proc)
        set(${OUT_VAR} "${_proc}" PARENT_SCOPE)
        return()
    endif()

    if(WIN32)
        find_program(_v vcpkg.exe)
    else()
        find_program(_v vcpkg)
    endif()
    if(_v)
        get_filename_component(_dir "${_v}" DIRECTORY)
        set(${OUT_VAR} "${_dir}" PARENT_SCOPE)
        return()
    endif()

    set(${OUT_VAR} "" PARENT_SCOPE)
endfunction()

# Pick a default vcpkg triplet from the active CMake compiler / OS. Honors a
# user-supplied VCPKG_TARGET_TRIPLET (cache var or -D) by short-circuiting.
function(_vcpkg_default_triplet OUT_VAR)
    if(MINGW OR (CMAKE_CXX_COMPILER_ID STREQUAL "GNU" AND WIN32))
        set(${OUT_VAR} "x64-mingw-dynamic" PARENT_SCOPE)
    elseif(WIN32)
        set(${OUT_VAR} "x64-windows"       PARENT_SCOPE)
    elseif(APPLE)
        set(${OUT_VAR} "x64-osx"           PARENT_SCOPE)
    else()
        set(${OUT_VAR} "x64-linux"         PARENT_SCOPE)
    endif()
endfunction()

# Resolve the baseline SHA for VCPKG_ROOT_DIR.
#   1. `git rev-parse HEAD` if git is on PATH.
#   2. Read .git/HEAD directly (no git binary needed).
#   3. VS-bundled vcpkg: read `embeddedsha` from vcpkg-bundle.json.
function(_vcpkg_read_baseline VCPKG_ROOT_DIR OUT_VAR)
    set(${OUT_VAR} "" PARENT_SCOPE)

    execute_process(
        COMMAND git -C "${VCPKG_ROOT_DIR}" rev-parse HEAD
        OUTPUT_VARIABLE _sha
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _rc
        ERROR_QUIET
    )
    if(_rc EQUAL 0 AND _sha)
        set(${OUT_VAR} "${_sha}" PARENT_SCOPE)
        return()
    endif()

    set(_bundle "${VCPKG_ROOT_DIR}/vcpkg-bundle.json")
    if(EXISTS "${_bundle}")
        file(READ "${_bundle}" _json)
        string(JSON _sha ERROR_VARIABLE _e GET "${_json}" embeddedsha)
        if(NOT _e AND _sha)
            set(${OUT_VAR} "${_sha}" PARENT_SCOPE)
            return()
        endif()
    endif()

    set(_head "${VCPKG_ROOT_DIR}/.git/HEAD")
    if(NOT EXISTS "${_head}")
        return()
    endif()
    file(READ "${_head}" _content)
    string(STRIP "${_content}" _content)
    if(_content MATCHES "^ref: (.+)$")
        set(_ref "${CMAKE_MATCH_1}")
        set(_loose "${VCPKG_ROOT_DIR}/.git/${_ref}")
        if(EXISTS "${_loose}")
            file(READ "${_loose}" _sha)
            string(STRIP "${_sha}" _sha)
            set(${OUT_VAR} "${_sha}" PARENT_SCOPE)
            return()
        endif()
        set(_packed "${VCPKG_ROOT_DIR}/.git/packed-refs")
        if(EXISTS "${_packed}")
            file(STRINGS "${_packed}" _lines)
            foreach(_line IN LISTS _lines)
                if(_line MATCHES "^([0-9a-f]+) ${_ref}$")
                    set(${OUT_VAR} "${CMAKE_MATCH_1}" PARENT_SCOPE)
                    return()
                endif()
            endforeach()
        endif()
    elseif(_content MATCHES "^[0-9a-fA-F]+$")
        set(${OUT_VAR} "${_content}" PARENT_SCOPE)
    endif()
endfunction()

# --- Main: from here on, only normalized variables are used. -----------------

function(deps_install_vcpkg DEPS_JSON)
    # 1) Normalize all platform/env-specific inputs into uniform variables.
    _vcpkg_locate_root(VCPKG_ROOT_DIR)
    if(NOT VCPKG_ROOT_DIR)
        message(FATAL_ERROR
            "DEPS_BACKEND=vcpkg but no vcpkg installation found. Set "
            "VCPKG_ROOT (User-scope on Windows so it survives VS Dev Cmd), "
            "or pass -DVCPKG_ROOT_OVERRIDE=<path>.")
    endif()
    set(ENV{VCPKG_ROOT} "${VCPKG_ROOT_DIR}") # downstream tools see the resolved one

    if(NOT VCPKG_TARGET_TRIPLET)
        _vcpkg_default_triplet(_t)
        set(VCPKG_TARGET_TRIPLET "${_t}" CACHE STRING "vcpkg target triplet")
    endif()

    if(WIN32)
        find_program(VCPKG_EXE vcpkg.exe HINTS "${VCPKG_ROOT_DIR}" NO_DEFAULT_PATH)
    else()
        find_program(VCPKG_EXE vcpkg     HINTS "${VCPKG_ROOT_DIR}" NO_DEFAULT_PATH)
    endif()
    if(NOT VCPKG_EXE)
        message(FATAL_ERROR "no vcpkg executable under '${VCPKG_ROOT_DIR}'")
    endif()

    _vcpkg_read_baseline("${VCPKG_ROOT_DIR}" VCPKG_BASELINE)
    if(NOT VCPKG_BASELINE)
        message(FATAL_ERROR
            "vcpkg requires a builtin-baseline but couldn't resolve one for "
            "'${VCPKG_ROOT_DIR}'. Tried: `git rev-parse HEAD`, .git/HEAD, "
            "vcpkg-bundle.json's embeddedsha.")
    endif()

    # 2) Build aggregate manifest from DEPS_JSON.
    set(_install_root "${CMAKE_BINARY_DIR}/vcpkg_installed")
    set(_blds_root    "${_install_root}/vcpkg/blds")
    set(_pkgs_root    "${_install_root}/vcpkg/pkgs")
    set(_manifest_dir "${CMAKE_BINARY_DIR}/_vcpkg_aggregate")

    string(JSON _len LENGTH "${DEPS_JSON}" dependencies)
    math(EXPR _last "${_len} - 1")

    set(_dep_entries "")
    set(_override_entries "")
    foreach(_i RANGE 0 ${_last})
        string(JSON _name GET "${DEPS_JSON}" dependencies ${_i} name)
        string(JSON _ver  ERROR_VARIABLE _e GET "${DEPS_JSON}" dependencies ${_i} version)
        list(APPEND _dep_entries "    \"${_name}\"")
        if(NOT _e AND _ver)
            list(APPEND _override_entries
                "    { \"name\": \"${_name}\", \"version\": \"${_ver}\" }")
        endif()
    endforeach()
    list(REMOVE_DUPLICATES _dep_entries)
    list(JOIN _dep_entries ",\n" _deps_block)

    set(_overrides_field "")
    if(_override_entries)
        list(REMOVE_DUPLICATES _override_entries)
        list(JOIN _override_entries ",\n" _ovr_block)
        set(_overrides_field ",\n  \"overrides\": [\n${_ovr_block}\n  ]")
    endif()

    file(MAKE_DIRECTORY "${_manifest_dir}")
    file(WRITE "${_manifest_dir}/vcpkg.json"
"{
  \"name\": \"aggregate\",
  \"version-string\": \"0.0.0\",
  \"builtin-baseline\": \"${VCPKG_BASELINE}\",
  \"dependencies\": [
${_deps_block}
  ]${_overrides_field}
}
")

    # 3) When DEPS_KEEP_SOURCES is ON, surgically remove any top-level dep
    #    whose buildtree source is empty (typical after a binary-cache hit on
    #    a previous configure). vcpkg's "already installed" check would
    #    otherwise skip the install and leave blds/<port>/src/ empty.
    if(DEPS_KEEP_SOURCES)
        foreach(_i RANGE 0 ${_last})
            string(JSON _pname GET "${DEPS_JSON}" dependencies ${_i} name)
            file(GLOB _src "${_blds_root}/${_pname}/src/*")
            if(NOT _src AND IS_DIRECTORY "${_install_root}/vcpkg/info")
                message(STATUS "vcpkg: removing ${_pname} to force "
                               "from-source re-extraction (DEPS_KEEP_SOURCES=ON)")
                execute_process(
                    COMMAND "${VCPKG_EXE}" remove
                            "--x-install-root=${_install_root}"
                            "--triplet=${VCPKG_TARGET_TRIPLET}"
                            "--recurse" "${_pname}"
                )
            endif()
        endforeach()
    endif()

    # 4) Run vcpkg install. Buildtrees and packages live under the install
    #    root for per-preset isolation; downloads stay at vcpkg's default to
    #    keep the source-archive cache shared across presets.
    set(_install_args
        "--x-manifest-root=${_manifest_dir}"
        "--x-install-root=${_install_root}"
        "--x-buildtrees-root=${_blds_root}"
        "--x-packages-root=${_pkgs_root}"
        "--triplet=${VCPKG_TARGET_TRIPLET}"
        "--feature-flags=manifests,versions"
    )
    if(DEPS_KEEP_SOURCES)
        list(APPEND _install_args "--no-binarycaching")
    endif()

    execute_process(
        COMMAND "${VCPKG_EXE}" install ${_install_args}
        RESULT_VARIABLE _rc
    )
    if(NOT _rc EQUAL 0)
        message(FATAL_ERROR "vcpkg install failed (rc=${_rc})")
    endif()

    list(APPEND CMAKE_PREFIX_PATH "${_install_root}/${VCPKG_TARGET_TRIPLET}")
    set(CMAKE_PREFIX_PATH "${CMAKE_PREFIX_PATH}" PARENT_SCOPE)
endfunction()
