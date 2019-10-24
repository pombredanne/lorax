#!/bin/bash
# Note: execute this file from the project root directory

#####
#
# Builds qcow2 images and tests them with QEMU-KVM
#
#####

set -e

. /usr/share/beakerlib/beakerlib.sh
. $(dirname $0)/lib/lib.sh

CLI="${CLI:-./src/bin/composer-cli}"

rlJournalStart
    rlPhaseStartSetup
        rlAssertExists $QEMU_BIN
    rlPhaseEnd

    rlPhaseStartTest "compose start"
        rlAssertEquals "SELinux operates in enforcing mode" "$(getenforce)" "Enforcing"

        TMP_DIR=`mktemp -d /tmp/composer.XXXXX`
        SSH_KEY_DIR=`mktemp -d /tmp/composer-ssh-keys.XXXXXX`

        rlRun -t -c "ssh-keygen -t rsa -N '' -f $SSH_KEY_DIR/id_rsa"
        PUB_KEY=`cat $SSH_KEY_DIR/id_rsa.pub`

        cat > $TMP_DIR/with-ssh.toml << __EOF__
name = "with-ssh"
description = "HTTP image with SSH"
version = "0.0.1"

[[packages]]
name = "httpd"
version = "*"

[[packages]]
name = "openssh-server"
version = "*"

[[customizations.user]]
name = "root"
key = "$PUB_KEY"

[customizations.kernel]
append = "custom_cmdline_arg"
__EOF__

        rlRun -t -c "$CLI blueprints push $TMP_DIR/with-ssh.toml"

        UUID=`$CLI compose start with-ssh qcow2`
        rlAssertEquals "exit code should be zero" $? 0

        UUID=`echo $UUID | cut -f 2 -d' '`
    rlPhaseEnd

    rlPhaseStartTest "compose finished"
        wait_for_compose $UUID
        rlRun -t -c "$CLI compose image $UUID"
        IMAGE="$UUID-disk.qcow2"
    rlPhaseEnd

    rlPhaseStartTest "Start VM instance"
        boot_image "-boot c -hda $IMAGE" 60
    rlPhaseEnd

    rlPhaseStartTest "Verify VM instance"
        # run generic tests to verify the instance
        verify_image root localhost "-i $SSH_KEY_DIR/id_rsa -p $SSH_PORT"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun -t -c "killall -9 qemu-system-$(uname -m)"
        rlRun -t -c "$CLI compose delete $UUID"
        rlRun -t -c "rm -rf $IMAGE $TMP_DIR $SSH_KEY_DIR"
    rlPhaseEnd

rlJournalEnd
rlJournalPrintText
