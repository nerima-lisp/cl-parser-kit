#!/bin/sh

set -u

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
failures=0
known=0
compile_check_script="$project_root/scripts/run-compile-check.lisp"
run_tests_script="$project_root/run-tests.lisp"
run_examples_script="$project_root/scripts/run-examples.lisp"

have_command() {
  command -v "$1" >/dev/null 2>&1
}

first_line() {
  perl -ne 'if (!$done) { s/\r?\n$//; print; $done = 1; } END { exit($done ? 0 : 1); }'
}

join_command() {
  first=1
  for arg in "$@"; do
    if [ "$first" -eq 1 ]; then
      first=0
    else
      printf ' '
    fi
    printf "'%s'" "$arg"
  done
}

impl_version() {
  command_name=$1

  case "$command_name" in
    sbcl|ccl|ecl|clisp|abcl)
      "$command_name" --version 2>&1 | first_line
      ;;
    *)
      return 1
      ;;
  esac
}

build_command() {
  command_name=$1
  mode=$2
  script_path=$3

  case "$mode" in
    sbcl-script)
      join_command "$command_name" --script "$script_path"
      ;;
    load)
      join_command "$command_name" --load "$script_path"
      ;;
    ccl-load)
      join_command "$command_name" --batch --no-init --load "$script_path"
      ;;
    ecl-load)
      join_command "$command_name" --norc --load "$script_path"
      ;;
    clisp-file)
      join_command "$command_name" -q -norc "$script_path"
      ;;
    *)
      return 1
      ;;
  esac
}

run_check() {
  impl_name=$1
  check_name=$2
  shift 2
  command_line=$(join_command "$@")

  printf 'RUN  %s [%s]\n' "$impl_name" "$check_name"
  printf 'INFO %s [%s] command: %s\n' "$impl_name" "$check_name" "$command_line"
  "$@"
  status=$?
  if [ "$status" -eq 0 ]; then
    printf 'PASS %s [%s]\n' "$impl_name" "$check_name"
    return 0
  fi

  printf 'FAIL %s [%s] (exit %s)\n' "$impl_name" "$check_name" "$status"
  return 1
}

run_mode_check() {
  impl_name=$1
  check_name=$2
  command_name=$3
  mode=$4
  script_path=$5

  case "$mode" in
    sbcl-script)
      run_check "$impl_name" "$check_name" "$command_name" --script "$script_path"
      ;;
    load)
      run_check "$impl_name" "$check_name" "$command_name" --load "$script_path"
      ;;
    ccl-load)
      run_check "$impl_name" "$check_name" "$command_name" --batch --no-init --load "$script_path"
      ;;
    ecl-load)
      run_check "$impl_name" "$check_name" "$command_name" --norc --load "$script_path"
      ;;
    clisp-file)
      run_check "$impl_name" "$check_name" "$command_name" -q -norc "$script_path"
      ;;
    *)
      printf 'FAIL %s [%s] (unknown mode %s)\n' "$impl_name" "$check_name" "$mode"
      return 1
      ;;
  esac
}

run_impl() {
  impl_name=$1
  command_name=$2
  compile_mode=$3
  tests_mode=$4
  examples_mode=$5
  known=$((known + 1))

  if ! have_command "$command_name"; then
    printf 'SKIP %s (%s not found)\n' "$impl_name" "$command_name"
    printf 'INFO %s compile command: %s\n' "$impl_name" \
      "$(build_command "$command_name" "$compile_mode" "$compile_check_script")"
    printf 'INFO %s tests command: %s\n' "$impl_name" \
      "$(build_command "$command_name" "$tests_mode" "$run_tests_script")"
    printf 'INFO %s examples command: %s\n' "$impl_name" \
      "$(build_command "$command_name" "$examples_mode" "$run_examples_script")"
    return 0
  fi

  printf 'RUN  %s\n' "$impl_name"
  if version=$(impl_version "$command_name"); then
    printf 'INFO %s version: %s\n' "$impl_name" "$version"
  else
    printf 'INFO %s version: unavailable\n' "$impl_name"
  fi

  if run_mode_check "$impl_name" compile "$command_name" "$compile_mode" "$compile_check_script" &&
     run_mode_check "$impl_name" tests "$command_name" "$tests_mode" "$run_tests_script" &&
     run_mode_check "$impl_name" examples "$command_name" "$examples_mode" "$run_examples_script"; then
    printf 'PASS %s\n' "$impl_name"
  else
    printf 'FAIL %s\n' "$impl_name"
    failures=$((failures + 1))
  fi
}

if [ "$#" -gt 0 ]; then
  implementations="$*"
else
  implementations="sbcl ccl ecl clisp abcl"
fi

for impl in $implementations; do
  case "$impl" in
    sbcl)
      run_impl "SBCL" sbcl sbcl-script sbcl-script sbcl-script
      ;;
    ccl)
      run_impl "Clozure CL (CCL)" ccl ccl-load ccl-load ccl-load
      ;;
    ecl)
      run_impl "ECL" ecl ecl-load ecl-load ecl-load
      ;;
    clisp)
      run_impl "CLISP" clisp clisp-file clisp-file clisp-file
      ;;
    abcl)
      run_impl "ABCL" abcl load load load
      ;;
    *)
      printf 'SKIP %s (unknown implementation key)\n' "$impl"
      ;;
  esac
done

if [ "$known" -eq 0 ]; then
  printf 'FAIL no known implementation keys were requested\n' >&2
  exit 1
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi
