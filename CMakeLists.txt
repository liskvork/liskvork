cmake_minimum_required(VERSION 3.13)

option(USE_CLANG "Build application with clang" ON)
option(STATIC "Build the binary statically" OFF)

message(STATUS "Linking statically: ${STATIC}")

if (USE_CLANG)
    find_program(CLANG_EXECUTABLE clang REQUIRED)
    set(CMAKE_C_COMPILER ${CLANG_EXECUTABLE})

    find_program(CLANGPP_EXECUTABLE clang++ REQUIRED)
    set(CMAKE_CXX_COMPILER ${CLANGPP_EXECUTABLE})
endif()

project(liskvork
    VERSION 0.1.1
    DESCRIPTION "Linux native gomoku manager"
    HOMEPAGE_URL "https://gitlab.com/huntears/liskvork"
    LANGUAGES CXX
)

###############################################################################
## file globbing ##############################################################
###############################################################################

file(GLOB_RECURSE sources src/*.cpp src/*.hpp)
file(GLOB_RECURSE sources_test test/*.cpp test/*.hpp)
file(GLOB_RECURSE data resources/*)

###############################################################################
## target definitions #########################################################
###############################################################################

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(CheckIPOSupported)
check_ipo_supported(RESULT ipo_supported OUTPUT ipo_error)

add_executable(liskvork ${sources} ${data})

if (CMAKE_BUILD_TYPE MATCHES Release)
    if (ipo_supported)
        message(STATUS "IPO / LTO enabled")
        set_property(TARGET liskvork PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
    else ()
        message(WARNING "IPO / LTO not supported: <${ipo_error}>")
    endif ()
endif ()

if (STATIC)
    set_target_properties(liskvork PROPERTIES LINK_SEARCH_START_STATIC 1)
    set_target_properties(liskvork PROPERTIES LINK_SEARCH_END_STATIC 1)
    set(CMAKE_FIND_LIBRARY_SUFFIXES ".a")

    # set(CMAKE_EXE_LINKER_FLAGS "-static-libgcc -static-libstdc++")
    set(CMAKE_EXE_LINKER_FLAGS "-static")
endif ()

target_compile_options(liskvork PUBLIC -Wall -Wextra -Wconversion)

target_include_directories(liskvork PUBLIC src)

set_target_properties(liskvork PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
)

target_compile_definitions(liskvork PUBLIC PROGRAM_VERSION="${CMAKE_PROJECT_VERSION}")

file(COPY ${data} DESTINATION resources)

###############################################################################
## dependencies ###############################################################
###############################################################################

include(FetchContent)

set(FETCHCONTENT_QUIET OFF)

FetchContent_Declare(
    yaml-cpp
    GIT_REPOSITORY https://github.com/jbeder/yaml-cpp.git
    GIT_TAG yaml-cpp-0.7.0
    GIT_PROGRESS TRUE
    GIT_SHALLOW TRUE
)

FetchContent_Declare(
    argparse
    GIT_REPOSITORY https://github.com/p-ranav/argparse.git
    GIT_TAG v2.9
    GIT_PROGRESS TRUE
    GIT_SHALLOW TRUE
)

FetchContent_Declare(
    spdlog
    GIT_REPOSITORY https://github.com/gabime/spdlog.git
    GIT_TAG v1.11.0
    GIT_PROGRESS TRUE
    GIT_SHALLOW TRUE
)

FetchContent_MakeAvailable(
    yaml-cpp
    argparse
    spdlog
)

target_link_libraries(liskvork PUBLIC
  argparse
  yaml-cpp
  spdlog::spdlog
)

###############################################################################
## testing ####################################################################
###############################################################################

find_package(GTest)

if(GTEST_FOUND AND NOT STATIC)
  add_executable(unit_tests ${sources_test} ${sources})

  target_compile_definitions(unit_tests PUBLIC UNIT_TESTS)

  # this allows us to use our executable as a link library
  # therefore we can inherit all compiler options and library dependencies
  set_target_properties(liskvork PROPERTIES ENABLE_EXPORTS on)

  target_link_libraries(unit_tests
    ${GTEST_BOTH_LIBRARIES}
    liskvork
  )
endif()

###############################################################################
## packaging ##################################################################
###############################################################################

include(GNUInstallDirs)

install(TARGETS liskvork
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
# install(DIRECTORY resources DESTINATION ${CMAKE_INSTALL_BINDIR})

set(CPACK_PACKAGE_NAME "liskvork")
set(CPACK_PACKAGE_VERSION ${CMAKE_PROJECT_VERSION})

execute_process(
        COMMAND git log -1 --format=%h
        WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
        OUTPUT_VARIABLE GIT_HASH
        OUTPUT_STRIP_TRAILING_WHITESPACE
)

set(CPACK_PACKAGE_FILE_NAME
    "${CMAKE_PROJECT_NAME}-${CMAKE_PROJECT_VERSION}-${GIT_HASH}-${CMAKE_SYSTEM_NAME}-${CMAKE_BUILD_TYPE}-${CMAKE_CXX_COMPILER_ID}-${CMAKE_CXX_COMPILER_VERSION}"
)
set(CPACK_PACKAGE_INSTALL_DIRECTORY "liskvork")
set(CPACK_PACKAGE_CONTACT "Alexandre Flion <huntears@kreog.com>")
set(CPACK_GENERATOR "DEB;RPM")

set(CPACK_MONOLITHIC_INSTALL 1)

include(CPack)
