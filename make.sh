# 建立 build
cd ./extern/llvm
mkdir -p ./llvm-build
cd ./llvm-build
cmake -G "Ninja" ../llvm \
      -DLLVM_ENABLE_PROJECTS="clang;lld" \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_TARGETS_TO_BUILD="X86;ARM"
ninja