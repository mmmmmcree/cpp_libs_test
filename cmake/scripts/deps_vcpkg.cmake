# deps_vcpkg.cmake — install dependencies via vcpkg manifest mode.
#
# Reads each dep's "name" (versions/git/fetch_target are ignored — vcpkg's
# own port versioning takes precedence; pin via vcpkg-configuration.json
# if you need a specific revision).
#
# Synthesizes ${CMAKE_BINARY_DIR}/_vcpkg_aggregate/vcpkg.json, runs vcpkg
# install, prepends the install dir to CMAKE_PREFIX_PATH.

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

    string(JSON _len LENGTH "${DEPS_JSON}" dependencies)
    math(EXPR _last "${_len} - 1")
    set(_entries "")
    foreach(_i RANGE 0 ${_last})
        string(JSON _name GET "${DEPS_JSON}" dependencies ${_i} name)
        list(APPEND _entries "    \"${_name}\"")
    endforeach()
    list(REMOVE_DUPLICATES _entries)
    list(JOIN _entries ",\n" _block)

    set(_dir "${CMAKE_BINARY_DIR}/_vcpkg_aggregate")
    file(MAKE_DIRECTORY "${_dir}")
    file(WRITE "${_dir}/vcpkg.json"
"{
  \"name\": \"aggregate\",
  \"version-string\": \"0.0.0\",
  \"dependencies\": [
${_block}
  ]
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
