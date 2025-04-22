#!/bin/bash

# Get the directory of this script (Resources folder)
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_DIR="$( cd "$DIR/.." && pwd )"
FRAMEWORKS_DIR="$APP_DIR/Frameworks"
BIN_DIR="$DIR/clamav/bin"

# Set up the environment variables for library loading
export DYLD_LIBRARY_PATH="$FRAMEWORKS_DIR:$DYLD_LIBRARY_PATH"
export DYLD_FRAMEWORK_PATH="$FRAMEWORKS_DIR:$DYLD_FRAMEWORK_PATH"

# Run freshclam with all arguments passed to this script
"$BIN_DIR/freshclam" "$@"
exit $?
