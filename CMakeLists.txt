cmake_minimum_required(VERSION 3.13 FATAL_ERROR)
set(APP_VERSION "0.0.1" CACHE STRING "Application Version" FORCE)

project(mos_6502_emu VERSION ${APP_VERSION}
        DESCRIPTION "An emulator for the MOS 6502 processor"
        LANGUAGES CXX)

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
target_compile_features(${CLI_NAME} PRIVATE cxx_std_17)

