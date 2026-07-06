#!/usr/bin/env bats

load test_helper

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

@test "jq_inplace: valid expression updates file" {
  echo '{"a":1}' > test.json
  jq_inplace test.json '.a = 2'
  result=$(jq '.a' test.json)
  [ "$result" = "2" ]
}

@test "jq_inplace: invalid expression preserves original" {
  echo '{"a":1}' > test.json
  run jq_inplace test.json 'INVALID'
  [ "$status" -ne 0 ]
  # 원본이 보존되어야 함
  result=$(jq '.a' test.json)
  [ "$result" = "1" ]
}

@test "jq_inplace: output is valid JSON" {
  echo '{"a":1}' > test.json
  jq_inplace test.json '.b = "hello"'
  jq empty test.json
  [ $? -eq 0 ]
}

@test "timestamp: returns ISO format" {
  result=$(timestamp)
  [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "config_get: returns default when no config file" {
  result=$(config_get '.test' 'default_val')
  [ "$result" = "default_val" ]
}

@test "config_get: reads value from config file" {
  echo '{"test":"actual_val"}' > "$CONFIG_FILE"
  result=$(config_get '.test' 'default_val')
  [ "$result" = "actual_val" ]
}

@test "config_get: returns default for missing key" {
  echo '{"other":"val"}' > "$CONFIG_FILE"
  result=$(config_get '.test' 'default_val')
  [ "$result" = "default_val" ]
}

@test "config_get: handles invalid JSON gracefully" {
  echo 'not json' > "$CONFIG_FILE"
  result=$(config_get '.test' 'default_val')
  [ "$result" = "default_val" ]
}

@test "jq_inplace: self-heals empty file (backup + reset to {})" {
  : > empty.json
  jq_inplace empty.json '.a = 1' 2>/dev/null
  result=$(jq '.a' empty.json)
  [ "$result" = "1" ]
  ls empty.json.corrupt.* >/dev/null 2>&1
}

@test "jq_inplace: self-heals corrupt file preserving backup content" {
  echo 'not json' > bad.json
  jq_inplace bad.json '.k = "v"' 2>/dev/null
  result=$(jq -r '.k' bad.json)
  [ "$result" = "v" ]
  backup=$(ls bad.json.corrupt.* | head -1)
  grep -q 'not json' "$backup"
}

@test "jq_inplace: releases lock dir after update" {
  echo '{"a":1}' > lk.json
  jq_inplace lk.json '.a = 2'
  [ ! -d lk.json.lock.d ]
}

@test "write_json_atomic: writes valid JSON from argument" {
  write_json_atomic wa.json '{"x":1}'
  result=$(jq '.x' wa.json)
  [ "$result" = "1" ]
}

@test "write_json_atomic: writes valid JSON from stdin" {
  echo '{"y":2}' | write_json_atomic wb.json
  result=$(jq '.y' wb.json)
  [ "$result" = "2" ]
}

@test "write_json_atomic: refuses invalid JSON and does not create file" {
  run write_json_atomic wc.json 'not-json'
  [ "$status" -ne 0 ]
  [ ! -f wc.json ]
}

@test "write_json_atomic: refuses empty stdin and preserves existing file" {
  echo '{"keep":true}' > wd.json
  run bash -c 'source "'"$SCRIPT_DIR"'/lib/utils.sh"; printf "" | write_json_atomic wd.json'
  [ "$status" -ne 0 ]
  result=$(jq '.keep' wd.json)
  [ "$result" = "true" ]
}
