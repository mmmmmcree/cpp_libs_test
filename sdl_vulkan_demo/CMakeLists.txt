cmake_minimum_required(VERSION 3.21)
project(sdl_vulkan_demo LANGUAGES CXX)

find_package(SDL3   CONFIG REQUIRED)
find_package(Vulkan REQUIRED)

add_executable(${PROJECT_NAME} main.cpp)
target_link_libraries(${PROJECT_NAME} PRIVATE SDL3::SDL3 Vulkan::Vulkan)
set_target_properties(${PROJECT_NAME} PROPERTIES FOLDER demos)
