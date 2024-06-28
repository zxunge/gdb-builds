#!/bin/bash

set -eux

GDB_VERSION=14.2
ZSTD_VERSION=1.5.6
GMP_VERSION=6.3.0
MPFR_VERSION=4.2.1
MPC_VERSION=1.3.1
ISL_VERSION=0.26
EXPAT_VERSION=2.6.2
BINUTILS_VERSION=2.42
PYTHON_VERSION=3.8.19
GCC_VERSION=14.1.0
MINGW_VERSION=12.0.0
TARGET=i686-w64-mingw32
NAME=gdb-${GDB_VERSION}-${TARGET}

EXTRA_CRT_ARGS=--disable-lib64
EXTRA_GCC_ARGS="--disable-sjlj-exceptions --with-dwarf2"

function get()
{
  mkdir -p ${SOURCE} && pushd ${SOURCE}
  FILE="${1##*/}"
  if [ ! -f "${FILE}" ]; then
    curl -fL "$1" -o ${FILE}
    case "${1##*.}" in
    gz|tgz)
      tar --warning=none -xzf ${FILE}
      ;;
    bz2)
      tar --warning=none -xjf ${FILE}
      ;;
    xz)
      tar --warning=none -xJf ${FILE}
      ;;
    *)
      exit 1
      ;;
    esac
  fi
  popd
}

# place where source code is downloaded & unpacked
SOURCE=$(pwd)/source

# place where build for specific target is done
BUILD=$(pwd)/build/${TARGET}

# place where build dependencies are installed
PREFIX=$(pwd)/binaries/${TARGET}

# place where bootstrap compiler is built
BOOTSTRAP=$(pwd)/bootstrap/${TARGET}

# final installation folder
FINAL=$(pwd)/${NAME}

get https://ftp.gnu.org/gnu/gdb/gdb-${GDB_VERSION}.tar.xz
get https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz
get https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.xz
get https://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.xz
get https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz
get https://libisl.sourceforge.io/isl-${ISL_VERSION}.tar.xz
get https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION//./_}/expat-${EXPAT_VERSION}.tar.xz
get https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz
get https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
get https://sourceforge.net/projects/mingw-w64/files/mingw-w64/mingw-w64-release/mingw-w64-v${MINGW_VERSION}.tar.bz2
get https://registry.npmmirror.com/-/binary/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz

curl -Lsf "https://sourceware.org/git/?p=binutils-gdb.git;a=patch;h=45e83f865876e42d22cf4bc242725bb4a25a12e3" | patch -t -N -p1 -d ${SOURCE}/gdb-${GDB_VERSION} || true

FOLDER="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

mkdir -p ${BUILD}/x-binutils && pushd ${BUILD}/x-binutils
${SOURCE}/binutils-${BINUTILS_VERSION}/configure \
  --prefix=${BOOTSTRAP}                          \
  --with-sysroot=${BOOTSTRAP}                    \
  --target=${TARGET}                             \
  --disable-plugins                              \
  --disable-nls                                  \
  --disable-shared                               \
  --disable-multilib                             \
  --disable-werror
make -j$(nproc)
make install
popd

mkdir -p ${BUILD}/x-mingw-w64-headers && pushd ${BUILD}/x-mingw-w64-headers
${SOURCE}/mingw-w64-v${MINGW_VERSION}/mingw-w64-headers/configure \
  --prefix=${BOOTSTRAP}                                           \
  --host=${TARGET}
make -j$(nproc)
make install
ln -sTf ${BOOTSTRAP} ${BOOTSTRAP}/mingw
popd

mkdir -p ${BUILD}/x-gcc && pushd ${BUILD}/x-gcc
${SOURCE}/gcc-${GCC_VERSION}/configure \
  --prefix=${BOOTSTRAP}                \
  --with-sysroot=${BOOTSTRAP}          \
  --target=${TARGET}                   \
  --enable-static                      \
  --disable-shared                     \
  --enable-lto                         \
  --disable-nls                        \
  --disable-multilib                   \
  --disable-werror                     \
  --disable-libgomp                    \
  --enable-languages=c,c++             \
  --enable-threads=posix               \
  --enable-checking=release            \
  --enable-large-address-aware         \
  --disable-libstdcxx-pch              \
  --disable-libstdcxx-verbose          \
  ${EXTRA_GCC_ARGS}
make -j$(nproc) all-gcc
make install-gcc
popd

export PATH=${BOOTSTRAP}/bin:$PATH

mkdir -p ${BUILD}/x-mingw-w64-crt && pushd ${BUILD}/x-mingw-w64-crt
${SOURCE}/mingw-w64-v${MINGW_VERSION}/mingw-w64-crt/configure \
  --prefix=${BOOTSTRAP}                                       \
  --with-sysroot=${BOOTSTRAP}                                 \
  --host=${TARGET}                                            \
  --disable-dependency-tracking                               \
  --enable-warnings=0                                         \
  ${EXTRA_CRT_ARGS}
make -j$(nproc)
make install
popd

