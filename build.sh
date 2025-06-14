#!/bin/bash

# Configuration
HOME=/root
INSTALLDIR=/home
GS=$HOME/cgame
NET=$HOME/cnet
SKILL=$HOME/cskill
LOGFILE="build.log"
exec > >(tee -a "$LOGFILE") 2>&1

log_section() {
	echo ""
	echo "======================= $1 ======================="
	echo ""
}

setup_links() {
	log_section "Setting up $NET"
	cd "$NET" || exit 1
	rm -f common io mk storage rpc lua rpcgen
	ln -s $HOME/share/{common,io,mk,storage,rpc,lua,rpcgen} .
	cd ..

	log_section "Setting up iolib"
	mkdir -p iolib/inc
	cd iolib/inc || exit 1
	rm -f *
	for header in \
		auctionsyslib.h sysauctionlib.h db_if.h factionlib.h glog.h gsp_if.h \
		mailsyslib.h privilege.hxx sellpointlib.h stocklib.h webtradesyslib.h \
		kingelectionsyslib.h pshopsyslib.h db_os.h; do
		ln -s "$NET/gamed/$header"
	done
	ln -s $HOME/share/io/luabase.h
	cd ../
	rm -f lib*
	ln -s $NET/io/libgsio.a
	ln -s $NET/gdbclient/libdbCli.a
	ln -s $SKILL/skill/libskill.a
	ln -s $NET/gamed/libgsPro2.a
	ln -s $NET/logclient/liblogCli.a
	cd ..

	log_section "Updating Rules.make"
	EPWD=$(pwd | sed -e 's/\//\\\//g')
	cd "$GS"
	sed -i -e "s|IOPATH=.*$|IOPATH=$EPWD/iolib|" -e "s|BASEPATH=.*$|BASEPATH=$EPWD/$GS|" Rules.make
	cd ..

	log_section "Linking libskill.so"
	cd "$GS/gs" || exit 1
	rm -f libskill.so
	ln -s $SKILL/libskill.so
	cd ../../
}

build_all() {
	setup_links
	build_rpcgen
	build_deliver
	build_gslib
	build_skill
	build_game
	build_task
	install_all
}

build_rpcgen() {
	log_section "$NET - rpcgen"
	cd "$NET" && ./rpcgen rpcalls.xml && cd ..
}

build_deliver() {
	log_section "Building Delivery Services"
	cd "$NET" || exit 1
	for dir in licenseclient gauthd logservice gacd glinkd gdeliveryd gamedbd uniquenamed gfaction io; do
		log_section "Building $dir"
		cd "$dir" && make clean && make -j32 && [[ "$dir" == "io" ]] && make lib -j32 || true
		cd ..
	done
	cd ..
}

build_gslib() {
	log_section "Building Core Libraries"
	cd "$NET/logclient" && make clean && make -f Makefile.gs clean && make -f Makefile.gs -j32 && cd ../
	cd "$NET/gamed" && make clean && make lib -j32 && cd ../
	cd "$NET/gdbclient" && make clean && make lib -j32 && cd ../
	cd "$GS/libgs"
	mkdir -p io gs db sk log
	make
	cd ../../
}

build_skill() {
	log_section "Building Skills"
	cd $SKILL/skill/gen || exit 1
	mkdir -p skills buffcondition
	ant
	chmod a+x gen
	cd ..
	make clean && make -j32
	cd ../../
}

build_game() {
	log_section "Building Game"
	cd "$GS" || exit 1
	make clean && make -j32
	cd ..
}

build_task() {
	log_section "Building Task Library"
	cd "$GS/gs/task" || exit 1
	make clean && make lib -j32
	cd ../../../
}

install_all() {
	log_section "Installing to system directories"
	install_main
	install_protected
}

install_main() {
	cp $GS/gs/gs $INSTALLDIR/gamed/gs
	cp $GS/gs/libtask.so $INSTALLDIR/gamed/libtask.so
	cp $SKILL/libskill.so $INSTALLDIR/gamed/libskill.so
	for daemon in gfactiond gauthd uniquenamed gamedbd gdeliveryd glinkd gacd logservice; do
		cp "$NET/$daemon/$daemon" "$INSTALLDIR/$daemon/$daemon"
	done
	log_section "Main Installation Completed"
}

install_protected() {
	for daemon in gs gfactiond gauthd uniquenamed gamedbd gdeliveryd glinkd gacd; do
		cp "$NET/$daemon/$daemon" "$HOME/get_protects/$daemon"
	done
	log_section "Protected Copy Completed"
}

show_menu() {
	clear
	echo "=========== Build Menu ==========="
	echo "1) Build Delivery Services"
	echo "2) Build GS (core server libs)"
	echo "3) Full Build (ALL)"
	echo "4) Install"
	echo "5) Exit"
	echo "=================================="
	read -rp "Choose an option: " option
	case $option in
		1) build_rpcgen; build_deliver ;;
		2) build_gslib ;;
		3) build_all ;;
		4) install_all ;;
		5) exit 0 ;;
		*) echo "Invalid option";;
	esac
}

main() {
	if [ $# -gt 0 ]; then
		case "$1" in
			deliver) build_rpcgen; build_deliver ;;
			gs) build_gslib ;;
			all) build_all ;;
			install) install_all ;;
			*) echo "Unknown argument: $1" ;;
		esac
	else
		while true; do
			show_menu
			read -rp "Press Enter to continue..." _
		done
	fi
}

main "$@"
