#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 Red Hat, Inc.
#
# Tests for the lsmcli bash completion script.  A stub 'lsmcli' is put first in
# PATH so the value look-ups return known values.  Every list type includes an
# entry containing command substitution, which the completion code must offer
# verbatim and must never evaluate.

set -u

srcdir=${srcdir:-$(dirname "$0")}
completion_script="${srcdir}/lsmcli"

if [[ ! -r ${completion_script} ]] ; then
    echo "Cannot read completion script ${completion_script}" >&2
    exit 1
fi

tmp_dir=$(mktemp -d) || exit 1
trap 'rm -rf "${tmp_dir}"' EXIT

# Created by the payload if it ever gets evaluated, and by the stub every time
# it is run.
export LSM_TEST_MARKER="${tmp_dir}/payload_ran"
export LSM_TEST_CALLED="${tmp_dir}/lsmcli_called"

# The literal string the stub returns as a value.  Single quoted so it stays
# unevaluated here; if the completion code expands it the marker shows up.
PAYLOAD='$(touch ${LSM_TEST_MARKER})'

cat > "${tmp_dir}/lsmcli" <<'STUB'
#!/usr/bin/env bash
# Stub lsmcli returning terse ('#' separated) output for the requested --type.
touch "${LSM_TEST_CALLED}"

list_type=''
ag=''
while [[ $# -gt 0 ]] ; do
    case "$1" in
        --type) list_type="$2" ; shift 2 ;;
        --ag) ag="$2" ; shift 2 ;;
        --fs) shift 2 ;;
        *) shift ;;
    esac
done

payload='$(touch ${LSM_TEST_MARKER})'

case "${list_type}" in
    # 'sys three' proves a value containing a space survives as one entry.
    systems) printf '%s\n' "${payload}#sys desc" "sys-one#desc" "sys-two#desc" \
                           "sys three#desc" ;;
    pools) printf '%s\n' "${payload}#pool desc" "pool-one#desc" ;;
    volumes) printf '%s\n' "${payload}#vol desc" "vol-one#desc" ;;
    disks) printf '%s\n' "${payload}#disk desc" "disk-one#desc" ;;
    exports) printf '%s\n' "${payload}#export desc" "export-one#desc" ;;
    target_ports) printf '%s\n' "${payload}#tgt desc" "tgt-one#desc" ;;
    fs) printf '%s\n' "${payload}#fs desc" "fs-one#desc" ;;
    snapshots) printf '%s\n' "${payload}#snap desc" "snap-one#desc" ;;
    nfs_client_auth) printf '%s\n' "${payload}" "standard" ;;
    access_groups)
        # Third column is the initiator, which is what --init completes with.
        if [[ -n ${ag} ]] ; then
            printf '%s\n' "${ag}#ag name#init-filtered#ISCSI"
        else
            printf '%s\n' "ag-one#ag name#${payload}#ISCSI" \
                          "ag-two#ag name#init-two#ISCSI"
        fi
        ;;
esac
STUB
chmod +x "${tmp_dir}/lsmcli"

export PATH="${tmp_dir}:${PATH}"
export LSMCLI_AUTO_COMPLETE_VALUE=1

# shellcheck source=tools/bash_completion/lsmcli
source "${completion_script}"

failures=0

# Run _lsm for a command line and compare the resulting COMPREPLY.
# $1 The words already on the command line
# $2 The word being completed
# $3 Expected COMPREPLY entries, '|' separated
function check()
{
    local comp_line="$1"
    local cur="$2"
    local expected="$3"
    local -a words
    local actual

    read -r -a words <<< "${comp_line}"
    COMP_WORDS=("${words[@]}" "${cur}")
    COMP_CWORD=${#words[@]}
    COMPREPLY=()

    _lsm

    actual=$(IFS='|' ; echo "${COMPREPLY[*]+${COMPREPLY[*]}}")
    if [[ ${actual} != "${expected}" ]] ; then
        echo "FAIL: '${comp_line} ${cur}'"
        echo "      expected: ${expected}"
        echo "      actual:   ${actual}"
        failures=$(( failures + 1 ))
    fi
}

# Command line                                | word | expected completions
tests=(
    "lsmcli capabilities --sys|            |${PAYLOAD}|sys-one|sys-two|sys three"
    "lsmcli capabilities --sys|sys-o       |sys-one"
    "lsmcli capabilities --sys|nomatch     |"
    "lsmcli volume-create --pool|          |${PAYLOAD}|pool-one"
    "lsmcli volume-delete --vol|           |${PAYLOAD}|vol-one"
    "lsmcli volume-replicate-range --src-vol| |${PAYLOAD}|vol-one"
    "lsmcli volume-replicate-range --dst-vol| |${PAYLOAD}|vol-one"
    "lsmcli volume-raid-create --disk|     |${PAYLOAD}|disk-one"
    "lsmcli volume-mask --ag|              |ag-one|ag-two"
    "lsmcli access-group-create --init|    |${PAYLOAD}|init-two"
    "lsmcli list --nfs-export|             |${PAYLOAD}|export-one"
    "lsmcli list --tgt|                    |${PAYLOAD}|tgt-one"
    "lsmcli fs-delete --fs|                |${PAYLOAD}|fs-one"
    "lsmcli fs-clone --src-fs|             |${PAYLOAD}|fs-one"
    "lsmcli fs-unexport --export|          |${PAYLOAD}|export-one"
    "lsmcli fs-export --auth-type|         |${PAYLOAD}|standard"
    # Filtered look-ups, where another argument narrows the result.
    "lsmcli access-group-add --ag ag-one --init| |init-filtered"
    "lsmcli fs-snap-delete --fs fs-one --snap|   |${PAYLOAD}|snap-one"
    # --snap without a --fs has nothing to offer.
    "lsmcli fs-snap-delete --snap|         |"
    # A value is matched literally, no globbing and no expansion.
    "lsmcli capabilities --sys|\$(          |${PAYLOAD}"
    "lsmcli capabilities --sys|*           |"
)

for t in "${tests[@]}" ; do
    IFS='|' read -r comp_line cur expected_head rest <<< "${t}"
    expected="${expected_head}"
    [[ -n ${rest} ]] && expected="${expected_head}|${rest}"
    # Trailing blanks in the table keep the columns readable.
    check "${comp_line}" "${cur%% *}" "${expected}"
done

# Nothing above may have run the payload.
if [[ -e ${LSM_TEST_MARKER} ]] ; then
    echo "FAIL: completion evaluated a returned value"
    failures=$(( failures + 1 ))
fi

# With value look-up off, which is the default, lsmcli is never run.
rm -f "${LSM_TEST_CALLED}"
env -u LSMCLI_AUTO_COMPLETE_VALUE bash --noprofile --norc -c '
    source "$1"
    COMP_WORDS=(lsmcli capabilities --sys "")
    COMP_CWORD=3
    _lsm' _ "${completion_script}"
if [[ -e ${LSM_TEST_CALLED} ]] ; then
    echo "FAIL: lsmcli run with value look-up disabled"
    failures=$(( failures + 1 ))
fi

if [[ ${failures} -ne 0 ]] ; then
    echo "${failures} completion test(s) failed"
    exit 1
fi

echo "All completion tests passed"
exit 0
