#!/bin/bash

###############################################################################
#
#  lxc-gentoo : script to create a gentoo lxc guest
#
#   license:
#     This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
#
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#   this script requires:
#    - bash
#    - flock
#    - gpg (source validation)
#    - wget and a working internet connection for HTTP fetches
#
#   output requires (at runtime):
#    - lxc-utils package
#    - linux kernel with relevant options enabled (see lxc-checkconfig)
#
#   output environment description:
#    - uses the latest stage3 and portage (ie: 'very latest gentoo')
#    - creates a veth-connected guest
#       - a virtual ethernet interface appears to the guest as 'eth0' and the
#         host as '<guestname>' (max 15 characters; less show on 'ifconfig',
#         use iputils' 'ip addr' instead)
#       - guests can instead use physical interface, vlan, etc.
#    - typical startup time is 0.2-0.3 seconds
#    - very fast disk IO (unlike paravirtualised solutions)
#
#   notes:
#    - dedicated to all fellow ethical unix hackers who do not work for
#      morally corrupt governments and corporations: use your powers for good!
#
#   authors: Fedja Beader, Anders Larsson, Julien Sanchez, Walter Stanish,
#            Guillaume Zitta, and others.
#
###############################################################################

CACHE="${CACHE:-/var/cache/lxc/gentoo}"
WGET="wget --timeout=8 --read-timeout=15 -c -t10 -nd"

# Defaults only
NAME="${NAME:-gentoo}"
UTSNAME="${UTSNAME:-gentoo.local}"
IPV4="${IPV4:-dhcp}"
IPV4_GATEWAY="${IPV4_GATEWAY:-auto}"
IPV6="${IPV6:-dhcp}"
IPV6_GATEWAY="${IPV6_GATEWAY:-auto}"
GUESTROOTPASS="$GUESTROOTPASS"
ARCH="${ARCH:-amd64}"
ARCHVARIANT="${ARCHVARIANT:-${ARCH}}"
CONFFILE="$CONFFILE"
MIRROR="${MIRROR:-http://distfiles.gentoo.org}"
STAGE3_TARBALL="${STAGE3_TARBALL}"
PORTAGE_SOURCE="$PORTAGE_SOURCE"
PGP_DIR="${PGP_DIR:-$HOME/.gnupg}"

# These paths are within the container so do not need to obey configure prefixes
INITTAB="/etc/inittab"
FSTAB="/etc/fstab"

# Ensure strict root's umask doesen't render the VM unusable
umask 022

################################################################################
#                        Various helper functions
################################################################################

# param: $1: the name of the lock
# The rest contain the command to execute and its parameters
execute_exclusively()
{
	mkdir -p /var/lock/subsys

	local lock_name="$1"
	shift 1

	{
		printf "Attempting to obtain an exclusive lock (timeout: 30 min) named \"%s\"...\n" "$lock_name"

		printf -v time_started "%(%s)T" "-1"
		flock -x -w 1800  50

		if [[ $? -ne 0 ]]; then
			printf " => unable to obtain after %s seconds, aborting.\n" "$(($(printf "%(%s)T" "-1") - $time_started))"
			return 2
		else
			printf " => done, took %s seconds.\n" "$(($(printf "%(%s)T" "-1") - $time_started))"
		fi

		printf " => Executing \"%s\"\n" "$*"
		"$@"

	} 50> "/var/lock/subsys/$lock_name"
}

# Please use these suggested error codes:
# die 1 ... -- general/unspecified failure
# die 2 ... -- filesystem error (e.g. tar unpacking failed)
# die 4 ... -- network error
# die 8 ... -- error in program logic
# die 16 .. -- erroneous (user) input
# or any combination of these.

die()
{
	printf "\n[the last exit code leading to this death was: %s ]\n" "$?"
	local retval="$1"
	shift 1
	printf "$@"
	exit "$retval"
}

################################################################################
#                    DISTRO custom configuration files
################################################################################

populate_dev()
{
	cd "$ROOTFS/dev" || die 2 "Unable to change directory to %s!\n" "$ROOTFS/dev"

	# we silence errors as newer stage3s already include needed device files
	{
		# newer stage3 include too many useless nodes, remove them
		rm -f hda*
		rm -f sda*
		rm -f sdb*
		rm -f sdc*
		rm -f sdd*
		rm -f tty*
		rm -f core
		rm -f mem
		rm -f port
		rm -rf input/

		# tabsize 4
		mknod -m 666 null		c 1 3
		mknod -m 666 zero		c 1 5
		mknod -m 666 full		c 1 7

		mknod -m 666 random		c 1 8
		mknod -m 666 urandom	c 1 9

		mknod -m 600 console	c 5 1
		mknod -m 666 tty		c 5 0
		mknod -m 666 tty0		c 4 0
		mknod -m 666 tty1		c 4 1

		mknod -m 600 initctl	p

		mknod -m 666 ptmx		c 5 2
		mkdir -m 755 pts

		mkdir -m 1777 shm

		mkdir -m 755 net
		mknod -m 666 net/tun	c 10 200

	} 2> /dev/null
	cd - > /dev/null
}

# custom fstab
write_distro_fstab()
{
	cat <<- EOF > "$ROOTFS/$FSTAB"
	# required to prevent boot-time error display
	none    /         none    defaults  0 0
	tmpfs   /dev/shm  tmpfs   defaults  0 0
	EOF
}

