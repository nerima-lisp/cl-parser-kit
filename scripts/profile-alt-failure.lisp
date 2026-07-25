(require :asdf)

(let ((root (uiop:ensure-directory-pathname
             (truename (or (second sb-ext:*posix-argv*) (uiop:getcwd))))))
  (asdf:load-asd (merge-pathnames "cl-parser-kit.asd" root))
  (asdf:load-system :cl-parser-kit :verbose nil :print nil))

(defun bench (label thunk iterations)
  (sb-ext:gc :full t)
  (let ((bytes-before (sb-ext:get-bytes-consed))
        (time-before (get-internal-real-time)))
    (dotimes (i iterations) (funcall thunk))
    (let ((elapsed (/ (- (get-internal-real-time) time-before)
                      (float internal-time-units-per-second 1.0d0)))
          (bytes (- (sb-ext:get-bytes-consed) bytes-before)))
      (format t "~A~40Telapsed=~,6Fs~15Tconsed=~:D bytes~%" label elapsed bytes))))

;; A chain of alternatives that all fail at the same position, forcing
;; MERGE-PARSE-FAILURES to combine their "expected" lists repeatedly --
;; the exact path %MERGE-PARSE-FAILURE-LISTS-UNIQUE is on.
(defun make-mismatched-tokens (n)
  (map 'vector (lambda (i) (cl-parser-kit:make-token :type :mismatch :start i :end (1+ i)))
       (loop for i below n collect i)))

(let* ((n 2048) (iterations 20)
       (tokens (make-mismatched-tokens n))
       (parser (cl-parser-kit:alt (cl-parser-kit:type-token :plus)
                                  (cl-parser-kit:type-token :minus)
                                  (cl-parser-kit:type-token :star)
                                  (cl-parser-kit:type-token :slash))))
  (bench "alt of 4 always-failing branches, at every position"
         (lambda ()
           (dotimes (position n)
             (cl-parser-kit:run-parser parser tokens position)))
         iterations))
