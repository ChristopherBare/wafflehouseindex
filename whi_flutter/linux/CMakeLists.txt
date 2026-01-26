cmake_minimum_required(VERSION 3.10)
project(whi_flutter LANGUAGES CXX)

set(BINARY_NAME "whi_flutter")
set(APPLICATION_ID "com.example.whi_flutter")

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Configure build options from Flutter tool.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

# Make sure the Flutter tooling directory exists (generated at build time).
add_subdirectory(${FLUTTER_MANAGED_DIR})

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK3 REQUIRED IMPORTED_TARGET gtk+-3.0)

add_definitions(${GTK3_CFLAGS_OTHER})

add_library(${BINARY_NAME}_plugin_registrant STATIC
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)
target_link_libraries(${BINARY_NAME}_plugin_registrant PRIVATE flutter PkgConfig::GTK3)

add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
)

apply_standard_settings(${BINARY_NAME})

target_link_libraries(${BINARY_NAME}
  PRIVATE flutter PkgConfig::GTK3 ${BINARY_NAME}_plugin_registrant
)

set_target_properties(${BINARY_NAME} PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bundle"
)

# The flutter_assemble target no longer exists in modern Flutter.
# Flutter assets are handled differently now.
if(TARGET flutter_assemble)
  add_dependencies(${BINARY_NAME} flutter_assemble)
endif()

# Flutter asset bundling is now handled automatically
# Set the FLUTTER_ASSET_DIR if it exists
if(DEFINED FLUTTER_ASSET_DIR_OUT)
  set(FLUTTER_ASSET_DIR "${FLUTTER_ASSET_DIR_OUT}")
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flutter/ephemeral/flutter_assets")
  set(FLUTTER_ASSET_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter/ephemeral/flutter_assets")
endif()

# Ensure Flutter assets are available
set(FLUTTER_ASSET_DIR_OUT "${CMAKE_CURRENT_BINARY_DIR}/flutter_assets")
set(FLUTTER_ROOT "/home/christopher/development/flutter")
set(FLUTTER_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/flutter/ephemeral/libflutter_linux_gtk.so")
set(FLUTTER_ICU_DATA_FILE "${CMAKE_CURRENT_SOURCE_DIR}/flutter/ephemeral/icudtl.dat")

# Build Flutter assets (skip if flutter command not available)
if(EXISTS "${FLUTTER_ROOT}/bin/flutter")
  add_custom_command(
    OUTPUT ${FLUTTER_ASSET_DIR_OUT}
    COMMAND ${CMAKE_COMMAND} -E env
      ${FLUTTER_TOOL_ENVIRONMENT}
      "${FLUTTER_ROOT}/bin/flutter"
    assemble
    -dTargetPlatform=linux-x64
    -dTargetFile=lib/main.dart
    -dBuildMode=${CMAKE_BUILD_TYPE}
    --output="${FLUTTER_ASSET_DIR_OUT}"
    debug_bundle_linux-x64_assets
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/../pubspec.yaml"
            "${CMAKE_CURRENT_SOURCE_DIR}/../lib/main.dart"
  )
endif()

# Copy the necessary files to the bundle directory after build.
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:${BINARY_NAME}>/data"
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:${BINARY_NAME}>/lib"
)

# Skip copying Flutter assets here - handled by flutter build

# Copy ICU data
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${FLUTTER_ICU_DATA_FILE}"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/data/icudtl.dat"
)

# Copy Flutter library
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${FLUTTER_LIBRARY}"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/lib/libflutter_linux_gtk.so"
)

# Install rules (required by Flutter build process)
# Set a default install prefix that doesn't require root if not specified
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/install" CACHE PATH "Install path prefix" FORCE)
endif()

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

if(DEFINED FLUTTER_ASSET_DIR)
  install(CODE "
    file(REMOVE_RECURSE \"\${CMAKE_INSTALL_PREFIX}/data\")
    " COMPONENT Runtime)

  install(DIRECTORY "${FLUTTER_ASSET_DIR}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/data"
    COMPONENT Runtime)
endif()

# Install the AOT library on non-Debug builds only.
if(DEFINED AOT_LIBRARY AND NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${CMAKE_INSTALL_PREFIX}/lib"
    COMPONENT Runtime)
endif()
