#!/bin/sh
#
# SPDX-License-Identifier: GPL-2.0-or-later
# SPDX-FileCopyrightText: 2026 SonicDE Community

# shellcheck disable=SC2009
# shellcheck disable=SC2016
set -e -u


# Functions

msg() {
	printf "$1\n"
}

yesno() {
	printf "$1 (y/n): " ; read -r _ANS
	test "$_ANS" = 'y' -o "$_ANS" = 'Y'  && return 0
}

die() {
	printf "$1\n" ; exit 1
}

thank_you() {
	printf "$THANKS_MSG\n"
	cd "$_OLDPWD"
	exit 0
}


# Constants

VERS='0.3.0'
PGP_KEY='3B87898C73F11DF5'
ORIG_URL='https://sonicde-arch.github.io'
REPO_URL="$ORIG_URL/\$arch"

THANKS_MSG="\nThank you for choosing SonicDE! Please see $ORIG_URL for any further information."
_OLDPWD="$(pwd)"

DL_CMD=
test "$(command -v curl)" && DL_CMD='curl --remote-name'
test "$(command -v wget)" && DL_CMD='wget --no-globber'

SUDO_CMD=
test "$(command -v doas)" && SUDO_CMD='doas'
test "$(command -v sudo)" && SUDO_CMD='sudo'


# Pretext and Prechecks

cat <<-EO_INTRO
	SonicDE.org sonic-switch.sh, version: $VERS.

	This script will install SonicDE on your Arch Linux system. It will restart your
	graphical session so please save all your work. It will also silently replace the
	conflicting KDE components with the SonicDE ones.
EO_INTRO

test "$DL_CMD" || die '\nNo `curl` or `wget` command found. Please install one.'
test "$SUDO_CMD" || die '\nNo `doas` or `sudo` command found. Please install one.'

# FIXME The test has to work on CachyOS, EndeavourOS, and all the other Arches.
test "$(grep -i "^ID=['\"]*arch['\"]*$" /etc/os-release)" || die "$(cat <<-'EO_NOARCH'

	This script only works on Arch Linux and its derivatives. Please see https://sonicde.org
	for SonicDE packages suitable for other distributions and operating systems. Aborting.
EO_NOARCH
)"

yesno "\nAre you ready to switch to SonicDE?" || exit 0


# Main

_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}"/sonic-switch.XXXXXXXX)"
cd "$_WORKDIR" || die "\nCouldn't change into workdir ${_WORKDIR}."

set +e
$SUDO_CMD pacman-key -l "$PGP_KEY" >/dev/null 2>pacman-key.err
if [ "$(cat pacman-key.err)" ] ; then
	set -e
	msg '\nImporting the SonicDE for Arch Linux package signing key:'
	$DL_CMD https://sonicde-arch.github.io/sonicde-archlinux.asc
	sudo pacman-key --add sonicde-archlinux.asc
	sudo pacman-key --finger "$PGP_KEY"
	yesno "$(cat <<-EO_FPM
		Please compare the key fingerprint to the one at $ORIG_URL.
		Does it look right?
EO_FPM
)" || die '\nWrong fingerprint. Aborting.'
	sudo pacman-key --lsign-key "$PGP_KEY"
fi

set +e
RES="$(grep '^\[sonicde\]' /etc/pacman.conf)"
if [ "$RES" ] ; then
	msg '\The SonicDE repository is already in your pacman.conf. Proceeding.'
else
	set -e
	msg '\nAdding the SonicDE repository to your `/etc/pacman.conf`:'
	$SUDO_CMD tee -a /etc/pacman.conf <<-EO_REPO

	[sonicde]
	Server = $REPO_URL
EO_REPO
fi
set -e


msg '\nUpdating your packages:'
$SUDO_CMD pacman -Syyu

msg '\nInstalling SonicDE:'
yes | $SUDO_CMD pacman -S --needed sonicde-meta


## Login Manager Replacement

set +e
_RE="$(printf '%s' "$KNOWN_LMS" | tr ' ' '|')"
LM_NAME="$(ps -A -o comm= | grep -E "^(${_RE})$")"

test "$LM_NAME" = 'soniclogin' && thank_you
yesno "$(cat <<-EO_LMSW

	You're currently using the \`$LM_NAME\` login manager. Do you want to switch to the
	Sonic Login Manager?
EO_LMSW
)" || thank_you

set -e

$SUDO_CMD pacman -S --needed --noconfirm sonic-login-manager


msg "$THANKS_MSG"
msg '\nSwitching to the Sonic Login Manager (soniclogin) in 3 seconds.'
msg "You can find a log at ${_WORKDIR}/nohup.out."
sleep 3

nohup $SUDO_CMD sh -c "$SWITCH_CMD"
