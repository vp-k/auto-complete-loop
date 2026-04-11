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