write_distro_timezone()
{
	if [ -e /etc/localtime ]; then
		# duplicate host timezone
		cat /etc/localtime > "$ROOTFS/etc/localtime"
	else
		# otherwise set up UTC
		rm "$ROOTFS/etc/localtime" > /dev/null 2>&1
		ln -s ../usr/share/zoneinfo/UTC "$ROOTFS/etc/localtime"
	fi
}

# custom inittab
write_distro_inittab()
{
	sed -i 's/^c[1-9]/#&/' "$ROOTFS/$INITTAB" # disable getty
	echo "# Lxc main console" >> "$ROOTFS/$INITTAB"
	echo "1:12345:respawn:/sbin/agetty -a root --noclear 115200 console linux" >> "$ROOTFS/$INITTAB"

	# finally we add a pf line to enable clean shutdown on SIGPWR (issue 60)
	echo "# clean container shutdown on SIGPWR" >> "$ROOTFS/$INITTAB"
	echo "pf:12345:powerwait:/sbin/halt" >> "$ROOTFS/$INITTAB"
}

setup_portage()
{
	# do a primitive portage setup
	mkdir -p "$ROOTFS/etc/portage" && \
	mkdir -p "$ROOTFS/var/portage/tmp" && \
	mkdir -p "$ROOTFS/var/portage/tree" && \
	mkdir -p "$ROOTFS/var/portage/logs" && \
	mkdir -p "$ROOTFS/var/portage/packages" && \
	mkdir -p "$ROOTFS/var/portage/distfiles" \
		|| die 2 "Error: unable to create needed portage directories.\n"

	# relocate profile symlink
	local src="$ROOTFS/etc/portage/make.profile"
	local dest="$(readlink "$src")"
	dest="${dest##*../}"
	dest="${dest//usr\/portage/var/portage/tree}"
	dest="$ROOTFS/$dest"
	ln -f -s "$dest" "$src" \
		|| die 2 "Error: unable to relocate portage symlink:\n%s -> %s\n" "$src" "$dest"

	cat <<- EOF >> "$ROOTFS/etc/portage/make.conf"
	PORTAGE_TMPDIR="/var/portage/tmp"
	PORTDIR="/var/portage/tree"
	PORT_LOGDIR="/var/portage/logs"
	PKGDIR="/var/portage/packages"
	DISTDIR="/var/portage/distfiles"

	# enable this to store built binary packages
	#FEATURES="\$FEATURES buildpkg"

	FEATURES="\$FEATURES compress-build-logs"
	FEATURES="\$FEATURES split-log"
	FEATURES="\$FEATURES split-elog"
	EOF

	if [[ "$PORTAGE_SOURCE" == "none" ]]; then
		printf "Skipping portage tree setup\n"
	else
		# We need to set up the portage tree
		if [[ -z "$PORTAGE_SOURCE" ]]; then
			execute_exclusively "portage" fetch_portage \
				|| die 1 "Error: unable to fetch a portage snapshot.\n"
		fi

		# PORTAGE_SOURCE will be set by fetch_portage.
		if [[ -f "$PORTAGE_SOURCE" ]]; then
			verify_gpg "$PORTAGE_SOURCE.gpgsig" "$PORTAGE_SOURCE"

			printf "Extracting the portage tree into %s/var/portage/tree...\n" "$ROOTFS"
			tar -xp --strip-components 1 -C "$ROOTFS/var/portage/tree/" -f "$PORTAGE_SOURCE" \
				|| die 2 "Error: unable to extract the portage tree.\n"
		elif [[ -d "$PORTAGE_SOURCE" ]]; then
			printf "Will bind mount the portage tree from the host (%s).\n" "$PORTAGE_SOURCE"
		else
			printf "Warning: I don't know what to do with this portage source (%s)\n" "$PORTAGE_SOURCE"
		fi
	fi
}

# custom network configuration
write_distro_network()
{
	# /etc/resolv.conf
	grep -i 'search ' /etc/resolv.conf > "$ROOTFS/etc/resolv.conf"
	grep -i 'nameserver ' /etc/resolv.conf >> "$ROOTFS/etc/resolv.conf"
	# Append LXC-specific gentoo network configuration instructions
	cat <<- EOF >> "$ROOTFS/etc/conf.d/net"

		# Use of this file is typically discouraged for lxc-gentoo guests.
		# this is because it inhibits guest portability between disparate
		# hosts. instead, use the guest-specific lxc.conf(5) file on the
		# host to configure appropriate static interface addressing. This
		# will result in a faster and more reliable startup than other
		# options such as VLAN bridging with spanning tree complexities,
		# or DHCP based autoconfiguration.
	EOF
	# only link for dchp, since static options render it unnecessary
	# https://github.com/globalcitizen/lxc-gentoo/issues/33
	if [ "${IPV4}" == "dhcp" ]; then
		ln -s net.lo "$ROOTFS/etc/init.d/net.eth0"
		ln -s /etc/init.d/net.eth0 "$ROOTFS/etc/runlevels/default/net.eth0"
	# otherwise treat network access as auto-provided by openrc, so as to
	# avoid errors about starting network related scripts when launching
	# actual network services (sshd, etc.)
	else
		echo 'rc_provide="net"' >>"$ROOTFS/etc/rc.conf"
	fi
}

