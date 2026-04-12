#!/bin/bash

cmd_test() {
    local action="${1:-}"
    local subarg="$2"

    local current_branch
    current_branch=$(cd "$RETRO_DIR" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

    if [[ $current_branch != *"dev"* ]]; then
        rx_log "error" "Test command is only available on dev branches"
        rx_log "info" "Current branch: ${GRAY}${current_branch}${RESET}"
        return 1
    fi

    local core="$RETRO_DIR/scripts/test_core.sh"

    case "$action" in
        status)
            local status_output
            status_output=$(bash "$core" --status 2>&1)

            if echo "$status_output" | grep -q "error"; then
                rx_log "error" "Failed to get test status"
                return 1
            fi

            local total passed failed warnings cached timestamp
            IFS='|' read -r total passed failed warnings cached timestamp <<<"$status_output"

            total="${total#total=}"
            passed="${passed#passed=}"
            failed="${failed#failed=}"
            warnings="${warnings#warnings=}"
            cached="${cached#cached=}"
            timestamp="${timestamp#timestamp=}"

            rx_table_header "󰦀" "Test Status"

            if [[ $cached == "no" ]]; then
                rx_table_row "󰍔" "Cache:" "No cache - run 'test refresh'" "$WARNING" "20"
                rx_table_separator
                rx_table_row "󰐕" "Total tests:" "${total}" "$PINK" "20"
                rx_table_row "󰈑" "Run:" "retro test refresh" "$GRAY" "20"
            else
                if [[ $failed -gt 0 ]]; then
                    rx_table_row "󰜺" "Status:" "FAILED" "$ERROR" "20"
                elif [[ $warnings -gt 0 ]]; then
                    rx_table_row "󰍔" "Status:" "WARNINGS" "$WARNING" "20"
                else
                    rx_table_row "󰸀" "Status:" "PASSED" "$SUCCESS" "20"
                fi

                rx_table_separator

                rx_table_row "󰐕" "Total:" "${total}" "$PINK" "20"
                rx_table_row "󰸀" "Passed:" "${passed}" "$SUCCESS" "20"

                if [[ $failed -gt 0 ]]; then
                    rx_table_row "󰜺" "Failed:" "${failed}" "$ERROR" "20"
                else
                    rx_table_row "󰸀" "Failed:" "0" "$SUCCESS" "20"
                fi

                if [[ $warnings -gt 0 ]]; then
                    rx_table_row "󰍔" "Warnings:" "${warnings}" "$WARNING" "20"
                fi

                if [[ -n $timestamp && $timestamp != "0" ]]; then
                    local human_time
                    human_time=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$timestamp")
                    rx_table_row_gray "󰔛" "Last run:" "$human_time" "20"
                fi
            fi

            rx_table_separator
            rx_table_spacer
            ;;

        all)
            rx_log "info" "Running all tests..."

            local all_output
            all_output=$(bash "$core" --run-all 2>&1)

            local passed_count=0
            local failed_count=0

            rx_table_header "󰦀" "Test Results"

            while IFS='|' read -r result name output; do
                [[ -z $result ]] && continue

                if [[ $result == "pass" ]]; then
                    ((passed_count++))
                    rx_table_row "󰸀" "${name}" "PASSED" "$SUCCESS" "20"
                elif [[ $result == "fail" ]]; then
                    ((failed_count++))
                    rx_table_row "󰜺" "${name}" "FAILED" "$ERROR" "20"
                    if [[ -n $output ]]; then
                        local decoded_output
                        decoded_output=$(echo "$output" | jq -r . 2>/dev/null || echo "$output")
                        local first=true
                        while IFS= read -r err_line; do
                            [[ -z $err_line ]] && continue
                            if [[ $first == "true" ]]; then
                                rx_table_row_gray "  " "Error:" "${err_line:0:60}" "20"
                                first=false
                            else
                                rx_table_row_gray "   " "" "${err_line:0:60}" "20"
                            fi
                        done <<<"$decoded_output"
                    fi
                elif [[ $result == "summary" ]]; then
                    continue
                fi
            done <<<"$all_output"

            rx_table_separator

            if [[ $failed_count -gt 0 ]]; then
                rx_table_row "󰜺" "Failed:" "${failed_count}" "$ERROR" "20"
                return 1
            else
                rx_table_row "󰸀" "All tests:" "PASSED" "$SUCCESS" "20"
            fi

            rx_table_separator
            rx_table_spacer

            if [[ $failed_count -gt 0 ]]; then
                rx_log "error" "Some tests failed"
                return 1
            else
                rx_log "success" "All tests passed"
            fi
            ;;

        list)
            local list_output
            list_output=$(bash "$core" --list 2>&1)

            if echo "$list_output" | grep -q "error"; then
                rx_log "error" "Failed to list tests"
                return 1
            fi

            rx_table_header "󰒒" "Available Tests"

            while IFS='|' read -r _ name desc; do
                [[ -z $name ]] && continue
                rx_table_row_gray "󰬔" "${name}:" "${desc:-No description}" "10"
            done <<<"$list_output"

            rx_table_separator
            rx_table_spacer
            ;;

        run)
            if [[ -z $subarg ]]; then
                rx_log "error" "Usage: retro test run <name>"
                rx_log "info" "Run 'retro test list' to see available tests"
                return 1
            fi

            rx_log "info" "Running test: ${PINK}${subarg}${RESET}..."

            local run_output
            run_output=$(bash "$core" --run "$subarg" 2>&1)

            if echo "$run_output" | grep -q "error"; then
                local err_msg="${run_output#error|}"
                rx_log "error" "$err_msg"
                return 1
            fi

            if echo "$run_output" | grep -q "result=pass"; then
                rx_log "success" "Test ${subarg} passed"
            else
                rx_log "error" "Test ${subarg} failed"
                echo -e "${GRAY}${run_output}${RESET}"
                return 1
            fi
            ;;

        *)
            rx_help_usage "retro --tests <command>"
            rx_help_commands "Available Commands"
            rx_help_cmd "status" "Show cached test status (fast)"
            rx_help_cmd "all" "Run all tests and update cache"
            rx_help_cmd "list" "List all available tests"
            rx_help_cmd "run <name>" "Run a specific test"
            rx_help_examples
            rx_help_example "retro --tests status" "Show cached test analytics"
            rx_help_example "retro --tests refresh" "Run all tests & update cache"
            rx_help_example "retro --tests list" "List all tests"
            rx_help_example "retro --tests run shellcheck" "Run shellcheck test"
            rx_help_spacer
            return 1
            ;;
    esac
}

current_branch=$(cd "$RETRO_DIR" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

if [[ $current_branch == *"dev"* ]]; then
    register_command "SYSTEM" "-t|--tests" "Run test suite (dev branches only)" "cmd_test"
fi
