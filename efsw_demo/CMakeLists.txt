cmake_minimum_required(VERSION 3.21)
project(efsw_demo LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(efsw CONFIG REQUIRED)

add_executable(${PROJECT_NAME}
    main.cpp
    src/FileWatcher.cpp
)
target_include_directories(${PROJECT_NAME}
    PRIVATE
        include
)
target_link_libraries(${PROJECT_NAME}
    PRIVATE
        efsw::efsw
)

if(MSVC)
    target_compile_options(${PROJECT_NAME} PRIVATE /W4 /permissive-)
else()
    target_compile_options(${PROJECT_NAME} PRIVATE -Wall -Wextra -Wpedantic)
endif()

set_target_properties(${PROJECT_NAME} PROPERTIES FOLDER demos)

# Deploy runtime DLL deps next to the exe (replaces the package manager's
# auto-deploy hook, which we don't load at the top level). When the target
# links no shared imported libs, $<TARGET_RUNTIME_DLLS:...> is empty and
# we route to `cmake -E true` (silent no-op) to avoid copy_if_different
# erroring on missing source.
if(WIN32)
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E
                $<IF:$<BOOL:$<TARGET_RUNTIME_DLLS:${PROJECT_NAME}>>,copy_if_different,true>
                $<TARGET_RUNTIME_DLLS:${PROJECT_NAME}>
                $<TARGET_FILE_DIR:${PROJECT_NAME}>
        COMMAND_EXPAND_LISTS
    )
endif()

add_custom_target(run_${PROJECT_NAME}
    COMMAND $<TARGET_FILE:${PROJECT_NAME}> "${CMAKE_SOURCE_DIR}"
    DEPENDS ${PROJECT_NAME}
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    USES_TERMINAL VERBATIM
)
