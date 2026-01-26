cmake_minimum_required(VERSION 3.10)

# This file is managed by Flutter tooling and references ephemeral artifacts
# that are generated during the build. It is safe to commit this file, but
# do not edit paths below unless you know what you're doing.

set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")

if(NOT EXISTS "${EPHEMERAL_DIR}/generated_config.cmake")
  message(FATAL_ERROR
    "Generated build files for Flutter Linux are missing.\n"
    "Run 'flutter pub get' then build for linux (e.g., 'flutter run -d linux').")
endif()

include("${EPHEMERAL_DIR}/generated_config.cmake")

set(FLUTTER_LIBRARY "${EPHEMERAL_DIR}/libflutter_linux_gtk.so")
set(FLUTTER_ICU_DATA_FILE "${EPHEMERAL_DIR}/icudtl.dat")
set(FLUTTER_LIBRARY_HEADERS "${EPHEMERAL_DIR}")

# Define a helper to apply standard settings to targets (matches Flutter template behavior).
function(apply_standard_settings TARGET)
  # Determine linkage scope depending on target type
  get_target_property(_type ${TARGET} TYPE)
  if(_type STREQUAL "INTERFACE_LIBRARY")
    set(_scope INTERFACE)
  else()
    set(_scope PRIVATE)
  endif()

  # C++ standard and warnings
  target_compile_features(${TARGET} ${_scope} cxx_std_14)
  if(MSVC)
    target_compile_options(${TARGET} ${_scope} /W4)
  else()
    target_compile_options(${TARGET} ${_scope} -Wall -Wextra -Wpedantic)
  endif()
endfunction()

add_library(flutter INTERFACE)
target_include_directories(flutter INTERFACE
  "${FLUTTER_LIBRARY_HEADERS}"
)
target_link_libraries(flutter INTERFACE
  "${FLUTTER_LIBRARY}"
  dl
  pthread
)

# Provide a nice default set of compiler flags for Flutter targets.
apply_standard_settings(flutter)

# Define the plugin registrant (generated).
set(PLUGIN_REGISTRANT "${CMAKE_CURRENT_SOURCE_DIR}/generated_plugin_registrant.cc")

# Include generated plugins list if present.
if (EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/generated_plugins.cmake")
  include("${CMAKE_CURRENT_SOURCE_DIR}/generated_plugins.cmake")
endif()
