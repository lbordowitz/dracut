#!/bin/sh

do_fipskernel()
{
    boot=$(getarg boot=)
    KERNEL=$(uname -r)
    case "$boot" in
    LABEL=*)
        boot="$(echo $boot | sed 's,/,\\x2f,g')"
        boot="/dev/disk/by-label/${boot#LABEL=}"
        ;;
    UUID=*)
        boot="/dev/disk/by-uuid/${boot#UUID=}"
        ;;
    /dev/*)
        ;;
    *)
        die "You have to specify boot=<boot device> as a boot option for fips=1" ;;
    esac

    if ! [ -e "$boot" ]; then
        udevadm trigger --action=add >/dev/null 2>&1
        [ -z "$UDEVVERSION" ] && UDEVVERSION=$(udevadm --version)

        if [ $UDEVVERSION -ge 143 ]; then
            udevadm settle --exit-if-exists=$boot
        else
            udevadm settle --timeout=30
        fi
    fi

    [ -e "$boot" ]

    mkdir /boot
    info "Mounting $boot as /boot"
    mount -oro "$boot" /boot

    info "Checking integrity of kernel"

    if ! [ -e "/boot/.vmlinuz-${KERNEL}.hmac" ]; then
        warn "/boot/.vmlinuz-${KERNEL}.hmac does not exist"
        return 1
    fi

    sha512hmac -c "/boot/.vmlinuz-${KERNEL}.hmac" || return 1

    info "Umounting /boot"
    umount /boot
}

do_fips()
{
    FIPSMODULES=$(cat /etc/fipsmodules)

    if ! getarg rd.fips.skipkernel >/dev/null; then
	do_fipskernel
    fi
    info "Loading and integrity checking all crypto modules"
    for module in $FIPSMODULES; do
        if [ "$module" != "tcrypt" ]; then
            modprobe ${module} || return 1
        fi
    done
    info "Self testing crypto algorithms"
    modprobe tcrypt || return 1
    rmmod tcrypt
    info "All initrd crypto checks done"  

    return 0
}

if ! fipsmode=$(getarg fips) || [ $fipsmode = "0" ]; then
    rm -f /etc/modprobe.d/fips.conf >/dev/null 2>&1
else
    set -e
    do_fips || die "FIPS integrity test failed"
    set +e
fi

# vim:ts=8:sw=4:sts=4:et
