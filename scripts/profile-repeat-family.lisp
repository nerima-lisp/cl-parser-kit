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

(defun make-id-tokens (n)
  (map 'vector (lambda (i) (cl-parser-kit:make-token :type :identifier :value i :start i :end (1+ i)))
       (loop for i below n collect i)))

(defun make-id-then-end-tokens (n)
  (coerce (append (loop for i below n
                        collect (cl-parser-kit:make-token :type :identifier :value i
                                                          :start i :end (1+ i)))
                  (list (cl-parser-kit:make-token :type :semicolon :start n :end (1+ n))))
          'vector))

(let* ((n 1024) (iterations 200)
       (id-tokens (make-id-tokens n))
       (till-tokens (make-id-then-end-tokens n)))
  (bench "skip-many"
         (lambda () (cl-parser-kit:parse-all (cl-parser-kit:skip-many (cl-parser-kit:type-token :identifier)) id-tokens))
         iterations)
  (bench "fold-many (sum values)"
         (lambda () (cl-parser-kit:parse-all (cl-parser-kit:fold-many #'+ 0 (cl-parser-kit:type-token-value :identifier)) id-tokens))
         iterations)
  (bench "many-till"
         (lambda () (cl-parser-kit:parse-all
                     (cl-parser-kit:many-till (cl-parser-kit:type-token :identifier)
                                              (cl-parser-kit:type-token :semicolon))
                     till-tokens))
         iterations)
  (bench "times-between 0..n"
         (lambda () (cl-parser-kit:parse-all (cl-parser-kit:times-between 0 n (cl-parser-kit:type-token :identifier)) id-tokens))
         iterations))
