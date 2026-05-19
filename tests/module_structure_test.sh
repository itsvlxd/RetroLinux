#!/bin/bash
# Description: Verify modules have required files and valid JSON schema

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: 'jq' is required for schema validation. Please install it."
    exit 1
fi

MISSING=()

MODULES_DIRS=()
while IFS= read -r -d '' dir; do
    MODULES_DIRS+=("$dir")
done < <(find "$RETRO_DIR/modules" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

for mod_dir in "${MODULES_DIRS[@]}"; do
    mod_name=$(basename "$mod_dir")
    json_file="$mod_dir/properties.json"

    if [[ ! -f $json_file ]]; then
        MISSING+=("$mod_name: missing properties.json")
        continue
    fi

    schema_errors=$(jq -r '
        [
            if .title == null or (.title | type != "string") then "missing title" else empty end,
            if .type == null or (.type | IN("core", "extra") | not) then "invalid type" else empty end,
            if .access == null or (.access | IN("user", "root") | not) then "invalid access" else empty end,
            if .defaults == null or (.defaults | type != "boolean") then "invalid defaults" else empty end,
            if .mode == null or (.mode | IN("all", "install", "mirror") | not) then "invalid mode (must be all/install/mirror)" else empty end,
            if .config == null or (.config | type != "string") then "invalid config path" else empty end,
            if .install == null or (.install | type != "string") then "invalid install path" else empty end,
            if .overwrite == null or (.overwrite | type != "boolean") then "missing or invalid overwrite (must be boolean)" else empty end
        ] | join(", ")
    ' "$json_file")

    if [[ -n $schema_errors && $schema_errors != "" ]]; then
        MISSING+=("$mod_name JSON schema: $schema_errors")
    fi

    if [[ ! -f "$mod_dir/packages.sh" && ! -f "$mod_dir/install.sh" ]]; then
        MISSING+=("$mod_name: missing packages.sh or install.sh")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "\e[31mFAIL: ${#MISSING[@]} schema/structure issues found\e[0m"
    for m in "${MISSING[@]}"; do
        echo -e "  \e[33m[!] $m\e[0m"
    done
    exit 1
else
    echo -e "\e[32mPASS: All modules adhere to the RetroLinux schema\e[0m"
    exit 0
fi

