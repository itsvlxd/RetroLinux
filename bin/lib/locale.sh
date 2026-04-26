#!/bin/bash

rx_list_keyboard_layouts() {
    localectl --no-pager list-keymaps 2>/dev/null | sort
}

rx_list_x11_keyboard_layouts() {
    localectl --no-pager list-x11-keymap-layouts 2>/dev/null | sort
}

rx_get_current_keyboard() {
    local current=""
    current=$(localectl --no-pager status 2>/dev/null | grep "VC Keymap:" | awk '{print $3}')
    if [[ -z $current ]]; then
        current="us"
    fi
    echo "$current"
}

rx_verify_keyboard_layout() {
    local layout="$1"
    rx_list_keyboard_layouts | grep -qi "^${layout}$"
}

rx_set_keyboard_layout() {
    local layout="$1"
    if [[ $(tty 2>/dev/null) == "/dev/tty"* ]]; then
        loadkeys "$layout" 2>/dev/null || true
    fi
}

rx_get_sys_lang() {
    local lang="${LANG:-en_US.UTF-8}"
    echo "$lang"
}

rx_list_locales() {
    if [[ -f /usr/share/i18n/SUPPORTED ]]; then
        grep -v "C.UTF-8" /usr/share/i18n/SUPPORTED 2>/dev/null | sort
    fi
}

rx_list_locale_langs() {
    rx_list_locales | awk '{print $1}' | sed 's/_.*//' | sort -u
}

rx_list_locale_encs() {
    rx_list_locales | awk '{print $2}' | sort -u
}

rx_get_locale_lang() {
    local locale="$1"
    echo "$locale" | cut -d'.' -f1
}

rx_get_locale_enc() {
    local locale="$1"
    echo "$locale" | cut -d'.' -f2
}

declare -A LOCALE_LANG_NAMES=(
    ["af"]="Afrikaans"
    ["am"]="Amharic"
    ["ar"]="Arabic"
    ["as"]="Assamese"
    ["az"]="Azerbaijani"
    ["be"]="Belarusian"
    ["bg"]="Bulgarian"
    ["bn"]="Bengali"
    ["bs"]="Bosnian"
    ["ca"]="Catalan"
    ["cs"]="Czech"
    ["cy"]="Welsh"
    ["da"]="Danish"
    ["de"]="German"
    ["dz"]="Dzongkha"
    ["el"]="Greek"
    ["en"]="English"
    ["eo"]="Esperanto"
    ["es"]="Spanish"
    ["et"]="Estonian"
    ["eu"]="Basque"
    ["fa"]="Persian"
    ["fi"]="Finnish"
    ["fr"]="French"
    ["gl"]="Galician"
    ["gu"]="Gujarati"
    ["he"]="Hebrew"
    ["hi"]="Hindi"
    ["hr"]="Croatian"
    ["hu"]="Hungarian"
    ["hy"]="Armenian"
    ["id"]="Indonesian"
    ["is"]="Icelandic"
    ["it"]="Italian"
    ["ja"]="Japanese"
    ["ka"]="Georgian"
    ["kk"]="Kazakh"
    ["km"]="Khmer"
    ["kn"]="Kannada"
    ["ko"]="Korean"
    ["ku"]="Kurdish"
    ["lo"]="Lao"
    ["lt"]="Lithuanian"
    ["lv"]="Latvian"
    ["mk"]="Macedonian"
    ["ml"]="Malayalam"
    ["mn"]="Mongolian"
    ["mr"]="Marathi"
    ["ms"]="Malay"
    ["mt"]="Maltese"
    ["nb"]="Norwegian Bokmål"
    ["ne"]="Nepali"
    ["nl"]="Dutch"
    ["nn"]="Norwegian Nynorsk"
    ["no"]="Norwegian"
    ["or"]="Oriya"
    ["pa"]="Panjabi"
    ["pl"]="Polish"
    ["pt"]="Portuguese"
    ["pt_BR"]="Brazilian Portuguese"
    ["ro"]="Romanian"
    ["ru"]="Russian"
    ["si"]="Sinhala"
    ["sk"]="Slovak"
    ["sl"]="Slovenian"
    ["sq"]="Albanian"
    ["sr"]="Serbian"
    ["sv"]="Swedish"
    ["ta"]="Tamil"
    ["te"]="Telugu"
    ["th"]="Thai"
    ["tr"]="Turkish"
    ["uk"]="Ukrainian"
    ["ur"]="Urdu"
    ["uz"]="Uzbek"
    ["vi"]="Vietnamese"
    ["zh_CN"]="Simplified Chinese"
    ["zh_TW"]="Traditional Chinese"
)