# custom hostname
write_distro_hostname()
{
	# figure out the host parts
	local hosts_entries="$UTSNAME"
	local hosts_entry="$UTSNAME"

	while [[ $hosts_entry = *.* ]]; do
		hosts_entry="${hosts_entry%.*}"

		hosts_entries="$hosts_entries $hosts_entry"
	done

	# actual hostname will is now in $hosts_entry
	printf " - setting hostname..."
	printf "hostname=\"%s\"\n" "$hosts_entry" > "$ROOTFS/etc/conf.d/hostname"


	mapfile -t < "$ROOTFS/etc/hosts"
	printf "" > "$ROOTFS/etc/hosts" # truncate

	# potential problem: there are more 127... and ::1 entries. Not in stages for now.
	for line in "${MAPFILE[@]}"; do
		if [[ $line == 127.0.0.1* ]]; then
			printf "%-20s %s %s\n" "127.0.0.1" "$hosts_entries" "localhost" >> "$ROOTFS/etc/hosts"
		elif [[ $line == ::1* ]]; then
			printf "%-20s %s %s %s\n" "::1" "$hosts_entries" "localhost" >> "$ROOTFS/etc/hosts"
		else
			printf "%s\n" "$line" >> "$ROOTFS/etc/hosts"
		fi
	done

	printf "done.\n"
}

# fix init system
write_distro_init_fixes()
{
	# remove netmount from default runlevel (openrc leaves it in)
	rm -f "$ROOTFS/etc/runlevels/default/netmount" >/dev/null 2>&1
	# remove net.lo from boot runlevel (~jan 2013; openrc-0.11.8)
	rm -f "$ROOTFS/etc/runlevels/boot/net.lo" >/dev/null 2>&1
	# unless we are using DHCP to configure the container, we now
	# force openrc to automatic provision of the 'net' dep. this is
	# avoided for DHCP as it would prohibit service start from waiting
	# until the interface has been provided with an IP address, causing
	# many daemon start issues such as failed binds / bad connectivity
	# (~jan 2013)
	if [ "${IPV4}" != "dhcp" ]; then
		echo 'rc_provide="net"' >> "$ROOTFS/etc/rc.conf"
	fi
	# fix boot-time errors on openrc 0.12.4 related to mount permissions
	# (~jan 2014)
	rm -f "$ROOTFS/etc/runlevels/boot/bootmisc" 2>/dev/null
	# fix boot-time errors on openrc 0.12.4 related to lo interface being
	# already set up by the host system on our behalf (~jan 2014)
	rm -f "$ROOTFS/etc/runlevels/boot/loopback" 2>/dev/null
	# set reasonable default unicode-enabled locale, or perl vocallby whinges
	echo 'en_US.UTF-8 UTF-8' >>"$ROOTFS/etc/locale.gen"
	# fix boot-time errors on openrc 0.12.4 related to kernel modules
	# (~may 2014)
	rm -f "$ROOTFS/etc/runlevels/sysinit/kmod-static-nodes" 2>/dev/null
}

################################################################################
#                        lxc configuration files
################################################################################

