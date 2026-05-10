#!/bin/bash

rx_notice() {
    rx_clear_logo
    echo
    gum spin --spinner dot --title "$1" -- sleep "${2:-2}"
    echo
}