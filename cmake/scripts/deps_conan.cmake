# deps_conan.cmake — install dependencies via Conan 2.x.
#
# Generates a conanfile.txt with `[requires]` from each dep's "name/version",
# runs `conan install` with the CMakeDeps generator, and prepends the
# generated config dir to CMAKE_PREFIX_PATH so find_package(<name> CONFIG)
# resolves to Conan-installed packages.
#
# Caveat: this uses Conan's *default* profile, which must already exist.
# Set up once per machine: `conan profile detect`.

function(deps_install_conan DEPS_JSON)
    find_program(CONAN_EXE conan REQUIRED)

    string(JSON _len LENGTH "${DEPS_JSON}" dependencies)
    math(EXPR _last "${_len} - 1")

    set(_lines "[requires]")
    foreach(_i RANGE 0 ${_last})
        string(JSON _name GET "${DEPS_JSON}" dependencies ${_i} name)
        string(JSON _ver  ERROR_VARIABLE _e GET "${DEPS_JSON}" dependencies ${_i} version)
        if(_e OR NOT _ver)
            list(APPEND _lines "${_name}/[*]")
        else()
            list(APPEND _lines "${_name}/${_ver}")
        endif()
    endforeach()
    list(APPEND _lines "" "[generators]" "CMakeDeps")
    list(JOIN _lines "\n" _content)

    set(_dir         "${CMAKE_BINARY_DIR}/_conan_aggregate")
    set(_install_dir "${CMAKE_BINARY_DIR}/_conan_install")
    file(MAKE_DIRECTORY "${_dir}")
    file(WRITE "${_dir}/conanfile.txt" "${_content}\n")

    execute_process(
        COMMAND ${CONAN_EXE} install "${_dir}"
                --output-folder=${_install_dir}
                --build=missing
        RESULT_VARIABLE _rc
    )
    if(NOT _rc EQUAL 0)
        message(FATAL_ERROR "conan install failed (rc=${_rc})")
    endif()

    list(APPEND CMAKE_PREFIX_PATH "${_install_dir}")
    set(CMAKE_PREFIX_PATH "${CMAKE_PREFIX_PATH}" PARENT_SCOPE)
endfunction()
