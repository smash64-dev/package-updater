#!/bin/bash
# generate_empty_config.sh
# builds an empty config containing all config keys from the source

SELF_DIR="$(dirname "$(readlink -f "$0")")"
BASE_DIR="$(dirname "$SELF_DIR")"

# double underscores are not valid keys in the config
INVALID_REGEX='^$\|.*__.*'
SECTIONS=('gui' 'package' 'updater' 'user')

echo -e "# generated.cfg"

# generate the list for the primary config
for section in "${SECTIONS[@]}"; do
    obj_keys="$(grep -IRo "${section}([^)]*)" "$BASE_DIR" | cut -d'"' -f2)"
    func_keys="$(grep -IRio "__GetSectionValue(\"${section^}\"[^)]*)" "$BASE_DIR" | cut -d'"' -f4)"

    echo -e "\n[${section^}]"
    echo -e "${obj_keys}\n${func_keys}" | grep -v "$INVALID_REGEX" | sort | uniq | xargs -IQ echo 'Q='
done

# generate the list of the complex file directives
complex_keys="$(grep -IRo "complex_data[[]\"[^]]*\"[]]" "$BASE_DIR" | cut -d'"' -f2)"

echo -e "\n[Ensure_Directives]"
echo -e "$complex_keys" | grep -v "$INVALID_REGEX" | sort | uniq | xargs -IQ echo 'Q='

exit
