#!/bin/bash

CACHE_FILE="$RETRO_CONFIG/test_cache.json"

run_test_core() {
    local action="$1"
    TEST_DIR="$RETRO_DIR/tests"

    case "$action" in
        --list)
            if [[ ! -d "$TEST_DIR" ]]; then
                echo "error|no-tests-dir"
                exit 1
            fi

            for test_file in "$TEST_DIR"/*_test.sh; do
                [[ -f "$test_file" ]] || continue
                local test_name
                test_name=$(basename "$test_file" _test.sh)
                local test_desc=""

                if grep -q "^# Description:" "$test_file"; then
                    test_desc=$(sed -n 's/^# Description: //p' "$test_file")
                fi

                echo "test|${test_name}|${test_desc}"
            done
            ;;

        --status)
            if [[ ! -f "$CACHE_FILE" ]]; then
                echo "total=0|passed=0|failed=0|warnings=0|cached=no"
                exit 0
            fi

            local cached_data
            cached_data=$(cat "$CACHE_FILE" 2>/dev/null)

            if [[ -z "$cached_data" ]]; then
                echo "total=0|passed=0|failed=0|warnings=0|cached=no"
                exit 0
            fi

            local total passed failed warnings timestamp
            total=$(echo "$cached_data" | jq -r '.total // 0')
            passed=$(echo "$cached_data" | jq -r '.passed // 0')
            failed=$(echo "$cached_data" | jq -r '.failed // 0')
            warnings=$(echo "$cached_data" | jq -r '.warnings // 0')
            timestamp=$(echo "$cached_data" | jq -r '.timestamp // 0')

            echo "total=${total}|passed=${passed}|failed=${failed}|warnings=${warnings}|cached=yes|timestamp=${timestamp}"
            ;;

        --refresh)
            if [[ ! -d "$TEST_DIR" ]]; then
                echo "total=0|passed=0|failed=0|warnings=0"
                exit 0
            fi

            local total=0
            local passed=0
            local failed=0
            local warnings=0
            local results_json="["
            local first=true

            for test_file in "$TEST_DIR"/*_test.sh; do
                [[ -f "$test_file" ]] || continue
                ((total++))

                local result
                result=$(bash "$test_file" 2>&1)
                local exit_code=$?

                if [[ "$result" == *"WARN"* ]]; then
                    local warn_count
                    warn_count=$(echo "$result" | grep -c "WARN" || echo 0)
                    ((warnings += warn_count))
                fi

                local test_name
                test_name=$(basename "$test_file" _test.sh)

                if [[ $exit_code -eq 0 ]]; then
                    ((passed++))
                    if [[ "$first" == "true" ]]; then
                        first=false
                    else
                        results_json+=","
                    fi
                    results_json+="{\"name\":\"${test_name}\",\"status\":\"pass\",\"output\":\"\"}"
                else
                    ((failed++))
                    local escaped_output
                    escaped_output=$(echo "$result" | jq -Rs .)
                    if [[ "$first" == "true" ]]; then
                        first=false
                    else
                        results_json+=","
                    fi
                    results_json+="{\"name\":\"${test_name}\",\"status\":\"fail\",\"output\":${escaped_output}}"
                fi
            done

            results_json+="]"

            local timestamp
            timestamp=$(date +%s)

            echo "{\"total\":${total},\"passed\":${passed},\"failed\":${failed},\"warnings\":${warnings},\"timestamp\":${timestamp},\"results\":${results_json}}" > "$CACHE_FILE"

            echo "total=${total}|passed=${passed}|failed=${failed}|warnings=${warnings}|cached=yes|timestamp=${timestamp}"
            ;;

        --run)
            local test_name="$2"

            if [[ -z "$test_name" ]]; then
                echo "error|no-test-name"
                exit 1
            fi

            local test_file="$TEST_DIR/${test_name}_test.sh"

            if [[ ! -f "$test_file" ]]; then
                echo "error|test-not-found|${test_name}"
                exit 1
            fi

            local start_time
            start_time=$(date +%s)

            local output
            output=$(bash "$test_file" 2>&1)
            local exit_code=$?
            local end_time
            end_time=$(date +%s)
            local duration=$((end_time - start_time))

            if [[ $exit_code -eq 0 ]]; then
                echo "result=pass|test=${test_name}|duration=${duration}s"
            else
                echo "result=fail|test=${test_name}|duration=${duration}s|output=${output}"
            fi
            ;;

        --run-all)
            if [[ ! -d "$TEST_DIR" ]]; then
                echo "result=no-tests"
                exit 0
            fi

            local passed_count=0
            local failed_count=0
            local results_json="["
            local first=true

            for test_file in "$TEST_DIR"/*_test.sh; do
                [[ -f "$test_file" ]] || continue

                local test_name
                test_name=$(basename "$test_file" _test.sh)

                local output
                output=$(bash "$test_file" 2>&1)
                local exit_code=$?

                if [[ $exit_code -eq 0 ]]; then
                    ((passed_count++))
                    echo "pass|${test_name}"
                    if [[ "$first" == "true" ]]; then
                        first=false
                    else
                        results_json+=","
                    fi
                    results_json+="{\"name\":\"${test_name}\",\"status\":\"pass\",\"output\":\"\"}"
                else
                    ((failed_count++))
                    local escaped_output
                    escaped_output=$(echo "$output" | jq -Rs .)
                    echo "fail|${test_name}|${escaped_output}"
                    local escaped_output
                    escaped_output=$(echo "$output" | jq -Rs .)
                    if [[ "$first" == "true" ]]; then
                        first=false
                    else
                        results_json+=","
                    fi
                    results_json+="{\"name\":\"${test_name}\",\"status\":\"fail\",\"output\":${escaped_output}}"
                fi
            done

            results_json+="]"

            local timestamp
            timestamp=$(date +%s)

            echo "summary|total=$((passed_count + failed_count))|passed=${passed_count}|failed=${failed_count}"

            echo "{\"total\":$((passed_count + failed_count)),\"passed\":${passed_count},\"failed\":${failed_count},\"warnings\":0,\"timestamp\":${timestamp},\"results\":${results_json}}" > "$CACHE_FILE"
            ;;

        --get-results)
            if [[ ! -f "$CACHE_FILE" ]]; then
                echo "[]"
                exit 0
            fi

            local results
            results=$(jq -r '.results // []' "$CACHE_FILE" 2>/dev/null)
            echo "${results:-[]}"
            ;;

        *)
            echo "error|unknown-command"
            exit 1
            ;;
    esac
}

run_test_core "$@"