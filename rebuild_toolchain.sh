#!/bin/bash
set -e  # Exit on error

# --- Configuration ---
ROOT_DIR="/scratch/sem26f5"
LLVM_SRC="$ROOT_DIR/llvm-project"
NEWLIB_SRC="$ROOT_DIR/newlib-src"
BUILD_DIR="$ROOT_DIR/llvm-project/build"
INSTALL_DIR="$ROOT_DIR/llvm-project/install_test"
JOBS=$(nproc)

echo "--- 1. Cloning Newlib ---"
if [ ! -d "$NEWLIB_SRC" ]; then
    git clone --depth 1 -b newlib-4.4.0 https://sourceware.org/git/newlib-cygwin.git "$NEWLIB_SRC"
fi

echo "--- 2. Building LLVM/Clang (The Compiler) ---"
mkdir -p "$BUILD_DIR/llvm"
cd "$BUILD_DIR/llvm"
cmake -G Ninja "$LLVM_SRC/llvm" \
    -DCMAKE_BUILD_TYPE="Release" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="RISCV" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="riscv32-unknown-elf" \
    -DLLVM_OPTIMIZED_TABLEGEN=True

ninja -j "$JOBS"
ninja install

# Add the newly built clang to the PATH for the next steps
export PATH="$INSTALL_DIR/bin:$PATH"

echo "--- 3. Building Newlib (The C Library) ---"
mkdir -p "$BUILD_DIR/newlib32"
cd "$BUILD_DIR/newlib32"
"$NEWLIB_SRC/configure" \
    --target=riscv32-unknown-elf \
    --prefix="$INSTALL_DIR" \
    AR_FOR_TARGET="$INSTALL_DIR/bin/llvm-ar" \
    AS_FOR_TARGET="$INSTALL_DIR/bin/llvm-as" \
    LD_FOR_TARGET="$INSTALL_DIR/bin/ld.lld" \
    RANLIB_FOR_TARGET="$INSTALL_DIR/bin/llvm-ranlib" \
    CC_FOR_TARGET="$INSTALL_DIR/bin/clang --target=riscv32-unknown-elf -march=rv32imafd -mno-fdiv"

make -j "$JOBS"
make install

echo "--- 4. Building Compiler-RT (The Runtime) ---"
mkdir -p "$BUILD_DIR/compiler-rt32"
cd "$BUILD_DIR/compiler-rt32"
cmake -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_INSTALL_PREFIX=$("$INSTALL_DIR/bin/clang" -print-resource-dir) \
    -DCMAKE_C_COMPILER="$INSTALL_DIR/bin/clang" \
    -DCMAKE_CXX_COMPILER="$INSTALL_DIR/bin/clang" \
    -DCMAKE_AR="$INSTALL_DIR/bin/llvm-ar" \
    -DCMAKE_NM="$INSTALL_DIR/bin/llvm-nm" \
    -DCMAKE_RANLIB="$INSTALL_DIR/bin/llvm-ranlib" \
    -DCMAKE_C_COMPILER_TARGET="riscv32-unknown-elf" \
    -DCMAKE_CXX_COMPILER_TARGET="riscv32-unknown-elf" \
    -DCMAKE_ASM_COMPILER_TARGET="riscv32-unknown-elf" \
    -DCMAKE_C_FLAGS="-march=rv32imafd -mabi=ilp32d" \
    -DCMAKE_CXX_FLAGS="-march=rv32imafd -mabi=ilp32d" \
    -DCMAKE_ASM_FLAGS="-march=rv32imafd -mabi=ilp32d" \
    -DCMAKE_EXE_LINKER_FLAGS="-nostartfiles -nostdlib -fuse-ld=lld" \
    -DCOMPILER_RT_BAREMETAL_BUILD=ON \
    -DCOMPILER_RT_BUILD_BUILTINS=ON \
    -DCOMPILER_RT_BUILD_MEMPROF=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
    -DCOMPILER_RT_BUILD_PROFILE=OFF \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
    -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCOMPILER_RT_OS_DIR="" \
    -DLLVM_CONFIG_PATH="$INSTALL_DIR/bin/llvm-config" \
    "$LLVM_SRC/compiler-rt"

make -j "$JOBS"
make install

echo "--- ALL DONE ---"
echo "Toolchain installed to: $INSTALL_DIR"