rx_locale_to_lang_name() {
    local locale="${1:-en_US.UTF-8}"
    local lang_code="${locale%%.*}"
    local lang_name="${LOCALE_LANG_NAMES[$lang_code]:-}"
    if [[ -n $lang_name ]]; then
        echo "$lang_name"
    else
        echo "$lang_code"
    fi
}

declare -A KEYBOARD_LAYOUT_NAMES=(
    ["us"]="English (US)"
    ["us-intl"]="English (US International)"
    ["us-altgr-intl"]="English (US AltGr International)"
    ["us-dvorak"]="English (US Dvorak)"
    ["us-dvorak-intl"]="English (US Dvorak International)"
    ["us-dvorak-l"]="English (US Dvorak Left-hand)"
    ["us-dvorak-r"]="English (US Dvorak Right-hand)"
    ["us-colemak"]="English (US Colemak)"
    ["us-olpc2"]="English (US OLPC2)"

    ["uk"]="English (UK)"
    ["uk-dvorak"]="English (UK Dvorak)"

    ["fr"]="French"
    ["fr-bepo"]="French (Bepo)"
    ["fr-bepo-latin9"]="French (Bepo Latin9)"
    ["fr-afnor"]="French (AFNOR)"
    ["fr-latin1"]="French (Latin1)"
    ["fr-latin9"]="French (Latin9)"
    ["azerty"]="French (Azerty)"
    ["cf"]="French (Canada)"
    ["fr-pc"]="French (PC)"
    ["fr_CH"]="French (Switzerland)"
    ["dvorak-fr"]="French (Dvorak)"
    ["dvorak-ca-fr"]="French (Dvorak Canada)"
    ["be-latin1"]="Belgian"

    ["de"]="German"
    ["de-latin1"]="German (Latin1)"
    ["de-latin1-nodeadkeys"]="German (Latin1 No Deadkeys)"
    ["de-mobii"]="German (Mobii)"
    ["de_CH-latin1"]="German (Switzerland)"
    ["adnw"]="German (Adnw)"
    ["dvorak-de"]="German (Dvorak)"

    ["es"]="Spanish"
    ["es-cp850"]="Spanish (CP850)"
    ["es-olpc"]="Spanish (OLPC)"
    ["dvorak-es"]="Spanish (Dvorak)"
    ["latam"]="Spanish (Latin America)"

    ["it"]="Italian"
    ["it-ibm"]="Italian (IBM)"
    ["it-latin1"]="Italian (Latin1)"
    ["it2"]="Italian (Variant 2)"
    ["dvorak-it"]="Italian (Dvorak)"

    ["pt"]="Portuguese"
    ["pt-latin1"]="Portuguese (Latin1)"
    ["pt-latin9"]="Portuguese (Latin9)"
    ["pt-olpc"]="Portuguese (OLPC)"
    ["pt-br"]="Portuguese (Brazil)"
    ["pt-br-abnt2"]="Portuguese (Brazil ABNT2)"
    ["pt-br-dvorak"]="Portuguese (Brazil Dvorak)"
    ["pt-br-nativo"]="Portuguese (Brazil Nativo)"
    ["pt-br-nativo-epo"]="Portuguese (Brazil Nativo Esperanto)"
    ["dvorak-la"]="Portuguese (Dvorak Latin America)"

    ["pl"]="Polish"
    ["pl1"]="Polish (Variant 1)"
    ["pl2"]="Polish (Variant 2)"
    ["pl3"]="Polish (Variant 3)"
    ["pl4"]="Polish (Variant 4)"
    ["pl-pl"]="Polish (Poland)"
    ["sun-pl"]="Polish (Sun)"
    ["sun-pl-altgraph"]="Polish (Sun AltGraph)"

    ["cz"]="Czech"
    ["cz-cp1250"]="Czech (CP1250)"
    ["cz-lat2"]="Czech (Latin2)"
    ["cz-lat2-prog"]="Czech (Latin2 Programmer)"
    ["cz-qwertz"]="Czech (Qwertz)"
    ["cz-us-qwertz"]="Czech (US Qwertz)"

    ["sk"]="Slovak"
    ["sk-prog-qwerty"]="Slovak (Programmer Qwerty)"
    ["sk-prog-qwertz"]="Slovak (Programmer Qwertz)"
    ["sk-qwerty"]="Slovak (Qwerty)"
    ["sk-qwertz"]="Slovak (Qwertz)"
    ["sk1"]="Slovak (Variant 1)"
    ["sk2"]="Slovak (Variant 2)"
    ["sk3"]="Slovak (Variant 3)"
    ["sk4"]="Slovak (Variant 4)"

    ["hu"]="Hungarian"
    ["hu101"]="Hungarian (101-key)"

    ["ro"]="Romanian"
    ["ro-std"]="Romanian (Standard)"
    ["ro-win"]="Romanian (Windows)"
    ["ro1"]="Romanian (Variant 1)"
    ["ro2"]="Romanian (Variant 2)"
    ["ro3"]="Romanian (Variant 3)"
    ["ro4"]="Romanian (Variant 4)"

    ["nl"]="Dutch"
    ["nl2"]="Dutch (Variant 2)"

    ["bel"]="Belgian"
    ["by"]="Belarusian"
    ["by-cp1251"]="Belarusian (CP1251)"
    ["bywin-cp1251"]="Belarusian (Windows CP1251)"

    ["bg"]="Bulgarian"
    ["bg-cp1251"]="Bulgarian (CP1251)"
    ["bg-cp855"]="Bulgarian (CP855)"
    ["bg_bds-cp1251"]="Bulgarian (BDS CP1251)"
    ["bg_bds-utf8"]="Bulgarian (BDS UTF-8)"
    ["bg_pho-cp1251"]="Bulgarian (Phonetic CP1251)"
    ["bg_pho-utf8"]="Bulgarian (BDS UTF-8)"

    ["hr"]="Croatian"
    ["hcesar"]="Croatian (HCE)"
    ["croat"]="Croatian"

    ["sr-cy"]="Serbian (Cyrillic)"
    ["sr-latin"]="Serbian (Latin)"

    ["sl"]="Slovenian"
    ["slovene"]="Slovenian"

    ["mk"]="Macedonian"
    ["mk-utf"]="Macedonian (UTF-8)"

    ["ru"]="Russian"
    ["ru-cp1251"]="Russian (CP1251)"
    ["ru-ms"]="Russian (MS)"
    ["ru-yawerty"]="Russian (Yawerty)"
    ["ru1"]="Russian (Variant 1)"
    ["ru2"]="Russian (Variant 2)"
    ["ru3"]="Russian (Variant 3)"
    ["ru4"]="Russian (Variant 4)"
    ["ru_win"]="Russian (Windows)"
    ["ruwin"]="Russian (Windows)"
    ["ruwin-alt"]="Russian (Windows Alt)"
    ["dvorak-ru"]="Russian (Dvorak)"

    ["ua"]="Ukrainian"
    ["ua-cp1251"]="Ukrainian (CP1251)"
    ["ua-utf"]="Ukrainian (UTF-8)"
    ["ua-utf-ws"]="Ukrainian (UTF-8 Workman)"
    ["ua-ws"]="Ukrainian (Workman)"
    ["ua1"]="Ukrainian (Variant 1)"
    ["ua2"]="Ukrainian (Variant 2)"
    ["ua3"]="Ukrainian (Variant 3)"
    ["ua4"]="Ukrainian (Variant 4)"

    ["ee"]="Estonian"
    ["et"]="Estonian"
    ["et-nodeadkeys"]="Estonian (No Deadkeys)"

    ["lv"]="Latvian"
    ["lat"]="Latvian"
    ["lat-altgr"]="Latvian (AltGr)"
    ["lat-no-deadkeys"]="Latvian (No Deadkeys)"
    ["latqwerty"]="Latvian (Qwerty)"

    ["lt"]="Lithuanian"
    ["lt-baltic"]="Lithuanian (Baltic)"
    ["lt-classic"]="Lithuanian (Classic)"
    ["lt-us"]="Lithuanian (US)"

    ["fi"]="Finnish"
    ["se-fi"]="Finnish (Sweden)"

    ["se"]="Swedish"
    ["se-ir209"]="Swedish (IR209)"
    ["se-lat6"]="Swedish (Lat6)"
    ["se-sve"]="Swedish (Sve)"
    ["se-latin1"]="Swedish (Latin1)"
    ["dvorak-sv-a1"]="Swedish (Dvorak A1)"
    ["dvorak-sv-a5"]="Swedish (Dvorak A5)"
    ["dvorak-no"]="Swedish (Dvorak Norway)"

    ["no"]="Norwegian"
    ["no-dvorak"]="Norwegian (Dvorak)"
    ["no-latin1"]="Norwegian (Latin1)"

    ["dk"]="Danish"
    ["dk-latin1"]="Danish (Latin1)"

    ["is"]="Icelandic"
    ["is-latin1"]="Icelandic (Latin1)"

    ["ie"]="Irish"

    ["gr"]="Greek"
    ["gr-pc"]="Greek (PC)"

    ["tr"]="Turkish"
    ["tr-alt"]="Turkish (Alt)"
    ["tr_f"]="Turkish (F)"
    ["tr_q"]="Turkish (Q)"

    ["jp"]="Japanese"
    ["jp-106"]="Japanese (106-key)"

    ["kp"]="Korean"

    ["ir"]="Iranian"
    ["af"]="Afghan"

    ["in"]="Hindi (India)"
    ["iq"]="Iraqi"
    ["pk"]="Pakistani"

    ["il"]="Hebrew"
    ["il-heb"]="Hebrew"
    ["il-phonetic"]="Hebrew (Phonetic)"

    ["kg"]="Kyrgyz"
    ["kz"]="Kazakh"
    ["tj_alt-UTF8"]="Tajik (Alternate UTF-8)"
    ["ttwin"]="Tajik (Windows)"

    ["az"]="Azerbaijani"
    ["ge"]="Georgian"

    ["th"]="Thai"
    ["th-mane"]="Thai (Mane)"
    ["th-wheat"]="Thai (Wheat)"

    ["vi"]="Vietnamese"

    ["zh"]="Chinese"

    ["colemak"]="Colemak"
    ["dvorak"]="Dvorak"
    ["dvorak-programmer"]="Dvorak (Programmer)"
    ["dvorak-uk"]="Dvorak (UK)"
    ["carpalx"]="Carpalx"
    ["carpalx-full"]="Carpalx (Full)"
    ["emacs"]="Emacs"
    ["emacs2"]="Emacs2"
)

