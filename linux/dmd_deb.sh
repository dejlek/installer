#!/bin/bash


set -e -o pipefail


# error function
ferror(){
	echo "==========================================================" >&2
	echo $1 >&2
	echo $2 >&2
	echo "==========================================================" >&2
	exit 1
}


# check if in debian like system
if test ! -f /etc/debian_version ; then
	ferror "Refusing to build on a non-debian like system" "Exiting..."
fi


# show help
if test -z $1 ;then
	echo "Script to create dmd binary deb packages."
	echo
	echo "Usage:"
	echo "  dmd_deb.sh -v\"version\" -m\"model\" [-f]"
	echo
	echo "Options:"
	echo "  -v       dmd version (mandatory)"
	echo "  -m       32 or 64 (mandatory)"
	echo "  -f       force to rebuild"
	exit
fi


# check if too many parameters
if test $# -gt 3 ;then
	ferror "Too many arguments" "Exiting..."
fi


# check version parameter
if test "${1:0:2}" != "-v" ;then
	ferror "Unknown first argument (-v)" "Exiting..."
elif test "${1:0:4}" != "-v1." -a "${1:0:4}" != "-v2." -o `expr length $1` -ne 7 || `echo ${1:4} | grep -q [^[:digit:]]` ;then
	ferror "Incorrect version number" "Exiting..."
elif test "${1:0:4}" = "-v1." -a "${1:4}" -lt "73" ;then
	ferror "For \"dmd v1.073\" and newer only" "Exiting..."
elif test "${1:0:4}" = "-v2." -a "${1:4}" -lt "58" ;then
	ferror "For \"dmd v2.058\" and newer only" "Exiting..."
fi


# check model parameter
if test $# -eq 1 ;then
	ferror "Second argument is mandatory (-m[32-64])" "Exiting..."
elif test "$2" != "-m32" -a "$2" != "-m64" ;then
	ferror "Unknown second argument (-m[32-64])" "Exiting..."
fi


# check forced build parameter
if test $# -eq 3 -a "$3" != "-f" ;then
	ferror "Unknown third argument (-f)" "Exiting..."
fi


# needed commands function
E=0
fcheck(){
	if ! `which $1 1>/dev/null 2>&1` ;then
		LIST=$LIST" "$1
		E=1
	fi
}
fcheck gzip
fcheck unzip
fcheck wget
fcheck dpkg
fcheck dpkg-shlibdeps
fcheck fakeroot
fcheck dpkg-deb
if [ $E -eq 1 ]; then
    ferror "Missing commands on Your system:" "$LIST"
fi


# assign variables
MAINTAINER="Jordi Sayol <g.sayol@yahoo.es>"
VERSION=${1:2}
RELEASE=0
DESTDIR=`pwd`
TEMPDIR='/tmp/'`date +"%s%N"`
if test "${1:0:4}" = "-v1." ;then
	UNZIPDIR="dmd"
	DMDURL="http://ftp.digitalmars.com/dmd.$VERSION.zip"
elif test "${1:0:4}" = "-v2." ;then
	UNZIPDIR="dmd2"
	DMDURL="https://github.com/downloads/D-Programming-Language/dmd/dmd.$VERSION.zip"
fi
if test "$2" = "-m64" ;then
	ARCH="amd64"
elif test "$2" = "-m32" ;then
	ARCH="i386"
fi
ZIPFILE=`basename $DMDURL`
DMDDIR="dmd_"$VERSION"-"$RELEASE"_"$ARCH
DIR32="i386-linux-gnu"
DIR64="x86_64-linux-gnu"
DEBFILE=$DMDDIR".deb"


# check if destination deb file already exist
if `dpkg -I $DESTDIR"/"$DEBFILE &>/dev/null` && test "$3" != "-f" ;then
	echo -e "$DEBFILE - already exist"
