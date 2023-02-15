WORKDIR=$(pwd)

mkdir -p ./build
cd build
cmake .. -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=1 -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
cd $WORKDIR

