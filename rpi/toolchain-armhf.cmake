# CMake toolchain for Raspberry Pi 2B (ARMv7 Cortex-A7, hard-float) on Debian armhf.
# Used from inside the chroot created by rpi/setup.sh (crossbuild-essential-armhf
# + multiarch armhf -dev packages), so no separate sysroot is needed.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR armv7l)

set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)

set(CMAKE_FIND_ROOT_PATH /usr/arm-linux-gnueabihf)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

# Multiarch: armhf libraries/pkg-config files live under the triplet paths.
set(CMAKE_LIBRARY_ARCHITECTURE arm-linux-gnueabihf)
set(ENV{PKG_CONFIG_LIBDIR} "/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/share/pkgconfig")

# Lets ps2xTest run on the build host via qemu-user.
set(CMAKE_CROSSCOMPILING_EMULATOR qemu-arm -L /usr/arm-linux-gnueabihf)