rx_keyboard_display_name() {
    local keymap="${1:-us}"
    if [[ -n "${KEYBOARD_LAYOUT_NAMES[$keymap]:-}" ]]; then
        echo "${KEYBOARD_LAYOUT_NAMES[$keymap]}"
    else
        echo "$keymap"
    fi
}

rx_format_keyboard_for_gum() {
    local keyboards
    keyboards=$(rx_list_keyboard_layouts)
    local display_names=()
    local keymaps=()

    while IFS= read -r keymap; do
        [[ -z $keymap ]] && continue
        display_names+=("$(rx_keyboard_display_name "$keymap")")
        keymaps+=("$keymap")
    done <<<"$keyboards"

    printf '%s\n' "${display_names[@]}"
}

rx_get_keymap_from_display() {
    local display_name="$1"
    local keymap

    for key in "${!KEYBOARD_LAYOUT_NAMES[@]}"; do
        if [[ "${KEYBOARD_LAYOUT_NAMES[$key]}" == "$display_name" ]]; then
            echo "$key"
            return
        fi
    done

    echo "$display_name" | tr '[:upper:]' '[:lower:]'
}

rx_filter_keyboards() {
    local current_kb="$1"
    local current_display
    current_display=$(rx_keyboard_display_name "$current_kb")

    echo "$current_display"
}

rx_filter_locales() {
    local current_lang="${1:-en_US.UTF-8}"
    local lang_code="${current_lang%%.*}"
    local lang_name
    lang_name=$(rx_locale_to_lang_name "$lang_code")

    echo "$lang_name"
}

rx_list_locale_langs_for_gum() {
    local locales
    locales=$(rx_list_locale_langs)

    while IFS= read -r locale; do
        [[ -z $locale ]] && continue
        rx_locale_to_lang_name "$locale"
    done <<<"$locales"
}