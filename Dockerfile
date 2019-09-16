# Start with the latest version of the Ubuntu Docker container
FROM ubuntu:latest

# Run commands that require root authority

# Fetch and install all outstanding updates
RUN apt-get update && apt-get -y upgrade

# Install cmake, git, wget and nano
RUN apt-get install -y cmake git wget nano xz-utils

# Create a user to use so that we don't run it all as root
RUN useradd -d /home/builder -ms /bin/bash -G sudo -p builder builder

# Switch to new user and change to the user's home directory
USER builder
WORKDIR /home/builder

# Create a work directory and switch to it
RUN mkdir build_imx6
WORKDIR build_imx6

#
# The following wget invocation will need to be modified to download a toolchain appropriate 
# for your target device.
#

# Download the WRTNode cross compile toolchain and expand it
RUN wget http://downloads.openwrt.org/releases/18.06.2/targets/imx6/generic/openwrt-sdk-18.06.2-imx6_gcc-7.3.0_musl_eabi.Linux-x86_64.tar.xz
RUN tar -xvf openwrt-sdk-18.06.2-imx6_gcc-7.3.0_musl_eabi.Linux-x86_64.tar.xz

# Download the Azure IoT SDK for C
RUN git clone --recursive https://github.com/azure/azure-iot-sdk-c.git
RUN cd azure-iot-sdk-c

# Download OpenSSL source and expand it
RUN wget https://www.openssl.org/source/openssl-1.1.1c.tar.gz
RUN tar -xvf openssl-1.1.1c.tar.gz

# Download cURL source and expand it
RUN wget http://curl.haxx.se/download/curl-7.60.0.tar.gz
RUN tar -xvf curl-7.60.0.tar.gz

# Download the Linux utilities for libuuid and expand it
RUN wget https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.32/util-linux-2.32-rc2.tar.gz
RUN tar -xvf util-linux-2.32-rc2.tar.gz

#
# Set up environment variables in preparation for the builds to follow
# These will need to be modified for the corresponding locations in the downloaded toolchain
#
ENV WORK_ROOT=/home/builder/build_imx6
ENV TOOLCHAIN_ROOT=${WORK_ROOT}/openwrt-sdk-18.06.2-imx6_gcc-7.3.0_musl_eabi.Linux-x86_64
ENV TOOLCHAIN_SYSROOT=${TOOLCHAIN_ROOT}/staging_dir/toolchain-arm_cortex-a9+neon_gcc-7.3.0_musl_eabi
ENV TOOLCHAIN_EXES=${TOOLCHAIN_SYSROOT}/bin
ENV TOOLCHAIN_NAME=arm-openwrt-linux-muslgnueabi
ENV AR=${TOOLCHAIN_EXES}/${TOOLCHAIN_NAME}-ar
ENV AS=${TOOLCHAIN_EXES}/${TOOLCHAIN_NAME}-as
ENV CC=${TOOLCHAIN_EXES}/${TOOLCHAIN_NAME}-gcc
ENV LD=${TOOLCHAIN_EXES}/${TOOLCHAIN_NAME}-ld
ENV NM=${TOOLCHAIN_EXES}/${TOOLCHAIN_NAME}-nm
ENV RANLIB=${TOOLCHAIN_EXES}/${TOOLCHAIN_NAME}-ranlib

ENV LDFLAGS="-L${TOOLCHAIN_SYSROOT}/lib"
ENV LIBS="-lssl -lcrypto -ldl -lpthread"
ENV TOOLCHAIN_PREFIX=${TOOLCHAIN_SYSROOT}/usr
ENV STAGING_DIR=${TOOLCHAIN_SYSROOT}

# Build OpenSSL
WORKDIR openssl-1.1.1c
RUN ./Configure linux-generic32 shared --prefix=${TOOLCHAIN_PREFIX} --openssldir=${TOOLCHAIN_PREFIX}
RUN make
RUN make install
WORKDIR ..

# Build cURL
WORKDIR curl-7.60.0
RUN ./configure --with-sysroot=${TOOLCHAIN_SYSROOT} --prefix=${TOOLCHAIN_PREFIX} --target=${TOOLCHAIN_NAME} --with-ssl --with-zlib --host=${TOOLCHAIN_NAME} --build=x86_64-pc-linux-uclibc
RUN make
RUN make install
WORKDIR ..

# Build uuid
WORKDIR util-linux-2.32-rc2
RUN ./configure --prefix=${TOOLCHAIN_PREFIX} --with-sysroot=${TOOLCHAIN_SYSROOT} --target=${TOOLCHAIN_NAME} --host=${TOOLCHAIN_NAME} --disable-all-programs  --disable-bash-completion --enable-libuuid
RUN make
RUN make install
WORKDIR ..

# To build the SDK we need to create a cmake toolchain file. This tells cmake to use the tools in the
# toolchain rather than those on the host
WORKDIR azure-iot-sdk-c

# Create a working directory for the cmake operations
RUN mkdir cmake
WORKDIR cmake

# Create a cmake toolchain file on the fly
RUN echo "SET(CMAKE_SYSTEM_NAME Linux)     # this one is important" > toolchain.cmake
RUN echo "SET(CMAKE_SYSTEM_VERSION 1)      # this one not so much" >> toolchain.cmake
RUN echo "SET(CMAKE_SYSROOT ${TOOLCHAIN_SYSROOT})" >> toolchain.cmake
RUN echo "SET(CMAKE_C_COMPILER ${TOOLCHAIN_EXES}/${TOOLCHAIN_NAME}-gcc)" >> toolchain.cmake
RUN echo "SET(CMAKE_CXX_COMPILER ${TOOLCHAIN_EXES}/${TOOLCHAIN_NAME}-g++)" >> toolchain.cmake
RUN echo "SET(CMAKE_FIND_ROOT_PATH $ENV{TOOLCHAIN_SYSROOT})" >> toolchain.cmake
RUN echo "SET(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)" >> toolchain.cmake
RUN echo "SET(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)" >> toolchain.cmake
RUN echo "SET(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)" >> toolchain.cmake
RUN echo "SET(set_trusted_cert_in_samples true CACHE BOOL \"Force use of TrustedCerts option\" FORCE)" >> toolchain.cmake

# Build the SDK. This will use the OpenSSL, cURL and uuid binaries that we built before
RUN cmake -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake -DCMAKE_INSTALL_PREFIX=${TOOLCHAIN_PREFIX} ..
RUN make
RUN make install

# Finally a sanity check to make sure the files are there
RUN ls -al ${TOOLCHAIN_PREFIX}/lib
RUN ls -al ${TOOLCHAIN_PREFIX}/include

# Go to project root
WORKDIR ../..