write_lxc_configuration()
{
	echo -n " - writing LXC guest configuration..."

	if [[ "$ARCH" == "x86" || "$ARCH" == "amd64" ]]; then
		local arch_line="lxc.arch = $ARCH"
	else
		local arch_line="# lxc.arch = $ARCH"
	fi

	cat <<- EOF >> "$CONFFILE"
	# sets container architecture
	# If desired architecture != amd64 or x86, then we leave it unset as
	# LXC does not oficially support anything other than x86 or amd64.
	# (Qemu masks arch in those cases anyway).
	$arch_line

	# set the hostname
	lxc.utsname = ${UTSNAME%%.*}

	# network interface
	lxc.network.type = veth
	lxc.network.flags = up
	# - name in host (max 15 chars; defaults to 'tun'+random)
	lxc.network.veth.pair = ${NAME}
	# - name in guest
	lxc.network.name = eth0
	# enable for bridging
	# (eg. 'brctl addbr br0; brctl setfd br0 0; brctl addif br0 eth0')
	#lxc.network.link = br0
	EOF

	if [ "${IPV4}" == "dhcp" ]; then
		cat <<- EOF >> "$CONFFILE"
		# disabled (guest uses DHCP)
		#lxc.network.ipv4 = X.X.X.X
		#lxc.network.ipv4.gateway = Y.Y.Y.Y   # or 'auto'
		EOF
	else
		cat <<- EOF >> "$CONFFILE"
		lxc.network.ipv4 = ${IPV4}
		lxc.network.ipv4.gateway = ${IPV4_GATEWAY}
		EOF
	fi

	if [ "${IPV6}" == "dhcp" ]; then
		cat <<- EOF >> "$CONFFILE"
		# disabled (guest uses DHCP)
		#lxc.network.ipv6 = X/X
		#lxc.network.ipv6.gateway = X/X    # or 'auto'
		EOF
	else
		cat <<- EOF >> "$CONFFILE"
		lxc.network.ipv6 = ${IPV6}
		lxc.network.ipv6.gateway = ${IPV6_GATEWAY}
		EOF
	fi

	cat <<- EOF >> "$CONFFILE"

	# root filesystem location
	lxc.rootfs = $(readlink -f "$ROOTFS")

	# mounts that allow us to drop CAP_SYS_ADMIN
	lxc.mount.entry=proc proc proc ro,nodev,noexec,nosuid 0 0
	# disabled for security, see http://blog.bofh.it/debian/id_413
	#lxc.mount.entry=sys sys sysfs defaults 0 0
	lxc.mount.entry=shm dev/shm tmpfs rw,nosuid,nodev,noexec,relatime 0 0
	lxc.mount.entry=tmp tmp tmpfs rw,nosuid,nodev,noexec 0 0
	lxc.mount.entry=run run tmpfs rw,nosuid,nodev,relatime,mode=755 0 0

	# if you are unable to emerge something due to low ram, tell emerge to build somewhere else:
	# e.g. # PORTAGE_TMPDIR=/path/to/some/directory/on/disk emerge -avu htop
	lxc.mount.entry=portagetmp var/portage/tmp tmpfs rw,nosuid,nodev 0 0

	EOF

	if [[ -d "$PORTAGE_SOURCE" ]]; then
		printf "lxc.mount.entry=%s var/portage/tree none ro,bind 0 0\n" "$PORTAGE_SOURCE" >> "$CONFFILE"
	fi

	cat <<- EOF >> "$CONFFILE"

	# console access
	lxc.tty = 1
	lxc.pts = 128

	# this part is based on 'linux capabilities', see: man 7 capabilities
	#  eg: you may also wish to drop 'cap_net_raw' (though it breaks ping)
	#
	# WARNING: the security vulnerability reported for 'cap_net_admin' at
	# http://mainisusuallyafunction.blogspot.com/2012/11/attacking-hardened-linux-systems-with.html
	# via JIT spraying (the BPF JIT module disabled on most systems was used
	# in the example, but others are suggested vulnerable) meant that users
	# with root in a container, that capability and kernel module may escape
	# the container. ALWAYS be extremely careful granting any process root
	# within a container, use a minimal configuration at all levels -
	# including the kernel - and multiple layers of security on any system
	# where security is a priority.  note that not only LXC but PAX (and
	# others?) were vulnerable to this issue.
	#
	# conservative: lxc.cap.drop = sys_module mknod mac_override
	# aggressive follows. (leaves open: chown dac_override fowner ipc_lock kill lease net_admin net_bind_service net_broadcast net_raw setgid setuid sys_chroot sys_boot)
	lxc.cap.drop = audit_control audit_write dac_read_search fsetid ipc_owner linux_immutable mac_admin mac_override mknod setfcap sys_admin sys_module sys_pacct sys_ptrace sys_rawio sys_resource sys_time sys_tty_config syslog

	# deny access to all devices by default, explicitly grant some permissions
	#
	# format is [c|b] [major|*]:[minor|*] [r][w][m]
	#            ^     ^                   ^
	# char/block -'     \`- device number    \`-- read, write, mknod
	#
	# first deny all...
	lxc.cgroup.devices.deny = a
	# /dev/null and zero
	lxc.cgroup.devices.allow = c 1:3 rw
	lxc.cgroup.devices.allow = c 1:5 rw
	# /dev/{,u}random
	lxc.cgroup.devices.allow = c 1:9 rw
	lxc.cgroup.devices.allow = c 1:8 r
	# /dev/pts/*
	lxc.cgroup.devices.allow = c 136:* rw
	lxc.cgroup.devices.allow = c 5:2 rw
	# /dev/tty{0,1}
	lxc.cgroup.devices.allow = c 4:1 rwm
	lxc.cgroup.devices.allow = c 4:0 rwm
	# /dev/tty
	lxc.cgroup.devices.allow = c 5:0 rwm
	# /dev/console
	lxc.cgroup.devices.allow = c 5:1 rwm
	# /dev/net/tun
	lxc.cgroup.devices.allow = c 10:200 rwm

	EOF
	echo "done."
}

set_guest_root_password()
{
	[[ -z "$GUESTROOTPASS" ]] && return # pass is empty, abort

	echo -n " - setting guest root password.."
	echo "root:$GUESTROOTPASS" | chroot "$ROOTFS" chpasswd
	echo "done."
}

# does not return on failure
verify_gpg()
{
	local signature="$1"
	local file="$2"
	local numargs=$#

	if [[ -d "$PGP_DIR" && -f "$PGP_DIR/pubring.gpg" ]]; then
		command -v gpg > /dev/null \
			|| die 2 "verify_gpg(): Error: GNU privacy guard (gpg) is not installed, unable to verify.\n"

		if [[ $numargs -eq 1 ]]; then
			# signed file, e.g. DIGESTS.asc
			gpg --homedir "$PGP_DIR" --verify "$signature" \
				|| die 7 "verify_gpg(): Error: Unable to verify attached PGP signature! Please refer to README, section PGP setup\n"
		else
			# detached signature, e.g. portage-latest.tar.bz2.gpgsig
			gpg --homedir "$PGP_DIR" --verify "$signature" "$file" \
				|| die 7 "verify_gpg(): Error: Unable to verify detached PGP signature! Please refer to README, section PGP setup\n"
		fi
	else
		printf "verify_gpg(): Warning: \$PGP_DIR is empty or not a directory or $PGP_DIR/pubring.gpg\n%s\n" \
		       "doesen't exist, disabling signature checking!"
	fi
}

# returns nonzero on failure
# sha512sum, etc. busybox seems to behave the same as coreutils
verify_with_stdutils()
{
	local program="$1"
	local known_hash="$2"
	local file_to_verify="$3"

	local stdout
	stdout="$($program "$file_to_verify")"
	local retval=$?

	if [[ $retval -ne 0 ]]; then
		printf "verify_with_stdoutils(): Error: '%s' returned nonzero (%s)\n" \
		       "'$program' '$file_to_verify'" "$retval"
		return 1
	else
		stdout="${stdout%% *}" # discard all but the hash

		if [[ "$stdout" == "$known_hash" ]]; then
			printf "verify_with_stdutils(): '%s': %s OK\n" "$file_to_verify" "$program"
		else
			printf "verify_with_stdutils(): Error: file '%s' differs on disk, %s checksum\n\t%s\nshould be\n\t%s\n" \
			       "$file_to_verify" "$program" "$stdout" "$known_hash"
			return 2
		fi
	fi

	return 0
}

