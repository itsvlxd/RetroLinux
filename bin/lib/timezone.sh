#!/bin/bash

rx_list_timezones() {
    timedatectl --no-pager list-timezones 2>/dev/null | sort
}

rx_get_current_timezone() {
    timedatectl show 2>/dev/null | grep "Timezone=" | cut -d'=' -f2
}