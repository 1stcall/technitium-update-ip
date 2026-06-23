#!/usr/bin/env bash
set -euo pipefail

# Set sane defaults
export REPO=1stcall/technitium-update-ip
export BRANCH=main
export INSTALLPATH=/usr/bin
export CONFPATH=/etc/tddns
export VERBOSE=1
export DOWNTEMP

# Helper functions
log() {
    local verbose_level="$1"
    shift
    if [ "$verbose_level" -le "$VERBOSE" ]; then
        if [ "$verbose_level" -ge 2 ]; then
            exec 3>&2
        else
            exec 3>&1
        fi

        if [ "$verbose_level" -eq 0 ]; then
            exec 3>/dev/null
        fi

        echo -e "$(date +%Y-%m-%d\ %H:%M:%S) : $*" 1>&3
        exec 3>&-
    fi
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --repository URL     URL of the repository to install from (default: 1stcall/technitium-update-ip)."
    echo "  -b, --branch BRANCH      Branch to install (default: main)."
    echo "  -i, --installpath PATH   Installation path (default: /usr/bin)."
    echo "  -c, --configpath PATH    Configuration path (default: /etc/tddns)."
    echo "  -h, --help               Show this help menu."
    echo ""
    exit 0
}

# Parse Command Line Arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--repo|--repository) REPO="$2"; shift 2 ;;
        -b|--branch)            BRANCH="$2"; shift 2 ;;
        -i|--installpath)       INSTALLPATH="$2"; shift 2 ;;
        -c|--confpath)          CONFPATH="$2"; shift 2 ;;
        -h|--help)              show_help ;;
        -v|--verbose)           VERBOSE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; show_help ;;
    esac
done

# Show configuration
log 2 "REPO         :   $REPO"
log 2 "BRANCH       :   $BRANCH"
log 2 "INSTALLPATH  :   $INSTALLPATH"
log 2 "CONFPATH     :   $CONFPATH"
log 2 "VERBOSE      :   $VERBOSE"
log 2 ""

##########################################################################################
# Main processing starts here.

# Download required files to a tempory folder.
log 1 "Downloading required files from github."
DOWNTEMP=$(mktemp -d)
for file in tddns.sh tddns.conf.example tddns.service tddns.timer; do
    log 2 "Running : curl -so $DOWNTEMP/$file \\
                        https://raw.githubusercontent.com/$REPO/refs/heads/$BRANCH/$file"
    curl --fail-with-body -so "$DOWNTEMP/$file" https://raw.githubusercontent.com/"$REPO"/refs/heads/"$BRANCH"/"$file"
done

# Update tddns.service with the instalation & config paths.
log 1 "Configureing service file."
log 2 "Running : sed -i -e \"s|\[INSTALLPATH\]|$INSTALLPATH|g\" $DOWNTEMP/tddns.service"
sed -i -e "s|\[INSTALLPATH\]|$INSTALLPATH|g" "$DOWNTEMP"/tddns.service
log 2 "Running : sed -i -e \"s|\[CONFIGPATH\]|$CONFPATH\" $DOWNTEMP/tddns.service"
sed -i -e "s|\[CONFIGPATH\]|$CONFPATH|g" "$DOWNTEMP"/tddns.service

# Ensure destination folders exist.
log 2 "$(/usr/bin/mkdir -pv "$CONFPATH" "$INSTALLPATH")"

# Copy requred files to there destinations
log 1 "Installing files."
log 2 "$(/usr/bin/install -vm 0755 "$DOWNTEMP"/tddns.sh "$INSTALLPATH"/)"
log 2 "$(/usr/bin/install -vm 0644 "$DOWNTEMP"/tddns.conf.example "$CONFPATH"/tddns.conf)"
log 2 "$(/usr/bin/install -vm 0644 "$DOWNTEMP"/tddns.service /lib/systemd/system/)"
log 2 "$(/usr/bin/install -vm 0644 "$DOWNTEMP"/tddns.timer /lib/systemd/system/)"

# Make tddns.sh exicutable
#log 2 $(chmod -v +x "$INSTALLPATH"/tddns.sh)

# Remove tempory files & folder.
log 1 "Cleaning up."
log 2 $(rm -rv "$DOWNTEMP")

log 1 "Complete."
exit 0