else
	# remove bad formated deb file
	rm -f $DESTDIR"/"$DEBFILE


	# download zip file if not exist
	if test ! -f $DESTDIR"/"$ZIPFILE ;then
		echo "Downloading $ZIPFILE..."
		wget -nv -P $DESTDIR $DMDURL
	fi


	# create temp dir
	mkdir -p $TEMPDIR"/"$DMDDIR


	# unpacking sources
	unzip -q $DESTDIR"/"$ZIPFILE -d $TEMPDIR


	# add dmd-completion if present
	if test -f `dirname $0`"/"dmd-completion ;then
		mkdir -p $TEMPDIR"/"$DMDDIR"/etc/bash_completion.d/"
		cp `dirname $0`"/"dmd-completion $TEMPDIR"/"$DMDDIR"/etc/bash_completion.d/dmd"
	fi


	# change unzipped folders and files permissions
	chmod -R 0755 $TEMPDIR/$UNZIPDIR/*
	chmod 0644 $(find -L $TEMPDIR/$UNZIPDIR ! -type d)


	# switch to temp dir
	pushd $TEMPDIR"/"$DMDDIR


	# install binaries
	mkdir -p usr/bin
	if test "$ARCH" = "amd64" ;then
		cp -f ../$UNZIPDIR/linux/bin64/{dmd,dumpobj,obj2asm,rdmd} usr/bin
		if [ "$UNZIPDIR" = "dmd2" ]; then
			cp -f ../$UNZIPDIR/linux/bin64/{ddemangle,dman} usr/bin
		fi
	elif test "$ARCH" = "i386" ;then
		cp -f ../$UNZIPDIR/linux/bin32/{dmd,dumpobj,obj2asm,rdmd} usr/bin
		if [ "$UNZIPDIR" = "dmd2" ]; then
			cp -f ../$UNZIPDIR/linux/bin32/{ddemangle,dman} usr/bin
		fi
	fi


	# install libraries
	mkdir -p usr/lib
	if [ "$UNZIPDIR" = "dmd2" ]; then
		PHONAME="libphobos2.a"
	elif [ "$UNZIPDIR" = "dmd" ]; then
		PHONAME="libphobos.a"
	fi
	mkdir -p usr/lib/{$DIR32,$DIR64}
	cp -f ../$UNZIPDIR/linux/lib32/$PHONAME usr/lib/$DIR32
	cp -f ../$UNZIPDIR/linux/lib64/$PHONAME usr/lib/$DIR64


	# install include
	find ../$UNZIPDIR/src/ -iname "*.mak" -print0 | xargs -0 rm
	if test "$ARCH" = "amd64" ;then
		mkdir -p usr/include/$DIR64/dmd/
		cp -Rf ../$UNZIPDIR/src/phobos/ usr/include/$DIR64/dmd
		if [ "$UNZIPDIR" = "dmd2" ]; then
			mkdir -p usr/include/$DIR64/dmd/druntime/
			cp -Rf ../$UNZIPDIR/src/druntime/import/ usr/include/$DIR64/dmd/druntime
		fi
	elif test "$ARCH" = "i386" ;then
		mkdir -p usr/include/$DIR32/dmd/
		cp -Rf ../$UNZIPDIR/src/phobos/ usr/include/$DIR32/dmd
		if [ "$UNZIPDIR" = "dmd2" ]; then
			mkdir -p usr/include/$DIR32/dmd/druntime/
			cp -Rf ../$UNZIPDIR/src/druntime/import/ usr/include/$DIR32/dmd/druntime
		fi
	fi


	# install samples and HTML
	mkdir -p usr/share/dmd/
	cp -Rf ../$UNZIPDIR/samples/ usr/share/dmd
	cp -Rf ../$UNZIPDIR/html/ usr/share/dmd


	# install man pages
	gzip ../$UNZIPDIR/man/man1/{dmd.1,dmd.conf.5,dumpobj.1,obj2asm.1,rdmd.1}
	chmod 0644 ../$UNZIPDIR/man/man1/{dmd.1.gz,dmd.conf.5.gz,dumpobj.1.gz,obj2asm.1.gz,rdmd.1.gz}
	mkdir -p usr/share/man/man1/
	cp -f ../$UNZIPDIR/man/man1/{dmd.1.gz,dumpobj.1.gz,obj2asm.1.gz,rdmd.1.gz} usr/share/man/man1
	mkdir -p usr/share/man/man5/
	cp -f ../$UNZIPDIR/man/man1/dmd.conf.5.gz usr/share/man/man5


	# debianize copyright file
	mkdir -p usr/share/doc/dmd
	echo "This package was debianized by $MAINTAINER" > usr/share/doc/dmd/copyright
	echo "on `date -R`" >> usr/share/doc/dmd/copyright
	echo  >> usr/share/doc/dmd/copyright
	echo "It was downloaded from http://dlang.org/" >> usr/share/doc/dmd/copyright
	echo  >> usr/share/doc/dmd/copyright
	echo  >> usr/share/doc/dmd/copyright
	cat ../$UNZIPDIR/license.txt >> usr/share/doc/dmd/copyright


	# link changelog
	ln -s ../../dmd/html/d/changelog.html usr/share/doc/dmd/


	# create /etc/dmd.conf file
	mkdir -p etc/
	echo "; " > etc/dmd.conf
	echo "; dmd.conf file for dmd" >> etc/dmd.conf
	echo "; " >> etc/dmd.conf
	echo "; dmd will look for dmd.conf in the following sequence of directories:" >> etc/dmd.conf
	echo ";   - current working directory" >> etc/dmd.conf
	echo ";   - directory specified by the HOME environment variable" >> etc/dmd.conf
	echo ";   - directory dmd resides in" >> etc/dmd.conf
	echo ";   - /etc directory" >> etc/dmd.conf
	echo "; " >> etc/dmd.conf
	echo "; Names enclosed by %% are searched for in the existing environment and inserted" >> etc/dmd.conf
	echo "; " >> etc/dmd.conf
	echo "; The special name %@P% is replaced with the path to this file" >> etc/dmd.conf
	echo "; " >> etc/dmd.conf
	echo >> etc/dmd.conf
	echo "[Environment]" >> etc/dmd.conf
	echo >> etc/dmd.conf
	if [ "$ARCH" = "amd64" ]; then
		echo -n "DFLAGS=-I/usr/include/$DIR64/dmd/phobos" >> etc/dmd.conf
		if [ "$UNZIPDIR" = "dmd2" ]; then
			echo -n " -I/usr/include/$DIR64/dmd/druntime/import" >> etc/dmd.conf
		fi
		echo -n " -L-L/usr/lib/$DIR64 -L-L/usr/lib/$DIR32" >> etc/dmd.conf
	elif [ "$ARCH" = "i386" ]; then
		echo -n "DFLAGS=-I/usr/include/$DIR32/dmd/phobos" >> etc/dmd.conf
		if [ "$UNZIPDIR" = "dmd2" ]; then
			echo -n " -I/usr/include/$DIR32/dmd/druntime/import" >> etc/dmd.conf
		fi
		echo -n " -L-L/usr/lib/$DIR32 -L-L/usr/lib/$DIR64" >> etc/dmd.conf
	fi
	echo " -L--no-warn-search-mismatch -L--export-dynamic" >> etc/dmd.conf


	# create conffiles file
	mkdir -p DEBIAN
	echo "/etc/dmd.conf" > DEBIAN/conffiles
	if test -f etc/bash_completion.d/dmd ;then
		echo "/etc/bash_completion.d/dmd" >> DEBIAN/conffiles
	fi


	# find deb package dependencies
	DEPEND="libc6-dev, gcc, gcc-multilib, libc6, libgcc1, libstdc++6"
	if test "$UNZIPDIR" = "dmd2" ;then
		DEPEND=$DEPEND", xdg-utils"
	fi


	# create control file
	echo "Package: dmd" > DEBIAN/control
	echo "Version: $VERSION-$RELEASE" >> DEBIAN/control
	echo "Architecture: $ARCH" >> DEBIAN/control
	echo "Maintainer: $MAINTAINER" >> DEBIAN/control
	echo "Installed-Size: `du -ks usr/| awk '{print $1}'`" >> DEBIAN/control
	echo "Depends: $DEPEND" >> DEBIAN/control
	echo "Section: devel" >> DEBIAN/control
	echo "Priority: optional" >> DEBIAN/control
	echo "Homepage: http://dlang.org/" >> DEBIAN/control
	echo "Description: Digital Mars D Compiler" >> DEBIAN/control
	echo " D is a systems programming language. Its focus is on combining the power and" >> DEBIAN/control
	echo " high performance of C and C++ with the programmer productivity of modern" >> DEBIAN/control
	echo " languages like Ruby and Python. Special attention is given to the needs of" >> DEBIAN/control
	echo " quality assurance, documentation, management, portability and reliability." >> DEBIAN/control
	echo " ." >> DEBIAN/control
	echo " The D language is statically typed and compiles directly to machine code." >> DEBIAN/control
	echo " It's multiparadigm, supporting many programming styles: imperative," >> DEBIAN/control
	echo " object oriented, functional, and metaprogramming. It's a member of the C" >> DEBIAN/control
	echo " syntax family, and its appearance is very similar to that of C++." >> DEBIAN/control
	echo " ." >> DEBIAN/control
	echo " It is not governed by a corporate agenda or any overarching theory of" >> DEBIAN/control
	echo " programming. The needs and contributions of the D programming community form" >> DEBIAN/control
	echo " the direction it goes." >> DEBIAN/control
	echo " ." >> DEBIAN/control
	echo " Main designer: Walter Bright" >> DEBIAN/control


	# create md5sum file
	find usr/ -type f -print0 | xargs -0 md5sum > DEBIAN/md5sum
	if test -d etc/ ;then
		find etc/ -type f -print0 | xargs -0 md5sum >> DEBIAN/md5sum
	fi


	# change folders and files permissions
	chmod -R 0755 *
	chmod 0644 $(find -L . ! -type d)
	chmod 0755 usr/bin/{dmd,dumpobj,obj2asm,rdmd}
	if [ "$UNZIPDIR" = "dmd2" ]; then
		chmod 0755 usr/bin/{ddemangle,dman}
	fi


	# create deb package
	cd ..
	fakeroot dpkg-deb -b $DMDDIR


	# disable pushd
	popd


	# place deb package
	mv $TEMPDIR"/"$DEBFILE $DESTDIR


	# delete temp dir
	rm -Rf $TEMPDIR
fi

