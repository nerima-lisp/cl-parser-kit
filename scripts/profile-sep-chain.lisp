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

(defun make-comma-separated-tokens (n)
  (coerce (loop for i below n
                append (if (zerop i)
                           (list (cl-parser-kit:make-token :type :identifier :value i :start 0 :end 1))
                           (list (cl-parser-kit:make-token :type :comma :start (1- (* i 2)) :end (* i 2))
                                 (cl-parser-kit:make-token :type :identifier :value i
                                                           :start (* i 2) :end (1+ (* i 2))))))
          'vector))

(defun make-plus-chain-tokens (n)
  (coerce (loop for i below n
                append (if (zerop i)
                           (list (cl-parser-kit:make-token :type :number :value 1 :start 0 :end 1))
                           (list (cl-parser-kit:make-token :type :plus :start (1- (* i 2)) :end (* i 2))
                                 (cl-parser-kit:make-token :type :number :value 1
                                                           :start (* i 2) :end (1+ (* i 2))))))
          'vector))

(let* ((n 1024) (iterations 200)
       (sep-tokens (make-comma-separated-tokens n))
       (chain-tokens (make-plus-chain-tokens n)))
  (bench "sep-by1"
         (lambda () (cl-parser-kit:parse-all
                     (cl-parser-kit:sep-by1 (cl-parser-kit:type-token :identifier)
                                            (cl-parser-kit:type-token :comma))
                     sep-tokens))
         iterations)
  (bench "chainl1"
         (lambda () (cl-parser-kit:parse-all
                     (cl-parser-kit:chainl1 (cl-parser-kit:type-token-value :number)
                                            (cl-parser-kit:map-parser
                                             (cl-parser-kit:type-token :plus)
                                             (lambda (tok) (declare (ignore tok)) #'+)))
                     chain-tokens))
         iterations))
