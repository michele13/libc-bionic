#!/bin/bash
set -e

scriptdir="$(cd "$(dirname "$0")"; pwd)"
topdir="`pwd`/android_build"

googlebaseurl='https://android.googlesource.com/platform'

sources=('bionic' 'libnativehelper' 'build' 'build/soong' 'build/blueprint' 'build/kati' 'system/core' 'system/extras' 'external/jemalloc' 'external/libcxx' 'external/libcxxabi' 'external/elfutils' 'external/golang-protobuf'
         'external/llvm' 'external/libunwind_llvm' 'external/compiler-rt' 'external/google-benchmark' 'external/tinyxml2')
: ${buildref='android-10.0.0_r2'}
: ${arch:=`uname -m`}
: ${skipsrc:='no'}
: ${skipndk:='no'}
# benchmarks are broken right now
: ${skipbenches:='yes'}
# zlib IS required for building
: ${skipzlib:='no'}
# skip patch apply
: ${skippatch:='yes'}
# continue download of sources (or start from scratch)?
: ${continuedl:='no'}
ndkarch=$arch
gccarch=$arch
luncharch=$arch
gccver=4.9

abi="$arch-linux-android"

case $arch in
    x86) abi='x86_64-linux-android'; ndkarch='x86_64';;
    arm) abi+='eabi';;
    x86_64) gccarch='x86';;
    aarch64) ndkarch='arm64'; luncharch='arm64';;
esac

clangver=3.6
prebuilts=( "prebuilts/gcc/linux-x86/$gccarch/$abi-$gccver" "prebuilts/gcc/linux-x86/host/`uname -m`-linux-glibc2.17-4.8"
            'prebuilts/clang/host/linux-x86' 'prebuilts/gcc/linux-x86/host/x86_64-w64-mingw32-4.8' 'prebuilts/misc' 'prebuilts/go/linux-x86'
            'prebuilts/build-tools' 'prebuilts/vndk/v28')

dl_complete() {
# is the package in the list of the ones already downloaded?
grep -q "$1" "$topdir/.dl_done"

# output the exit status of the previous command (0) if successful. This means that the source is already there
echo $?
}

# I don't want to restart the script everytime it fails to download something, just keep trying until you succeed
git_fetch() {

git fetch --depth 1 origin "$2" -q || git_fetch

}

download_from_git () {
    
    # Create an empty .dl_done file
    touch $topdir/.dl_done
    
    # we want to be sure that download starts from scratch, 
    if [ "$continuedl" == "no" ]; then rm "$topdir/.dl_done"; fi
    
    # if continuedl is set to 'no' we download everything from zero.
    # Otherwise we check if the source is already downloaded, if not we proceed
    if [[ "$continuedl" == "no" || "$(dl_complete $1)" == 1 ]]; then
    echo "downloading $1"
    
      if [ -d "$topdir/$1" ]
      then
        rm -rf "$topdir/$1"
      fi
    mkdir -p "$topdir/$1"
    cd "$topdir/$1"
    
    # checkout of build should be done inside build/make, however I'm lazy so I will make a symlink
    if [ "$1" = "build" ]
      then
      #mkdir -p make
      #cd make
      ln -s . make
    fi  
    
    git init -q
    git remote add origin "$googlebaseurl/$1"
    
    # I don't want to restart the script everytime it fails to download something, just keep trying until you succeed 
    #git fetch --depth 1 origin "$2" -q 
    git_fetch
    
    git reset --hard FETCH_HEAD -q

    cd "$topdir"
    echo "$1" >> "$topdir/.dl_done"
    fi
}

if [ "$skipsrc" == 'no' ]
  then

mkdir -p "$topdir"
cd "$topdir"


for source in "${sources[@]}"
  do
    _buildref="$buildref"
    if [ "$source" == 'external/googletest' ]
      then
        _buildref='android-10.0.0_r2'
    fi

        download_from_git "$source" "$_buildref"
        
        # I'm lazy, complete only if necessary. Disabling
        #if [ "$source" == 'build' ]
        #  then
        #  cp build/make/core/root.mk $topdir/Makefile
        #  
        #fi
done


cd "$topdir"

if [[ "$skipbenches" == 'yes' ]]
  then
    find bionic -type d -name 'benchmarks' -exec rm -r {} +
fi

if [[ "$skippatch" == 'no' ]]
  then
  for patch in $scriptdir/*.patch
    do
      patch -f -p1 < "$patch" || true
    done
fi

fi


if [ "$skipndk" == 'no' ]
  then
        _buildref="$buildref"
        for tool in "${prebuilts[@]}"
          do
            download_from_git "$tool" "$_buildref"
        done
rm -r prebuilts/misc/common/android-support-test || true
fi

# We need to put in place some files in order for the build to succeed
cp build/core/root.mk Makefile
ln -s build/soong/root.bp Android.bp 2>/dev/null || true
ln -s build/soong/bootstrap.bash bootstrap.bash 2>/dev/null || true

source build/envsetup.sh
lunch "aosp_$ndkarch-eng" > /dev/null

if [ "$skipzlib" == 'no' ]
  then
    download_from_git 'external/zlib' "$buildref"
    cd "$topdir/external/zlib"
    mma -j5
fi

cd "$topdir/bionic"
mma -j5

outdir="$topdir/out/target/product/generic"
test -d "${outdir}_$ndkarch" && outdir+="_$ndkarch"

cd "$outdir"
if [ "$skipzlib" == 'no' ]
  then
    outfile="$topdir/../bionic_${arch}_${buildref}_zlib.tar.xz"
else
    outfile="$topdir/../bionic_${arch}_${buildref}.tar.xz"
fi    

tar -cJf "$outfile" data system

set +e
