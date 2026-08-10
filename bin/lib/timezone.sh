#!/bin/bash

rx_get_current_timezone() {
    timedatectl show 2>/dev/null | grep "Timezone=" | cut -d'=' -f2
}