# returns nonzero on failure
verify_with_openssl()
{
	local hash_type="$1"
	local known_hash="$2"
	local file_to_verify="$3"

	local stdout
	stdout="$(openssl "$hash_type" "$file_to_verify")"
	local retval=$?

	if [[ $retval -ne 0 ]]; then
		printf "verify_with_openssl(): Error: '%s' returned nonzero (%s)\n" \
		       "openssl '$file_to_verify'" "$retval"
		return 1
	else
		stdout="${stdout##* }" # discard all but the hash

		if [[ "$stdout" == "$known_hash" ]]; then
			printf "verify_with_openssl(): '%s': %s OK\n" "$file_to_verify" "$hash_type"
		else
			printf "verify_with_openssl(): Error: file '%s' differs on disk, %s checksum\n\t%s\n\tshould be\n\t%s\n" \
			       "$file_to_verify" "$hash_type" "$stdout" "$known_hash"
			return 2
		fi
	fi

	return 0
}

# returns program invocation on standard output
verify_find_hash_program()
{
	local hash_type="${1,,}" # to lower case

	# check if a standard utility exists and has the required hash
	if command -v "${hash_type}sum" > /dev/null; then
		printf "%ssum" "$hash_type"
		return 0
	fi

	# check if openssl exists and has the required hash
	if command -v openssl > /dev/null; then
		while read -r line; do
			if [[ "${line,,}" == "$hash_type" ]]; then
				printf "openssl %s" "$line"
				return 0
			fi
		done < <(openssl list-message-digest-algorithms)
	fi

	# check if busybox has the required hash
	if command -v busybox > /dev/null; then
		while read -r line; do
			if [[ "${line,,}" == "${hash_type}sum" ]]; then
				printf "busybox %s" "$line"
				return 0
			fi
		done < <(busybox --list)
	fi

	return 1
}

# returns nonzero on failure:
#   1 generic error
#   2 on hash mismatch
#	3 no hash checking program found for given hash
#	4 do not know how to invoke the above program
verify_hash()
{
	local hash_type="$1"
	local known_hash="$2"
	local file_to_verify="$3"

	local invocation
	invocation="$(verify_find_hash_program "$hash_type")"

	if [[ $? -ne 0 ]]; then
		return 3
	fi

	local program="${invocation%% *}" # strip everything but the first word
	local arguments="${invocation#* }" # strip first word

	if [[ "$program" == "openssl" ]]; then
		verify_with_openssl "$arguments" "$known_hash" "$file_to_verify"
		return $?
	elif [[ "$program" == "busybox" ]]; then
		verify_with_stdutils "$invocation" "$known_hash" "$file_to_verify"
		return $?
	elif [[ "$program" = *sum ]]; then
		verify_with_stdutils "$program" "$known_hash" "$file_to_verify"
		return $?
	else
		return 4
	fi
}

# parses a .DIGESTS file and attempts to verify the given file
verify_digests()
{
	local digest_file="$1"
	local file_to_verify="$2"

	[[ ! -f "$digest_file" ]]    && die 18 "verify_digests(): digest_file '%s' is not a file\n" "$digest_file"
	[[ ! -f "$file_to_verify" ]] && die 18 "verify_digests(): file_to_verify '%s' is not a file\n" "$file_to_verify"

	mapfile -t < "$digest_file"

	local state=""
	local verified=0
	local line_number=0

	for line in "${MAPFILE[@]}"; do
		(( line_number += 1 ))
		# default state: get next hash type
		if [[ "$state" == "" ]]; then
			if [[ "$line" = *HASH ]]; then
				local hashtype="${line##\# }" # remove '# ' at start
				hashtype="${hashtype%% HASH}" # remove ' HASH' at end

				state="$hashtype"
			fi
		else
			# these states are names of functions that will verify checksums
			known_hash="${line%%  *}" # remove everything but the hash
			known_file="${line##*  }" # remove everything but the filename
			last_component="${file_to_verify##*/}"

			if [[ "$last_component" == "$known_file" ]]; then
				verify_hash "$state" "$known_hash" "$file_to_verify"
				local return_value=$?

				if [[ $return_value -eq 0 ]]; then
					verified=1
				elif [[ $return_value -eq 2 ]]; then
					die 2 "verify_digests(): hash mismatch.\n"
				elif [[ $return_value -eq 3 ]]; then
					printf "verify_digests(): '%s':%s: Warning: no program exists for checking: '%s'\n" \
					       "$digest_file" "$line_number" "$hashtype"
				elif [[ $return_value -eq 4 ]]; then
					printf "verify_digests(): '%s':%s: Warning: I do not know what to do with the following: '%s'\n" \
					       "$digest_file" "$line_number" "$hashtype"
				fi
			fi
			state=""
		fi
	done

	[[ $verified -eq 0 ]] && die 2 "verify_digests(): Error: Unable to verify checksums for '%s',\n\tgiven digests '%s'\n" \
	                               "$file_to_verify" "$digest_file"
}

