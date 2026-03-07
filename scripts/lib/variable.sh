#!/bin/bash

VAR_CORE="$RETRO_DIR/scripts/variable_core.sh"

get_var() { bash "$VAR_CORE" --get "$1"; }
set_var() { bash "$VAR_CORE" --set "$1" "$2"; }
