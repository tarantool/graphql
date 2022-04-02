cmake_minimum_required(VERSION 2.8 FATAL_ERROR)

project(graphql C)

set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})
set(CMAKE_SKIP_INSTALL_ALL_DEPENDENCY TRUE)

# Find Tarantool and Lua dependencies
set(TARANTOOL_FIND_REQUIRED ON)
find_package(Tarantool)
include_directories(${TARANTOOL_INCLUDE_DIRS})

file(GLOB_RECURSE LUA_FILES
  "${CMAKE_CURRENT_SOURCE_DIR}/graphql/*.lua"
)


## VERSION ####################################################################
###############################################################################

execute_process(
  COMMAND git describe --tags --always
  WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
  OUTPUT_STRIP_TRAILING_WHITESPACE
  OUTPUT_VARIABLE GIT_DESCRIBE
  ERROR_QUIET
)

if (NOT GIT_DESCRIBE)
  set(GIT_DESCRIBE "unknown")
endif()

configure_file (
  "${PROJECT_SOURCE_DIR}/graphql/VERSION.lua.in"
  "${CMAKE_CURRENT_BINARY_DIR}/graphql/VERSION.lua"
)


## Testing ####################################################################
###############################################################################

enable_testing()

add_test(
  NAME lint
  COMMAND luacheck .
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

## Install ####################################################################
###############################################################################

install(
  DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_NAME}
  DESTINATION ${TARANTOOL_INSTALL_LUADIR}
  PATTERN "*.in" EXCLUDE
)

install(
  FILES
    ${CMAKE_CURRENT_BINARY_DIR}/graphql/VERSION.lua
  DESTINATION ${TARANTOOL_INSTALL_LUADIR}/${PROJECT_NAME}/
)