fetch_stage3()
{
	# base stage3 URL
	local stage3url="$MIRROR/releases/$ARCH/autobuilds"

	# get latest-stage3....txt file for subpath
	mkdir -p "$CACHE"
	local stage3latestSubPathUrl="$stage3url/latest-stage3-${ARCHVARIANT}.txt"

	printf "Determining path to latest Gentoo %s (%s) stage3 archive...\n" "$ARCH" "$ARCHVARIANT"
	printf " => downloading and processing %s\n" "$stage3latestSubPathUrl"

	local -a array_of_words
	array_of_words=($(${WGET} -q -O - "$stage3latestSubPathUrl")) \
		|| printf " => Failed.\n"

	# take the second last word and convert it to string form:
	latest_stage3_subpath="${array_of_words[-2]}"
	printf " => Got: %s\n" "$latest_stage3_subpath"


	# Download the actual stage3
	local output_file="$CACHE/stage3-$ARCH-$latest_stage3_subpath"
	if [[ -f "$output_file" ]]; then
		printf "Skipping download of stage3 as it is already present.\n"
	else
		printf "Downloading the actual stage3 tarball...\n"

		#  - ensure output directory exists
		local output_dir="${output_file%/*}"
		mkdir -p "$output_dir"

		#  - grab
		local input_url="$stage3url/$latest_stage3_subpath"
		printf " => %s ...\n" "$input_url"

		${WGET} -O "$output_file" "$input_url" \
			|| die 6 "Error: unable to fetch\n"
		printf " => saved to: %s\n" "$output_file"


		# Download the signature file
		printf " => Downloading the signature file\n"

		local input_url="$stage3url/$latest_stage3_subpath.DIGESTS.asc"
		local digest_file="$output_file.DIGESTS.asc"
		printf " => %s ...\n" "$input_url"

		wget -O "$digest_file" "$input_url" \
			|| die 6 "Error: unable to fetch\n"

		printf " => saved to: %s\n" "$digest_file"
	fi

	# used by calling function
	STAGE3_TARBALL="$output_file"
}

fetch_portage()
{
	local url="$MIRROR/snapshots/portage-latest.tar.bz2"
	local signature_url="$url.gpgsig"
	local dest="$CACHE/portage-latest.tar.bz2"
	local signature_dest="$dest.gpgsig"

	mkdir -p "$CACHE"
	if [[ ! -f "$dest" ]]; then
		# don't update
		printf "Downloading Gentoo portage (software build database) snapshot...\n"

		${WGET} -O "$dest" "$url" \
			|| die 6 "Error: unable to fetch\n"

		printf " => done.\n"
	fi

	if [[ ! -f "$signature_dest" ]]; then
		printf "Downloading Gentoo portage (software build database) snapshot GPG signatures...\n"

		${WGET} -O "$signature_dest" "$signature_url" \
			|| die 6 "Error: unable to fetch\n"

		printf " => done.\n"
	fi

	# used by calling function
	PORTAGE_SOURCE="$dest"
}

