#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

HUNSPELL_SOURCE_DIR="hunspell"
# version will be (e.g.) "1.4.0"
HUNSPELL_VERSION=`sed -n -E 's/#define PACKAGE_VERSION "([0-9])[.]([0-9])[.]([0-9])".*/\1.\2.\3/p' "hunspell/msvc/config.h"`

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

stage="$(pwd)/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

build=${AUTOBUILD_BUILD_ID:=0}
echo "${HUNSPELL_VERSION}.${build}" > "${stage}/VERSION.txt"

apply_patch()
{
    local patch="$1"
    local path="$2"
    echo "Applying $patch..."
    git apply --check --directory="$path" "$patch" && git apply --directory="$path" "$patch"
}

apply_patch "patches/0001-Fix-MSVC-solutions-for-VS2022.patch" "hunspell"

pushd "$HUNSPELL_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            load_vsvars

            msbuild.exe $(cygpath -w 'msvc/Hunspell.sln') /p:Configuration=Debug /p:Platform=$AUTOBUILD_WIN_VSPLATFORM
            msbuild.exe $(cygpath -w 'msvc/Hunspell.sln') /p:Configuration=Release /p:Platform=$AUTOBUILD_WIN_VSPLATFORM

            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then 
                debbitdir=msvc/Debug/libhunspell
                relbitdir=msvc/Release/libhunspell
            else
                debbitdir=msvc/x64/Debug/libhunspell
                relbitdir=msvc/x64/Release/libhunspell
            fi

            cp "$debbitdir".lib "$stage/lib/debug"
            cp "$relbitdir".lib "$stage/lib/release"
        ;;
        darwin*)
            # Setup build flags
            opts="${TARGET_OPTS:--arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE}"
            plainopts="$(remove_cxxstd $opts)"

            # force regenerate autoconf
            autoreconf -fvi

            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$plainopts" CXXFLAGS="$opts" \
                    ../configure --prefix="$stage" --libdir="$stage/lib/release" --enable-static --disable-shared
                make -j$AUTOBUILD_CPU_COUNT
                make install

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make check
                fi
            popd
        ;;
        linux*)
            # Default target per --address-size
            opts="-m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE"
            plainopts="$(remove_cxxstd $opts)"

            # force regenerate autoconf
            autoreconf -fvi

            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$plainopts" CXXFLAGS="$opts" \
                    ../configure --prefix="$stage" --libdir="$stage/lib/release" --enable-static --disable-shared
                make -j$AUTOBUILD_CPU_COUNT
                make install

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make check
                fi
            popd
        ;;
    esac
    mkdir -p "$stage/include/hunspell"
    cp src/hunspell/{*.h,*.hxx} "$stage/include/hunspell"
    mkdir -p "$stage/LICENSES"
    cp "license.hunspell" "$stage/LICENSES/hunspell.txt"
    cp "license.myspell" "$stage/LICENSES/myspell.txt"
popd
