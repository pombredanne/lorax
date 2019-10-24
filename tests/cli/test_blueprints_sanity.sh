#!/bin/bash
# Note: execute this file from the project root directory

set -e

. /usr/share/beakerlib/beakerlib.sh
. $(dirname $0)/lib/lib.sh

CLI="${CLI:-./src/bin/composer-cli}"


rlJournalStart
    rlPhaseStartTest "blueprints list"
        for bp in example-http-server example-development example-atlas; do
            rlAssertEquals "blueprint list finds $bp" \
                "`$CLI blueprints list | grep $bp`" "$bp"
        done
    rlPhaseEnd

    rlPhaseStartTest "blueprints save"
        rlRun -t -c "$CLI blueprints save example-http-server"
        rlAssertExists "example-http-server.toml"
        rlAssertGrep "example-http-server" "example-http-server.toml"
        rlAssertGrep "httpd" "example-http-server.toml"

        # non-existing blueprint
        rlRun -t -c "$CLI blueprints save non-existing-bp" 1
        rlAssertNotExists "non-existing-bp.toml"
    rlPhaseEnd

    rlPhaseStartTest "blueprints push"

        cat > beakerlib.toml << __EOF__
name = "beakerlib"
description = "Start building tests with beakerlib."
version = "0.0.1"
modules = []
groups = []
[[packages]]
name = "beakerlib"
version = "*"
__EOF__

        rlRun -t -c "$CLI blueprints push beakerlib.toml"
        rlAssertEquals "pushed bp is found via list" "`$CLI blueprints list | grep beakerlib`" "beakerlib"
        rlAssertExists "$BLUEPRINTS_DIR/git/workspace/master/beakerlib.toml"
    rlPhaseEnd

    rlPhaseStartTest "blueprints show"
        rlAssertEquals "show displays blueprint in TOML" "`$CLI blueprints show beakerlib`" "`cat beakerlib.toml`"
    rlPhaseEnd

    rlPhaseStartTest "SemVer .patch version is incremented automatically"
        # version is still 0.0.1
        rlAssertEquals "version is 0.0.1" "`$CLI blueprints show beakerlib | grep 0.0.1`" 'version = "0.0.1"'
        # add a new package to the existing blueprint
        cat >> beakerlib.toml << __EOF__

[[packages]]
name = "php"
version = "*"
__EOF__
        # push again
        rlRun -t -c "$CLI blueprints push beakerlib.toml"
        # official documentation says:
        # If a new blueprint is uploaded with the same version the server will
        # automatically bump the PATCH level of the version. If the version
        # doesn't match it will be used as is.
        rlAssertEquals "version is 0.0.2" "`$CLI blueprints show beakerlib | grep 0.0.2`" 'version = "0.0.2"'
    rlPhaseEnd

    rlPhaseStartTest "blueprints delete"
        rlRun -t -c "$CLI blueprints delete beakerlib"
        rlAssertEquals "bp not found after delete" "`$CLI blueprints list | grep beakerlib`" ""
        rlAssertNotExists "$BLUEPRINTS_DIR/git/workspace/master/beakerlib.toml"
    rlPhaseEnd

    rlPhaseStartTest "start a compose with deleted blueprint"
        cat > to-be-deleted.toml << __EOF__
name = "to-be-deleted"
description = "Dummy blueprint for testing compose start with a deleted blueprint"
version = "0.0.1"
__EOF__

        rlRun -t -c "$CLI blueprints push to-be-deleted.toml"
        rlRun -t -c "$CLI blueprints delete to-be-deleted"
        rlRun -t -c "$CLI compose list | grep to-be-deleted" 1
        rlRun -t -c "$CLI blueprints list | grep to-be-deleted" 1
        compose_id=$($CLI compose start to-be-deleted tar)
        rlAssertEquals "composer-cli exited with 1 when starting a compose using a deleted blueprint" "$?" "1"
        compose_id=$(echo $compose_id | cut -f 2 -d' ')

        if [ -z "$compose_id" ]; then
            rlPass "It wasn't possible to start a compose using a deleted blueprint."
        else
            rlFail "It was possible to start a compose using a deleted blueprint!"
            # don't wait for the compose to finish if it started unexpectedly, and do cleanup
            rlRun -t -c "$CLI compose cancel $compose_id"
            rlRun -t -c "$CLI compose delete $compose_id"
        fi

        rlRun -t -c "rm -f to-be-deleted.toml"
        unset compose_id
    rlPhaseEnd

rlJournalEnd
rlJournalPrintText