configure()
{
	if [[ -z ${QUIET} ]]; then
		# choose a container name, default is already in shell NAME variable
		read -p "What is the name for the container (recommended <=15 chars)? " -ei "$NAME" NAME


		# choose a hostname, default is the container name
		local domain=""
		if [[ $UTSNAME = *.* ]]; then
			domain=".${UTSNAME#*.}"
		fi
		read -p "What hostname[.domain] do you wish for this container ? " -ei "$NAME$domain" UTSNAME

		# ipv4 address
		read -p "What IPv4 IP address do you wish for this container ('dhcp' for DHCP, or '1.2.3.4/5') ? " -ei "$IPV4" IPV4

		# ipv4 gateway
		if [ "${IPV4}" != "dhcp" ]; then
			read -p "What is the IPv4 gateway IP address ? " -ei "$IPV4_GATEWAY" IPV4_GATEWAY
		fi

		# ipv6 address
		read -p "What IPv6 IP address do you wish for this container ('dhcp' for DHCP, or 'x/x') ? " -ei "$IPV6" IPV6

		# ipv6 gateway
		if [ "${IPV6}" != "dhcp" ]; then
			read -p "What is the IPv6 gateway IP address ? " -ei "$IPV6_GATEWAY" IPV6_GATEWAY

		fi

		# Type guest root password
		read -s -p "Type guest root password (enter for none/use already defined): "
		if [[ -n "$REPLY" ]]; then
			GUESTROOTPASS="$REPLY"
		fi
		printf "\n" # \n eaten by noecho

		if [[ -z "${STAGE3_TARBALL}" ]]; then
			# choose the mirror
			read -p "Which mirror to use for stage3 and Portage archive ? " -ei "$MIRROR" MIRROR

			# choose the container architecture
			local -a arches
			arches+=("alpha")
			arches+=("amd64")
			arches+=("arm")
			arches+=("hppa")
			arches+=("ia64")
			# arches+=("mips") # project only has experimental stages?
			arches+=("ppc")
			arches+=("s390")
			arches+=("sh")
			arches+=("sparc")
			arches+=("x86")

			printf "\n\nNote that you will have to set up Qemu? emulation yourself\n"
			printf "if your CPU cannot natively execute the chosen architecture (see README).\n"

			printf "\n\nSelect desired container architecture:\n"
			select ARCH in "${arches[@]}"; do
				if [[ -n "$ARCH" ]]; then
					break
				fi
			done

			printf "\nDownloading the list of available variants...\n"
			# we got a valid answer, proceed with variant list
			mapfile -t < <(${WGET} -O - "$MIRROR/releases/$ARCH/autobuilds")
			# I tried to check for errors here but failed miserably, hence the check
			# for an empty variant list down below.

			# parse the returned HTML for latest-stage3-VARIANT.txt
			local -a variants
			local variant

			for line in "${MAPFILE[@]}"; do
				if [[ "$line" = *latest-stage3-*.txt* ]]; then
					variant="${line#*latest-stage3-}"
					variant="${variant%%.txt*}"

					variants+=("$variant")
				fi
			done

			if [[ ${#variants[@]} -eq 0 ]]; then
				die 6 "variants list empty, see wget's output above\n"
			fi

			printf "\n\nSelect desired container subarchitecture/variant for %s:\n" "$ARCH"
			select ARCHVARIANT in "${variants[@]}"; do
				if [[ -n "$ARCHVARIANT" ]]; then
					break
				fi
			done
		fi

	fi

	if [[ -n "$CONFFILE" ]]; then
		if [[ -d "$CONFFILE" ]]; then
			CONFFILE="$CONFFILE/${NAME}.conf"
		# else
		#	we already have a valid config file name
		fi
	else
		CONFFILE="${NAME}.conf"
	fi

	echo "NAME           = $NAME"
	echo "UTSNAME        = $UTSNAME"
	echo "ROOTFS         = $ROOTFS"
	echo "CONFFILE       = $CONFFILE"
	echo "ARCH           = $ARCH"
	echo "ARCHVARIANT    = $ARCHVARIANT"
	echo "STAGE3_TARBALL = $STAGE3_TARBALL"
	echo "GUESTROOTPASS  = (not shown)"
	echo "MIRROR         = $MIRROR"
	echo "PORTAGE_SOURCE = $PORTAGE_SOURCE"
	echo "CACHE          = $CACHE"
	echo "IPV4           = $IPV4"
	echo "IPV4_GATEWAY   = $IPV4_GATEWAY"
	echo "IPV6           = $IPV6"
	echo "IPV6_GATEWAY   = $IPV6_GATEWAY"

	echo -e "Thanks! Now sit back and relax while your gentoo brews...\n\n"
	# nice pondering material
	if which fortune > /dev/null 2>&1 ; then
		echo '-----------------------------------------------------------------'
		if which cowsay > /dev/null 2>&1 ; then
			cowsay `fortune -s`
		else
			fortune
		fi
		echo -e "-----------------------------------------------------------------\n"
	fi
}

create()
{
	configure

	# never hurts to have a fail-safe.
	[[ -n "${NAME//\/}" ]] \
		|| die 8 "\$NAME (%s) IS EMPTY OR MADE OF ONLY DIRECTORY SEPERATORS, THIS IS *VERY* BAD!\n" "$NAME"

	# the rootfs name will be built with the container name
	ROOTFS="./${NAME}"

	# check if the conffile already exists
	[[ -e "$CONFFILE" ]] && die 18 "Error: config file (%s) already exists!\n" "$CONFFILE"

	# check if the rootfs already exists
	[[ -e "$ROOTFS" ]] && die 18 "Error: \$ROOTFS (%s) already exists!" "$ROOTFS"

	# the stage3 might not be possible to fetch, for isntance if we are offline. in that
	# case we use the latest one available. if that fails also, then we die.
	if [[ -z "$STAGE3_TARBALL" ]]; then
		# Fetch us a stage3
		execute_exclusively "${ARCH}_${ARCHVARIANT}_rootfs" fetch_stage3
		if [[ $? -ne 0 ]]; then
			# try to detect an existing stage3 (sorted to the latest mtime)
			STAGE3_TARBALL=`find $CACHE |grep '/stage3-'${ARCH} | grep tar | xargs ls -t1|head -n 1`
			if [[ ! -e "$STAGE3_TARBALL" ]]; then
				die 18 "ERROR: Failed to fetch stage3, and no previous stage3 available.\n"
			fi
			printf "      - Failed to fetch stage3, but found existing stage3 tarball instead.\n"
		fi
	fi

	verify_gpg "$STAGE3_TARBALL.DIGESTS.asc"
	verify_digests "$STAGE3_TARBALL.DIGESTS.asc" "$STAGE3_TARBALL"

	# variable is nonzero, try to unpack
	printf "\nUnpacking filesystem from %s to %s ... " "$STAGE3_TARBALL" "$ROOTFS"
	mkdir -p "$ROOTFS"

	tar -xpf "$STAGE3_TARBALL" -C "$ROOTFS"
	if [[ $? -ne 0 ]]; then
		printf "FAILED.\n"
		return 1
	else
		printf "done.\n"
	fi

	setup_portage

	write_lxc_configuration \
		|| die 1 "Error: Failed to write LXC configuration.\n"

	write_distro_inittab \
		|| die 1 "Error: Failed to write changes to inittab.\n"

	write_distro_hostname \
		|| die 1 "Error: Failed to write hostname.\n"

	populate_dev

	write_distro_fstab \
		|| die 1 "Error: Failed to write fstab\n"

	write_distro_timezone \
		|| die 1 "Error: Failed to write timezone\n"

	write_distro_network \
		|| die 1 "Error: Failed to write network configuration\n"

	write_distro_init_fixes \
		|| die 1 "Error: Failed to write init fixes\n"

	set_guest_root_password \
		|| die 1 "Error: Failed to set guest root password\n"

	cat <<-EOF
	All done!

	You can run your container with the 'lxc-start -f "$CONFFILE" -n "$NAME"'
	For host-side networking setup info, see "$ROOTFS/etc/conf.d/net"

	To enter your container for setup WITHOUT running it, try:
	   mount -t proc proc "$ROOTFS/proc"
	   mount -o bind /dev "$ROOTFS/dev"
	   chroot "$ROOTFS" /bin/bash
	   export PS1="(${NAME}) \$PS1"
	 (${NAME}) #   <-- you are now in the guest
	... or, start it on the current console with:
	   lxc-start -f "$CONFFILE" -n "$NAME"
	... or, start it elsewhere then use 'lxc-console -n "$NAME"' for a shell

	(Report bugs to https://github.com/globalcitizen/lxc-gentoo/issues )";
	EOF
}

destroy()
{
	printf "To destroy the container, just remove <container_name>* wherever you created it.\n"
	printf "Are you sure it is not running at the moment? (use lxc-kill -n <container_name> to stop/kill it.\n"
}

help()
{
	cat <<-EOF
	Usage: $0 {create|help} [options]
		-q : Quiet, use vars from env or options and do not ask me.
		-i IPV4 : IPv4 IP and netmask 'XX.XX.XX.XX/XX' or 'dhcp'.
			Current/Default: ${IPV4}
		-g IPV4_GATEWAY : IP address of the IPv4 gateway
			Current/Default: ${IPV4_GATEWAY}
		-i IPV6 : IPv6 IP and netmask 'X/X' or 'dhcp'.
			Current/Default: ${IPV6}
		-g IPV6_GATEWAY : IP address of the IPv6 gateway
			Current/Default: ${IPV6_GATEWAY}
		-n NAME : name of the container
			Current/Default: ${NAME}
		-u UTSNAME : hostname (+domain) of the container
			Current/Default: ${UTSNAME}
		-a ARCH : at the moment all but mips.
			Current/Default: ${ARCH}
		-p GUESTROOTPASS : password for root account
			Current/Default: ${GUESTROOTPASS}
		-m MIRROR : mirror for stage3 and Portage archive
			Current/Default: ${MIRROR}
		-t STAGE3_TARBALL : path to a stage3 archive to use
			Specifying this option will avoid fetching stage (or asking for arch, variant and mirror)
			Current: ${STAGE3_TARBALL} Default: null
		-P PORTAGE_SOURCE : path to a custom portage to use. Can be one of:
			 - tarball -- will be extracted
			 - directory -- will be bind-mounted read-only
			 - "none" -- do not set up a portage tree
			A portage snapshot will be downloaded if not specified
			Current: "$PORTAGE_SOURCE" Default: ""

	This script is a helper to create Gentoo system containers.

	To make a container, simply run:

	lxc-gentoo create

	You can override default by environnement variables or commandline options with this override sequence :
	default, env, cmdline option

	Example :
	$ IPV4_GATEWAY=10.0.0.254 ./lxc-gentoo create -i 10.0.0.1/24 -n gentooserver -u gentooserver

	An interactive script will ask you for various information.

	The first creation will download a Gentoo stage3 and portage
	snapshot and store it into a cache at "$CACHE".

	If you wish to remove the cache, point your file manager/shell into
	"$CACHE" and remove the files you consider unneeded.
	If you wish to update, remove the files that you consider unneeded,
	next lxc-gentoo create run will re-download needed ones.

	To destroy the container, just remove <container_name>* wherever you created it.
	Are you sure it is not running at the moment? (use lxc-stop/kill -n <container_name> to stop/kill it.

	Have fun :)

	(PS: Unix hackers with a conscience do not work for morally corrupt
		corporations or governments. Use your powers for good!)
	EOF
}

purge()
{
	cat <<- EOF
	If you wish to remove the cache, point your file manager/shell into
	"$CACHE" and remove the files you consider unneeded.
	If you wish to update, remove the files that you consider unneeded,
	next lxc-gentoo create run will re-download needed ones.
	EOF
}

fetch()
{
	configure
	# download
	execute_exclusively "${ARCH}_${ARCHVARIANT}_rootfs" fetch_stage3
	execute_exclusively "portage" fetch_portage
}

# Note: assuming uid==0 is root -- might break with userns??
if [ "$(id -u)" != "0" ]; then
	echo "This script should be run as 'root'"
	exit 1
fi

OPTIND=2
while getopts "i:g:n:u:a:p:m:t:P:q" opt; do
	case "$opt" in
		i) IPV4="$OPTARG" ;;
		g) IPV4_GATEWAY="$OPTARG" ;;
		I) IPV6="$OPTARG" ;;
		G) IPV6_GATEWAY="$OPTARG" ;;
		n) NAME="$OPTARG" ;;
		u) UTSNAME="$OPTARG" ;;
		a) ARCH="$OPTARG" ;;
		p) GUESTROOTPASS="$OPTARG" ;;
		m) MIRROR="$OPTARG" ;;
		t) STAGE3_TARBALL="$OPTARG" ;;
		P) PORTAGE_SOURCE="$OPTARG" ;;
		q) QUIET=Yes ;;
		\?) ;;
	esac
done

case "$1" in
	create)
		create;;
	destroy)
		destroy
		die 16 "destroy is to be removed\n" ;;
	fetch)
		fetch;;
	help)
		help;;
	purge)
		purge
		die 16 "purge is to be removed\n" ;;
	*)
		help
		exit 1;;
esac
