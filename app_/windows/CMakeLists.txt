# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(cloud_storage LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "cloud_storage")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# `webview_windows` still uses add_custom_command(TARGET ... DEPENDS ...),
# which newer CMake versions warn about unless CMP0175 is set explicitly.
# Keep legacy behavior here so recent CMake releases stay quiet without
# breaking the plugin build.
if(POLICY CMP0175)
  cmake_policy(SET CMP0175 OLD)
endif()

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

# Reuse a previously downloaded NuGet CLI from the Windows build directory when
# it is available. This avoids repeated "Nuget is not installed" notices from
# `webview_windows` on machines where the plugin already cached `nuget.exe`.
set(_cloud_storage_cached_nuget "${CMAKE_BINARY_DIR}/nuget.exe")
if(EXISTS "${_cloud_storage_cached_nuget}")
  set(NUGET "${_cloud_storage_cached_nuget}")
endif()

# The Firebase C++ SDK bundled with firebase_core still ships a CMake file that
# requests compatibility with versions older than 3.10, which triggers a
# deprecation warning every time CMake configures this project. Silence
# deprecated warnings while configuring Flutter-managed targets (where the
# Firebase SDK is pulled in), then restore the user's preference.
set(_cloud_storage_saved_warn_deprecated "")
if(DEFINED CMAKE_WARN_DEPRECATED)
  set(_cloud_storage_saved_warn_deprecated "${CMAKE_WARN_DEPRECATED}")
endif()
set(CMAKE_WARN_DEPRECATED OFF CACHE BOOL "" FORCE)

add_subdirectory(${FLUTTER_MANAGED_DIR})

if(_cloud_storage_saved_warn_deprecated STREQUAL "")
  unset(CMAKE_WARN_DEPRECATED CACHE)
else()
  set(CMAKE_WARN_DEPRECATED "${_cloud_storage_saved_warn_deprecated}" CACHE BOOL "" FORCE)
endif()

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place inside the build tree so that `flutter run`
# (and Visual Studio) can execute the binary without requiring administrator
# permissions to write into "Program Files". Avoid generator expressions here so
# the directory is computed during configuration time.
set(BUILD_BUNDLE_DIR "${CMAKE_CURRENT_BINARY_DIR}/bundle")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX MATCHES "/Program Files/" OR CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT
    OR CMAKE_INSTALL_PREFIX STREQUAL "${BUILD_BUNDLE_DIR}")
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

# Portable downloads must run without a Visual Studio installation. Use the
# redistributables belonging to this compiler, then install them with the app.
if(MSVC)
  set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP TRUE)
  set(CMAKE_INSTALL_DEBUG_LIBRARIES FALSE)
  set(CMAKE_INSTALL_DEBUG_LIBRARIES_ONLY FALSE)
  include(InstallRequiredSystemLibraries)
  install(FILES ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS}
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    CONFIGURATIONS Profile Release
    COMPONENT Runtime)
endif()

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

set(FIREBASE_APP_ID_JSON_PATH "${CMAKE_CURRENT_SOURCE_DIR}/firebase_app_id_file.json")
if(EXISTS "${FIREBASE_APP_ID_JSON_PATH}")
  set(FIREBASE_APP_ID_TARGET "${CMAKE_CURRENT_BINARY_DIR}/firebase_app_id_file.json")
  configure_file("${FIREBASE_APP_ID_JSON_PATH}" "${FIREBASE_APP_ID_TARGET}" COPYONLY)

  # Ensure the Firebase config ships in the bundle both next to the
  # executable and within the data directory so the firebase_core Windows
  # plugin can discover it regardless of where it looks relative to the
  # running binary.
  install(FILES "${FIREBASE_APP_ID_TARGET}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
  install(FILES "${FIREBASE_APP_ID_TARGET}"
    DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
    COMPONENT Runtime)
else()
  set(FIREBASE_APP_ID_JSON_PATH "")
  message(WARNING "Missing firebase_app_id_file.json; Firebase desktop initialization will fail.")
endif()

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
if(EXISTS "${NATIVE_ASSETS_DIR}")
  install(DIRECTORY "${NATIVE_ASSETS_DIR}"
     DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
     COMPONENT Runtime)
else()
  message(STATUS "No native assets found at ${NATIVE_ASSETS_DIR}; skipping copy.")
endif()

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# After the bundle is staged under `${CMAKE_INSTALL_PREFIX}` replicate it into
# the runner's per-configuration output directory. This ensures
# `build/windows/x64/runner/<config>` always contains the ICU data, Flutter
# engine, assets, and configuration files expected when launching via
# `flutter run -d windows`.
set(_cloud_storage_runner_base "${CMAKE_CURRENT_BINARY_DIR}/runner")
install(CODE "
  if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME OR \"\${CMAKE_INSTALL_CONFIG_NAME}\" STREQUAL \"\")
    set(_cloud_storage_runner_config \"Debug\")
  else()
    set(_cloud_storage_runner_config \"\${CMAKE_INSTALL_CONFIG_NAME}\")
  endif()
  set(_cloud_storage_runner_destination \"${_cloud_storage_runner_base}/\${_cloud_storage_runner_config}\")
  file(REMOVE_RECURSE \"\${_cloud_storage_runner_destination}\")
  file(MAKE_DIRECTORY \"\${_cloud_storage_runner_destination}\")
  execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy_directory
    \"${CMAKE_INSTALL_PREFIX}\" \"\${_cloud_storage_runner_destination}\")
" COMPONENT Runtime)
