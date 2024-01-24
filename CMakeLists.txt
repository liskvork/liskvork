cmake_minimum_required(VERSION 3.0)
project(liskvork
    VERSION 0.1.0
    DESCRIPTION ""
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

add_executable(liskvork ${sources} ${data})

target_compile_options(liskvork PUBLIC -Wall -Wextra -Wconversion)

target_include_directories(liskvork PUBLIC src)

set_target_properties(liskvork PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
)

file(COPY ${data} DESTINATION resources)

###############################################################################
## dependencies ###############################################################
###############################################################################

# No need for anything yet so this can stay here for now

# find_package(Boost 1.36.0 COMPONENTS filesystem system REQUIRED)

# target_link_libraries(example PUBLIC
#   ${Boost_LIBRARIES}
# )

###############################################################################
## testing ####################################################################
###############################################################################

find_package(GTest)

if(GTEST_FOUND)
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
install(DIRECTORY resources DESTINATION ${CMAKE_INSTALL_BINDIR})

set(CPACK_PACKAGE_NAME "liskvork")
set(CPACK_PACKAGE_VERSION ${CMAKE_PROJECT_VERSION})

set(CPACK_PACKAGE_FILE_NAME
    "${CMAKE_PROJECT_NAME}-${CMAKE_PROJECT_VERSION}-${CMAKE_SYSTEM_NAME}-${CMAKE_BUILD_TYPE}-${CMAKE_CXX_COMPILER_ID}-${CMAKE_CXX_COMPILER_VERSION}"
)
set(CPACK_PACKAGE_INSTALL_DIRECTORY "liskvork")
set(CPACK_PACKAGE_CONTACT "Alexandre Flion <huntears@kreog.com>")
set(CPACK_GENERATOR "DEB;RPM")

set(CPACK_MONOLITHIC_INSTALL 1)

include(CPack)
