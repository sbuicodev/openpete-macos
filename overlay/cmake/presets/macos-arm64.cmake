# macos-arm64: Apple Silicon only; the Vulkan renderer runs on Metal through
# MoltenVK, loaded directly (core/rhi/rhi_vulkan.c). Cache values live in
# CMakePresets.json: CMAKE_OSX_ARCHITECTURES must be set before project().
include(${CMAKE_CURRENT_LIST_DIR}/_helpers.cmake)
openpete_preset_default(OPENPETE_SKIP_DECOMP ON)
openpete_preset_default(OPENPETE_FUNC_TRACE OFF)
