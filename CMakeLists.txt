cmake_minimum_required(VERSION 3.21 FATAL_ERROR)
set(APP_VERSION "0.0.1" CACHE STRING "Application Version" FORCE)

project(mos_6502_emu VERSION ${APP_VERSION}
        DESCRIPTION "An emulator for the MOS 6502 processor"
        LANGUAGES CXX)

add_subdirectory("ext/SFML")

set(SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)
file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS ${SOURCE_DIR}/*.cpp)
set(INCLUDE_DIR include/)

if (UNIX AND NOT APPLE)
  set(LINUX true)
endif()

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug)
endif()

set(CLI_NAME emu)
add_executable(${CLI_NAME} src/main.cpp)
target_include_directories(${CLI_NAME} PUBLIC ${INCLUDE_DIR})
target_include_directories(${CLI_NAME} PRIVATE "ext/SFML/headers")
target_link_libraries(${CLI_NAME} PRIVATE sfml-graphics sfml-window)
target_compile_features(${CLI_NAME} PRIVATE cxx_std_17)

