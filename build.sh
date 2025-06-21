#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Please adjust these paths and directory names if they are incorrect.

# Project source directories
GAME_DIR="cgame"
NET_DIR="cnet"
SKILL_DIR="cskill"

# Shared resources location
# The original script used '~/share' and '/root/share'.
# Using a single, configurable path is more robust.
SHARE_DIR="$HOME/share"
ROOT_SHARE_DIR="/root/share" # Used for a single symlink

# Number of parallel jobs for 'make'
MAKE_JOBS=32

# --- End of Configuration ---

# --- Helper Functions ---

# Prints a formatted header.
print_header() {
    echo ""
    echo "========================================================================"
    echo "=> $1"
    echo "========================================================================"
    echo ""
}

# --- Setup Functions ---

setup_symlinks() {
    print_header "Setting up symlinks for $NET_DIR"
    cd "$NET_DIR"
    # Use -snf to create symlinks without having to remove old ones first.
    ln -snf "$SHARE_DIR/common" .
    ln -snf "$SHARE_DIR/io" .
    ln -snf "$SHARE_DIR/mk" .
    ln -snf "$SHARE_DIR/storage" .
    ln -snf "$SHARE_DIR/rpc" .
    ln -snf "$SHARE_DIR/lua" .
    ln -snf "$SHARE_DIR/rpcgen" .
    cd ..

    print_header "Setting up iolib"
    mkdir -p iolib/inc
    cd iolib

    # Symlink headers
    cd inc
    ln -snf "../../$NET_DIR/gamed/auctionsyslib.h" .
    ln -snf "../../$NET_DIR/gamed/sysauctionlib.h" .
    ln -snf "../../$NET_DIR/gdbclient/db_if.h" .
    ln -snf "../../$NET_DIR/gamed/factionlib.h" .
    ln -snf "../../$NET_DIR/common/glog.h" .
    ln -snf "../../$NET_DIR/gamed/gsp_if.h" .
    ln -snf "../../$NET_DIR/gamed/mailsyslib.h" .
    ln -snf "../../$NET_DIR/gamed/privilege.hxx" .
    ln -snf "../../$NET_DIR/gamed/sellpointlib.h" .
    ln -snf "../../$NET_DIR/gamed/stocklib.h" .
    ln -snf "../../$NET_DIR/gamed/webtradesyslib.h" .
    ln -snf "../../$NET_DIR/gamed/kingelectionsyslib.h" .
    ln -snf "../../$NET_DIR/gamed/pshopsyslib.h" .
    ln -snf "../../$NET_DIR/gdbclient/db_os.h" .
    ln -snf "$ROOT_SHARE_DIR/io/luabase.h" .
    cd ..

    # Symlink libraries
    ln -snf "../$NET_DIR/io/libgsio.a" .
    ln -snf "../$NET_DIR/gdbclient/libdbCli.a" .
    ln -snf "/root/cskill/skill/libskill.a" . # This path seems specific, leaving as is.
    ln -snf "../$NET_DIR/gamed/libgsPro2.a" .
    ln -snf "../$NET_DIR/logclient/liblogCli.a" .
    cd ..

    print_header "Modifying Rules.make"
    local escaped_pwd
    escaped_pwd=$(pwd | sed -e 's/\//\\\//g')
    cd "$GAME_DIR"
    sed -i -e "s/IOPATH=.*$/IOPATH=$escaped_pwd\/iolib/g" -e "s/BASEPATH=.*$/BASEPATH=$escaped_pwd\/$GAME_DIR/g" Rules.make
    
    print_header "Linking libskill.so"
    cd gs
    ln -snf "../../cskill/libskill.so" .
    cd ../../
}

# --- Build Functions ---

# A generic build function for components that use 'make'
build_component() {
    local component_path=$1
    local component_name=$2
    local extra_make_args=${3:-}
    
    print_header "Building $component_name"
    cd "$component_path"
    make clean
    make -j"$MAKE_JOBS" $extra_make_args
    cd - > /dev/null # Go back to previous directory quietly
}

build_rpcgen() {
    print_header "Running rpcgen"
    (cd "$NET_DIR" && ./rpcgen rpcalls.xml)
}

build_rpc_data() {
    print_header "Copying RPC Data"
    # The original script called this function, but the copy commands within it
    # were commented out. Uncomment the lines below if you need to copy these files.
    # DEST_DIR="/root/cnet/rpcdata"
    # mkdir -p "$DEST_DIR"
    # cp ./add/ec_sqlarenateammember "$DEST_DIR/ec_sqlarenateammember"
    # cp ./add/ec_sqlarenateam "$DEST_DIR/ec_sqlarenateam"
    echo "Skipping RPC data copy. To enable, edit the 'build_rpc_data' function in this script."
}

