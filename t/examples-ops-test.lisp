(in-package :cl-parser-kit/test)

(it-sequential "smoke-script-covers-documented-implementation-keys-test"
  (let ((contents (repository-file-contents "scripts/run-implementation-smoke.sh")))
    (assert-string-contains-all
     contents
     '("sbcl" "ccl" "ecl" "clisp" "abcl"
       "scripts/run-compile-check.lisp"
       "run-tests.lisp"
       "scripts/run-examples.lisp"
       "INFO %s [%s] command:"
       "INFO %s version:"
       "SKIP"
       "PASS"
       "FAIL"))))

(it-sequential "repository-does-not-ship-debug-helper-scripts-test"
  (assert-repository-files-do-not-match
   "scripts/*.lisp"
   (lambda (name)
     (local-string-prefix-p "debug-" name))))

(it-sequential "smoke-script-invokes-checked-in-verification-entrypoints-directly-test"
  (let ((script (repository-file-contents "scripts/run-implementation-smoke.sh")))
    (dolist (needle '("compile_check_script="
                      "run_tests_script="
                      "run_examples_script="
	                      "scripts/run-compile-check.lisp"
	                      "run-tests.lisp"
	                      "scripts/run-examples.lisp"
	                      "run_check"
	                      "run_mode_check"
	                      "run_mode_check \"$impl_name\" compile"
	                      "run_mode_check \"$impl_name\" tests"
	                      "run_mode_check \"$impl_name\" examples"
	                      "impl_version"
	                      "join_command"))
	      (expect (search needle script) :to-be-truthy))
	    (assert-string-lacks-any
	     script
	     '("driver_file=" "cat >\"$driver_file\"" "trap cleanup" "command_words"))))

(it-sequential "timeout-wrapper-kills-process-groups-and-validates-timeout-test"
  (let ((script (repository-file-contents "scripts/with-timeout.pl")))
    (dolist (needle '("TIMEOUT must be a positive integer"
                      "setpgrp(0, 0)"
                      "setpgrp($child, $child)"
                      "kill 'TERM', -$child"
                      "kill 'TERM', $child"
                      "kill 'KILL', -$child"
                      "kill 'KILL', $child"))
      (expect (search needle script) :to-be-truthy))))

(it-sequential "timeout-wrapper-enforces-timeout-at-runtime-test"
  (let* ((script (namestring (repository-file-path "scripts/with-timeout.pl")))
         (start (get-internal-real-time)))
    (multiple-value-bind (output error-output status)
        (uiop:run-program
         (list "perl"
               script
               "1"
               "sh"
               "-c"
               "trap '' TERM; sleep 100 & wait")
         :output :string
         :error-output :output
         :ignore-error-status t)
      (declare (ignore error-output))
      (let ((elapsed (/ (- (get-internal-real-time) start)
                        internal-time-units-per-second)))
        (expect status :to-equal 124)
        (expect (search "timed out after 1 seconds" output) :to-be-truthy)
        (expect (< elapsed 10) :to-be-truthy)))))
