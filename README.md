# Minimal Defensec SELinux Security Policy Version 2

## Introduction

Minimal DSSP (Version2) was designed to provide a template to build the widest array of configurations on top of that address custom access control challenges. A delicate balance was struck to provide just enough tooling to allow one to focus on productivity by making as little assumptions as possible about specific use cases.

A comprehensive set of optional templates, class mappings, class permissions and macros are provided by default to encourage efficient, consistent, and self documenting policy configuration.


## Leverages Common Intermediate Language

Common Intermediate Language is a language that is native to SELinux and that implements functionality inspired by popular features of Tresys Reference policy without the need for a pre-processor.

The source policy oriented nature of CIL provides enhanced accessibility and modularity. Text-based configuration makes it easier to resolve dependencies and to profile.

New language features allow authors to focus on creativity and productivity. Clear and simple syntax makes it easy to parse and generate security policy.


## Requirements

DSSP requires `semodule` or `secilc` >= 2.8 and Linux 4.16

SELinux should be enabled in the Linux kernel, your file systems should support `security extended attributes` and this support should be enabled in the Linux kernel.


## Installation with semodule: useful for systems where policy needs to be mutable at runtime (example: GNU/Linux distributions)

    git clone --recurse https://github.com/defensec/dssp2-minimal
    cd dssp2-minimal
    make install-semodule
    cat > /etc/selinux/config <<EOF
    SELINUX=permissive
    SELINUXTYPE=dssp2-minimal
    EOF
    echo "-F" > /.autorelabel
    reboot


## Installation with secilc: useful for systems where policy does not need to be mutable at runtime (example: embedded)

    git clone --recurse https://github.com/defensec/dssp2-minimal
    cd dssp2-minimal
    make install-config
    make
    mkdir -p /etc/selinux/dssp2-minimal/policy
    cp policy.* /etc/selinux/dssp2-minimal/policy/
    cp file_contexts /etc/selinux/dssp2-minimal/contexts/files/
    cat > /etc/selinux/config <<EOF
    SELINUX=permissive
    SELINUXTYPE=dssp2-minimal
    EOF
    cat > /etc/selinux/dssp2-minimal/seusers <<EOF
    root:sys.id:s0-s0
    __default__:sys.id:s0-s0
    EOF
    echo "-F" > /.autorelabel
    reboot


## Known issues

Add checkreqprot=0 to kernel boot line to help prevent bypassing of SELinux memory protection

