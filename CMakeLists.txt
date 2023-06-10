cmake_minimum_required(VERSION 3.21 FATAL_ERROR)
set(APP_VERSION "0.0.1" CACHE STRING "Application Version" FORCE)

project(nez VERSION ${APP_VERSION}
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

# recursively get all source files.
set(SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src")
file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS "${SOURCE_DIR}/*.cpp")

# Build the "nez" static library
set(LIB_NAME nez)
add_library(${LIB_NAME} STATIC ${SOURCES})
target_include_directories(${LIB_NAME} PRIVATE ${INCLUDE_DIR})
target_compile_features(${LIB_NAME} PRIVATE cxx_std_17)


# Build the emulator executable that statically links to the emulator library.
set(EXE_NAME emu)
add_executable(${EXE_NAME} ${CMAKE_CURRENT_SOURCE_DIR}/emu/main.cpp)
target_include_directories(${EXE_NAME} PUBLIC ${INCLUDE_DIR})
target_include_directories(${EXE_NAME} PRIVATE "ext/SFML/headers")
target_link_libraries(${EXE_NAME} PRIVATE sfml-graphics sfml-window)
target_link_libraries(${EXE_NAME} PRIVATE ${LIB_NAME})
target_compile_features(${EXE_NAME} PRIVATE cxx_std_17)


enable_testing()

set(TEST_DIR tests)
function (TEST_SUITE EXE_NAME TEST_NAME FILE_NAME)
  add_executable(${EXE_NAME} "${TEST_DIR}/${FILE_NAME}")
  target_compile_features(${EXE_NAME} PRIVATE cxx_std_17)
  target_link_libraries(${EXE_NAME} ${PROJECT_NAME})
  target_include_directories(${EXE_NAME} PRIVATE ${INCLUDE_DIR})
  add_test(NAME ${TEST_NAME} COMMAND ${EXE_NAME})
endfunction(TEST_SUITE)

TEST_SUITE(cpu-test "CPU Test" cpu.test.cpp)

