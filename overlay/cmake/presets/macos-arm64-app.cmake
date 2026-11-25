# macos-arm64-app: the distributable .app (tools/macos/make_app.sh). Shared
# recomp linkage: the engine carries no game code; the user's disc is
# recompiled into a module on first launch. Same hygiene as
# linux-release-shared: ROM-free icon, no source paths in the binary.
include(${CMAKE_CURRENT_LIST_DIR}/macos-arm64.cmake)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -ffile-prefix-map=${CMAKE_SOURCE_DIR}=openpete -ffile-prefix-map=${CMAKE_BINARY_DIR}=openpete-build")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffile-prefix-map=${CMAKE_SOURCE_DIR}=openpete -ffile-prefix-map=${CMAKE_BINARY_DIR}=openpete-build")
