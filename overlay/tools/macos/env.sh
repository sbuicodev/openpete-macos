# Source me: build environment for OpenPete on Apple Silicon macOS.
#   source tools/macos/env.sh
# The repo's scripts assume a Linux userland (bash 4+, GNU sed/grep/find,
# libclang python bindings); this puts Homebrew equivalents first on PATH.
_op_root="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/../.." && pwd)"
_brew=/opt/homebrew
export PATH="$_op_root/.venv-macos/bin:$_brew/bin:$_brew/opt/gnu-sed/libexec/gnubin:$_brew/opt/coreutils/libexec/gnubin:$_brew/opt/findutils/libexec/gnubin:$_brew/opt/grep/libexec/gnubin:$_brew/opt/gawk/libexec/gnubin:$PATH"
export OPENPETE_LIBCLANG="$_op_root/.venv-macos/lib/python3.14/site-packages/clang/native/libclang.dylib"
export OPENPETE_NO_COMMITS=1
# Oldest macOS the .app supports; every binary it ships is built for it.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
export CMAKE_PREFIX_PATH="$_brew/opt/openal-soft${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
unset _op_root _brew