When installing dssp2-minimal on an existing fedora installation some contexts of directories in the root filesystem become invalid

    mount --bind / /mnt
    chcon -u sys.id -r sys.role -t fs.sysfs.fs /mnt/sys
    chcon -u sys.id -r sys.role -t files.generic_runtime.runtime_file /mnt/run
    chcon -u sys.id -r sys.role -t fs.proc.fs /mnt/proc
    chcon -u sys.id -r sys.role -t fs.devtmpfs.fs /mnt/dev
    chcon -u sys.id -r sys.role -t files.generic_boot.boot_file /mnt/boot
    chcon -R -u sys.id -r sys.role -t fs.tmpfs.fs /mnt/tmp
    setenforce 0
    rm -rf /mnt/tmp/*
    rm -rf /mnt/tmp/.*
    setenforce 1
    umount /mnt
    umount /boot/efi
    restorecon -RF /boot/efi
    mount /dev/sda1 /boot/efi
    setsebool -P sys.mounton_invalid_dir off

Various `systemd` socket units and `systemd-tmpfiles` configuration snippets may refer to `/var/run` instead of `/run` and this causes them to create content with the wrong security context.

Fedora:

    cp /usr/lib/tmpfiles.d/pam.conf /etc/tmpfiles.d/ && \
       sed -i 's/\/var\/run/\/run/' /etc/tmpfiles.d/pam.conf

    cp /usr/lib/tmpfiles.d/certmonger.conf /etc/tmpfiles.d/ && \
       sed -i 's/\/var\/run/\/run/' /etc/tmpfiles.d/certmonger.conf

    cp /usr/lib/tmpfiles.d/mdadm.conf /etc/tmpfiles.d/ && \
       sed -i 's/\/var\/run/\/run/' /etc/tmpfiles.d/mdadm.conf

    cp /usr/lib/tmpfiles.d/pptp.conf /etc/tmpfiles.d/ && \
       sed -i 's/\/var\/run/\/run/' /etc/tmpfiles.d/pptp.conf

    cp /usr/lib/tmpfiles.d/radvd.conf /etc/tmpfiles.d/ && \
       sed -i 's/\/var\/run/\/run/' /etc/tmpfiles.d/radvd.conf

    cp /usr/lib/tmpfiles.d/spice-vdagentd.conf /etc/tmpfiles.d/ && \
       sed -i 's/\/var\/run/\/run/' /etc/tmpfiles.d/spice-vdagentd.conf

    cp /usr/lib/tmpfiles.d/vpnc.conf /etc/tmpfiles.d/ && \
       sed -i 's/\/var\/run/\/run/' /etc/tmpfiles.d/vpnc.conf

    cp /usr/lib/tmpfiles.d/sudo.conf /etc/tmpfiles.d/ && \
       sed -i 's/\/var\/run/\/run/' /etc/tmpfiles.d/sudo.conf

    cp /usr/lib/tmpfiles.d/samba.conf /etc/tmpfiles.d/ && \
       sed -i 's/\/var\/run/\/run/' /etc/tmpfiles.d/samba.conf

    cp /lib/systemd/system/cups.socket /etc/systemd/system/ && \
       sed -i 's/\/var\/run/\/run/' /etc/systemd/system/cups.socket

    cp /lib/systemd/system/virtlockd-admin.socket /etc/systemd/system/ && \
       sed -i 's/\/var\/run/\/run/' /etc/systemd/system/virtlockd-admin.socket

    cp /lib/systemd/system/virtlockd.socket /etc/systemd/system/ && \
       sed -i 's/\/var\/run/\/run/' /etc/systemd/system/virtlockd.socket

    cp /lib/systemd/system/virtlogd-admin.socket /etc/systemd/system/ && \
       sed -i 's/\/var\/run/\/run/' /etc/systemd/system/virtlogd-admin.socket

    cp /lib/systemd/system/virtlogd.socket /etc/systemd/system/ && \
       sed -i 's/\/var\/run/\/run/' /etc/systemd/system/virtlogd.socket

    cp /lib/systemd/system/sssd-kcm.socket /etc/systemd/system/ && \
       sed -i 's/\/var\/run/\/run/' /etc/systemd/system/sssd-kcm.socket

    cp /lib/systemd/system/sssd-secrets.socket /etc/systemd/system/ && \
       sed -i 's/\/var\/run/\/run/' /etc/systemd/system/sssd-secrets.socket

Debian:

    cp /usr/lib/tmpfiles.d/sshd.conf /etc/tmpfiles.d/ && \
        sed -i 's/\/var\/run/\/run/' /etc/tmpfiles.d/sshd.conf

    cp /lib/systemd/system/dbus.socket /etc/systemd/system/ && \
        sed -i 's/\/var\/run/\/run/' /etc/systemd/system/dbus.socket

    cp /lib/systemd/system/avahi-daemon.socket /etc/systemd/system/ && \
        sed -i 's/\/var\/run/\/run/' /etc/systemd/system/avahi-daemon.socket

Gentoo:

    cp /usr/lib/systemd/system/dbus.socket /etc/systemd/system/ && \
        sed -i 's/\/var\/run/\/run/' /etc/systemd/system/dbus.socket

To avoid dumping of core with Xserver/Xwayland:

    cat /etc/selinux/dssp2-minimal/contexts/x_contexts > /etc/X11/xorg.conf.d/99-selinux.conf

Configuration of /etc/selinux/semanage.conf:

    module-store = direct
    expand-check = 1
    usepasswd = false

    [sefcontext_compile]
    path = /usr/sbin/sefcontext_compile
    args = -r $@
    [end]

## Getting started with Hello World! (requires installation with semodule)

    cat > /usr/local/bin/helloworld.sh <<EOF
    #!/bin/bash
    echo "Hello World! from: \`id -Z\`"
    EOF
    chmod +x /usr/local/bin/helloworld.sh
    cat > helloworld.cil <<EOF
    (block helloworld
        (blockinherit system_agent_template)

        (typepermissive subj)

        (filecon "/usr/bin/helloworld\.sh" file cmd_file_context))
    (in sys
        (call helloworld.auto_subj_type_transition (isid)))
    EOF
    semodule -i helloworld.cil
    restorecon /usr/local/bin/helloworld.sh
    /usr/local/bin/helloworld.sh


## Resources

* [Common Intermediate Language](https://github.com/SELinuxProject/selinux/blob/master/secilc/docs/README.md) Learn to speak CIL