build_deliver_daemons() {
    build_component "$NET_DIR/licenseclient" "licenseclient" "lib"
    build_component "$NET_DIR/gauthd" "gauthd"
    build_component "$NET_DIR/logservice" "logservice"
    build_component "$NET_DIR/gacd" "gacd"
    build_component "$NET_DIR/glinkd" "glinkd"
    build_component "$NET_DIR/gdeliveryd" "gdeliveryd"
    build_component "$NET_DIR/gamedbd" "gamedbd"
    build_component "$NET_DIR/uniquenamed" "uniquenamed"
    build_component "$NET_DIR/io" "libgsio" "lib"
    build_component "$NET_DIR/gfaction" "gfaction"
}

build_gs_libs() {
    build_component "$NET_DIR/logclient" "liblogCli.a" "-f Makefile.gs"
    build_component "$NET_DIR/gamed" "libgsPro2.a" "lib"
    build_component "$NET_DIR/gdbclient" "libdbCli.a" "lib"
    
    print_header "Building libgs"
    (
        cd "$GAME_DIR/libgs"
        mkdir -p io gs db sk log
        make
    )
}

build_skill() {
    print_header "Building Skill Library"
    cd "$SKILL_DIR/skill"
    
    (
      cd gen
      mkdir -p skills buffcondition
      # The original script had 'ant' here.
      # You may need to uncomment the following line:
      # ant
      chmod a+x gen
      # The './gen' command was commented out. Uncomment if needed.
      # ./gen
    )

    make clean
    make -j"$MAKE_JOBS"
    cd ../../
}

build_game() {
    # The 'cvs up' was commented out in the original. Uncomment if needed.
    # (cd "$GAME_DIR" && cvs up)
    build_component "$GAME_DIR" "cgame"
}

# --- Installation Functions ---

install_daemons() {
    print_header "Installing daemons"
    # These paths are hardcoded, assuming a fixed deployment environment.
    cp ./"$GAME_DIR"/gs/gs /home/gamed/gs
    cp ./"$GAME_DIR"/gs/libtask.so /home/gamed/libtask.so
    cp ./"$SKILL_DIR"/libskill.so /home/gamed/libskill.so
    cp ./"$NET_DIR"/gfaction/gfactiond /home/gfactiond/gfactiond
    cp ./"$NET_DIR"/gauthd/gauthd /home/gauthd/gauthd
    cp ./"$NET_DIR"/uniquenamed/uniquenamed /home/uniquenamed/uniquenamed
    cp ./"$NET_DIR"/gamedbd/gamedbd /home/gamedbd/gamedbd
    cp ./"$NET_DIR"/gdeliveryd/gdeliveryd /home/gdeliveryd/gdeliveryd
    cp ./"$NET_DIR"/glinkd/glinkd /home/glinkd/glinkd
    cp ./"$NET_DIR"/gacd/gacd /home/gacd/gacd
    cp ./"$NET_DIR"/logservice/logservice /home/logservice/logservice
    echo "Installation successful!"
}

install_protect_files() {
    print_header "Copying files for protection"
    # This path is hardcoded, assuming a fixed deployment environment.
    local dest_dir="/root/get_protects"
    mkdir -p "$dest_dir"
    cp ./"$GAME_DIR"/gs/gs "$dest_dir"/gs
    cp ./"$NET_DIR"/gfaction/gfactiond "$dest_dir"/gfactiond
    cp ./"$NET_DIR"/gauthd/gauthd "$dest_dir"/gauthd
    cp ./"$NET_DIR"/uniquenamed/uniquenamed "$dest_dir"/uniquenamed
    cp ./"$NET_DIR"/gamedbd/gamedbd "$dest_dir"/gamedbd
    cp ./"$NET_DIR"/gdeliveryd/gdeliveryd "$dest_dir"/gdeliveryd
    cp ./"$NET_DIR"/glinkd/glinkd "$dest_dir"/glinkd
    echo "Copy successful!"
}

# --- Main Logic ---

usage() {
    echo "Usage: $0 {setup|deliver|gs|game|skill|rpcdata|all|install}"
    echo "Commands:"
    echo "  setup      : Set up initial symlinks and configurations."
    echo "  deliver    : Build all daemon applications."
    echo "  gs         : Build the main game server libraries (not the executable)."
    echo "  game       : Build the 'cgame' component, including the 'gs' executable."
    echo "  skill      : Build the skill library."
    echo "  rpcdata    : Copy RPC data files (currently disabled in script)."
    echo "  all        : Build and install everything."
    echo "  install    : Copy built files to their destination."
    exit 1
}

main() {
    if [ $# -eq 0 ]; then
        usage
    fi

    case "$1" in
        setup)
            setup_symlinks
            ;;
        deliver)
            build_rpcgen
            build_deliver_daemons
            ;;
        gs)
            build_gs_libs
            ;;
        game)
            build_game
            ;;
        skill)
            build_skill
            ;;
        rpcdata)
            build_rpc_data
            ;;
        all)
            build_rpcgen
            build_rpc_data
            build_deliver_daemons
            build_gs_libs
            build_skill
            build_game
            install_daemons
            install_protect_files
            ;;
        install)
            install_daemons
            install_protect_files
            ;;
        *)
            usage
            ;;
    esac

    print_header "Build process '$1' finished successfully."
}

# Run the main function with all script arguments
main "$@"