mkdir -p ${BUILD}/x-mingw-w64-winpthreads && pushd ${BUILD}/x-mingw-w64-winpthreads
${SOURCE}/mingw-w64-v${MINGW_VERSION}/mingw-w64-libraries/winpthreads/configure \
  --prefix=${BOOTSTRAP}                                                         \
  --with-sysroot=${BOOTSTRAP}                                                   \
  --host=${TARGET}                                                              \
  --disable-dependency-tracking                                                 \
  --enable-static                                                               \
  --disable-shared
make -j$(nproc)
make install
popd

mkdir -p ${BUILD}/zstd && pushd ${BUILD}/zstd
cmake ${SOURCE}/zstd-${ZSTD_VERSION}/build/cmake \
  -DCMAKE_BUILD_TYPE=Release                     \
  -DCMAKE_SYSTEM_NAME=Windows                    \
  -DCMAKE_INSTALL_PREFIX=${PREFIX}               \
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER      \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY       \
  -DCMAKE_C_COMPILER=${TARGET}-gcc               \
  -DCMAKE_CXX_COMPILER=${TARGET}-g++             \
  -DZSTD_BUILD_STATIC=ON                         \
  -DZSTD_BUILD_SHARED=OFF                        \
  -DZSTD_BUILD_PROGRAMS=OFF                      \
  -DZSTD_BUILD_CONTRIB=OFF                       \
  -DZSTD_BUILD_TESTS=OFF
make -j$(nproc)
make install
popd

mkdir -p ${BUILD}/gmp && pushd ${BUILD}/gmp
${SOURCE}/gmp-${GMP_VERSION}/configure \
  --prefix=${PREFIX}                   \
  --host=${TARGET}                     \
  --disable-shared                     \
  --enable-static                      \
  --enable-fat
make -j$(nproc)
make install
popd

mkdir -p ${BUILD}/mpfr && pushd ${BUILD}/mpfr
${SOURCE}/mpfr-${MPFR_VERSION}/configure \
  --prefix=${PREFIX}                     \
  --host=${TARGET}                       \
  --disable-shared                       \
  --enable-static                        \
  --with-gmp-build=${BUILD}/gmp
make -j$(nproc)
make install
popd

mkdir -p ${BUILD}/mpc && pushd ${BUILD}/mpc
${SOURCE}/mpc-${MPC_VERSION}/configure \
  --prefix=${PREFIX}                   \
  --host=${TARGET}                     \
  --disable-shared                     \
  --enable-static                      \
  --with-{gmp,mpfr}=${PREFIX}
make -j$(nproc)
make install
popd

mkdir -p ${BUILD}/isl && pushd ${BUILD}/isl
${SOURCE}/isl-${ISL_VERSION}/configure \
  --prefix=${PREFIX}                   \
  --host=${TARGET}                     \
  --disable-shared                     \
  --enable-static                      \
  --with-gmp-prefix=${PREFIX}
make -j$(nproc)
make install
popd

mkdir -p ${BUILD}/expat && pushd ${BUILD}/expat
${SOURCE}/expat-${EXPAT_VERSION}/configure \
  --prefix=${PREFIX}                       \
  --host=${TARGET}                         \
  --disable-shared                         \
  --enable-static                          \
  --without-examples                       \
  --without-tests
make -j$(nproc)
make install
popd

mkdir -p ${BUILD}/python && pushd ${BUILD}/python
${SOURCE}/Python-${PYTHON_VERSION}/configure  \
  --prefix=${FINAL}                    \
  --host=${TARGET}                     \
  --enable-optimizations               \
  --with-lto                           
make -j$(nproc)
make install
popd
  
mkdir -p ${BUILD}/gdb && pushd ${BUILD}/gdb
${SOURCE}/gdb-${GDB_VERSION}/configure \
  --prefix=${FINAL}                    \
  --host=${TARGET}                     \
  --enable-64-bit-bfd                  \
  --disable-werror                     \
  --enable-source-highlight            \
  --with-libexpat-prefix=${PREFIX}     \
  --with-python=${FINAL}               \
  --with-{gmp,mpfr,mpc,isl,zstd}=${PREFIX}
make -j$(nproc)
make install
popd

find ${FINAL} -name '*.exe' -print0 | xargs -0 -n 8 -P 2 ${TARGET}-strip --strip-unneeded
find ${FINAL} -name '*.dll' -print0 | xargs -0 -n 8 -P 2 ${TARGET}-strip --strip-unneeded
find ${FINAL} -name '*.o'   -print0 | xargs -0 -n 8 -P 2 ${TARGET}-strip --strip-unneeded
find ${FINAL} -name '*.a'   -print0 | xargs -0 -n 8 -P $(nproc) ${TARGET}-strip --strip-unneeded

7zr a -mx9 -mqs=on -mmt=on ${FINAL}/${NAME}.7z ${FINAL}

if [[ -v GITHUB_WORKFLOW ]]; then
  echo "OUTPUT_BINARY=${FINAL}/${NAME}.7z" >> $GITHUB_OUTPUT
  echo "RELEASE_NAME=GDB-${GDB_VERSION}" >> $GITHUB_OUTPUT
  echo "GDB_VERSION=${GDB_VERSION}" >> $GITHUB_OUTPUT
  echo "OUTPUT_NAME=${NAME}.7z" >> $GITHUB_OUTPUT
fi
