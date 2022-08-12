#!/bin/bash

ALL_IN_ONE_PATH="/abs/path/to/your/glibc-all-in-one"
VERSION=$ALL_IN_ONE_PATH"/glibc_versions"
#DIR_TCACHE='tcache'
DIR_TCACHE=''
DIR_HOST='x64'
LIB_HOST='amd64'
GLIBC_VERSION=''
TARGET=''
UPDATE=''
RELOAD=''
GDB=''
RADARE2=''
NOT_EXECUTION=''
FORCE_TARGET_INTERPRETER=''

# Handle arguments
function show_help {
    # echo "Usage: $0 <version> <target> [-h] [-i686] [-u] [-r] [-gdb | -r2 | -p]"
	echo "Usage: $0 <version> <target> [-h] [-i686] [-gdb | -r2 | -p]"
    echo "-i686 - use x32 bits libc"
    # echo "-u - update libc list in glibc-all-in-one"
    # echo "-r - download libc in glibc-all-in-one"
    echo "-gdb - start target in GDB"
    echo "-r2 - start target in radare2"
    echo "-p - just set interpreter and rpath in target without execution"
}

if [[ $# < 2 ]]; then
    show_help
    exit 1
fi

function init_glibc(){
    git submodule update --init --recursive
}

function update_glibc (){
    if [ "$1" == "X" ] || [ ! -f $ALL_IN_ONE_PATH/list ]; then
        cd $ALL_IN_ONE_PATH
        ./update_list
        cd -
    fi
}

function download_glibc (){
    if [ "$2" == "X" ] || [ ! -d $ALL_IN_ONE_PATH/libs/$libc ]; then
        cd $ALL_IN_ONE_PATH
        rm -rf libs/$1 debs/$1
        ./download $1
        ./download_old $1
        cd -
    fi
}

function copy_glibc (){
    if [ ! -f "$OUTPUT_DIR/libc-$GLIBC_VERSION.so" ]; then
        cp -r $ALL_IN_ONE_PATH/libs/$1/* $OUTPUT_DIR
        cp -r $ALL_IN_ONE_PATH/libs/$1/.debug $OUTPUT_DIR
    fi
}

function set_interpreter (){
    local curr_interp=$(patchelf --print-interpreter "$TARGET")
    
    if [[ $curr_interp != $1 ]];
    then
        patchelf --set-interpreter "$1" "$TARGET"
        echo "INERPERETER as $1 for $TARGET"
    fi
}

function set_rpath (){
    curr_rpath=$(patchelf --print-rpath "$TARGET")
    
    if [[ $curr_rpath != $OUTPUT_DIR ]];
    then
        patchelf --set-rpath "$OUTPUT_DIR" "$TARGET"
        echo "RPATH as $OUTPUT_DIR"
    fi
}

GLIBC_VERSION=$1		# 2.23
GLIBC_MAJOR=$(echo $GLIBC_VERSION | cut -d'.' -f1)	# 2(.23)
GLIBC_MINOR=$(echo $GLIBC_VERSION | cut -d'.' -f2)	# (2.)23
TARGET=$2			# binary file
SYSTEM_GLIBC_VERSION=$(lsof -p $$ 2>/dev/null | grep libc- | awk ' { print $NF" --version"; } ' | sh | head -n 1 | cut -d' ' -f 10 | cut -d'.' -f 1-2)
SYSTEM_GLIBC_MAJOR=$(echo $SYSTEM_GLIBC_VERSION | cut -d'.' -f1)
SYSTEM_GLIBC_MINOR=$(echo $SYSTEM_GLIBC_VERSION | cut -d'.' -f2)
SYSTEM_GLIBC=$(lsof -p $$ 2>/dev/null | grep libc- | awk ' { print $NF" --version"; } ' | sh | head -n 1 | cut -d' ' -f 10)

while :; do
    case $3 in
        -h|-\?|--help)
            show_help
            exit
        ;;
        #        -disable-tcache)
        #            DIR_TCACHE='notcache'
        #            ;;
        -i686)
            DIR_HOST='i686'
            LIB_HOST='i386'
        ;;
        -u)
            UPDATE='X'
        ;;
        -r)
            RELOAD='X'
        ;;
        -gdb)
            GDB='X'
        ;;
        -r2)
            RADARE2='X'
        ;;
        -p)
            NOT_EXECUTION='X'
        ;;
        -ti)
            FORCE_TARGET_INTERPRETER='X'
        ;;
        '')
            break
        ;;
    esac
    shift
done


if [ ! -d $ALL_IN_ONE_PATH/LICENSE ]; then
    init_glibc
fi

if [ -z $DIR_TCACHE ]; then
    OUTPUT_DIR="$VERSION/$GLIBC_VERSION/${DIR_HOST}/lib"
else
    OUTPUT_DIR="$VERSION/$GLIBC_VERSION/${DIR_HOST}_${DIR_TCACHE}/lib"
fi

if [ ! -d "$OUTPUT_DIR" ];
then
    mkdir -p $OUTPUT_DIR
fi

update_glibc $UPDATE	# update_glibc run update_list
libc=$(cat $ALL_IN_ONE_PATH/list | grep "$GLIBC_VERSION" | grep "$LIB_HOST" | head -n 1)
download_glibc $libc $RELOAD
copy_glibc $libc

if [ ! -f $TARGET ]; then
    echo "Create binaries by make"
    exit
fi

if [ -z "$(ls -A $OUTPUT_DIR)" ]; then
    echo "Couldn't download and extract glibc."
    echo "Check you have installed zstd"
    exit
fi

if [ ! -f $TARGET ]; then	# binary doesn't exists
    echo "Create binaries by make"
    exit
fi

target_interpreter="$OUTPUT_DIR/$(ls $OUTPUT_DIR | grep ld)"

if [[ $GLIBC_MAJOR != $SYSTEM_GLIBC_MAJOR ]] || [[ $GLIBC_MINOR != $SYSTEM_GLIBC_MINOR ]]; then
    set_interpreter $target_interpreter
    set_rpath
fi

if [ "$GDB" == 'X' ];
then
    if [[ $GLIBC_VERSION != $SYSTEM_GLIBC_VERSION ]]; then
        gdb $TARGET -iex "set debug-file-directory $OUTPUT_DIR/.debug"
    else
        gdb $TARGET
    fi
elif [ "$RADARE2" == 'X' ];
then
    r2 -d $TARGET
elif [ "$NOT_EXECUTION" == ''  ];
then
    "./$TARGET"
else
    echo "$TARGET It's ready for discovering"
fi
