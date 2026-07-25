(require :asdf)

(defun benchmark-getenv-integer (name default &key (minimum 1))
  (let ((raw (uiop:getenv name)))
    (if (or (null raw) (zerop (length raw))) default
      (let ((value (parse-integer raw :junk-allowed nil)))
        (unless (>= value minimum)
          (error "~A must be at least ~D, got ~D" name minimum value))
        value))))

(defun benchmark-root ()
  (uiop:ensure-directory-pathname
    (truename
      (or
        (second sb-ext:*posix-argv*)
        (uiop:getenv "CL_PARSER_KIT_ROOT")
        (uiop:getcwd)))))

(progn
  (defun load-benchmark-system (root)
    (asdf:load-asd (merge-pathnames "cl-parser-kit.asd" root))
    (asdf:load-system :cl-parser-kit :verbose nil :print nil))
  (load-benchmark-system (benchmark-root)))

(defun benchmark-median (values)
  (let* ((sorted (sort (copy-seq values) #'<))
         (length (length sorted))
         (middle (floor length 2)))
    (if (oddp length) (aref sorted middle)
      (/ (+ (aref sorted (1- middle)) (aref sorted middle)) 2))))

(defun benchmark-sample (thunk iterations units-per-iteration)
  (sb-ext:gc :full t)
  (let ((bytes-before (sb-ext:get-bytes-consed))
        (time-before (get-internal-real-time)))
    (dotimes (iteration iterations)
      (declare (ignore iteration))
      (funcall thunk))
    (let* ((elapsed
          (/
            (- (get-internal-real-time) time-before)
            (float internal-time-units-per-second 1.0d0)))
           (bytes (- (sb-ext:get-bytes-consed) bytes-before))
           (throughput
          (if (plusp elapsed) (/ (* iterations units-per-iteration) elapsed)
            0.0d0)))
      (values elapsed bytes throughput))))

(defun %write-tsv-row (fields)
  (loop for field in fields
        for first-p = t then nil
        unless first-p
          do (write-char #\Tab)
        do (princ field))
  (terpri))

(defun emit-benchmark-row (benchmark phase sample root size units iterations elapsed bytes throughput)
  (%write-tsv-row
    (list
      benchmark
      phase
      sample
      (namestring root)
      size
      units
      iterations
      (format nil "~,9F" elapsed)
      bytes
      (format nil "~,3F" throughput))))

(defun run-benchmark (name root size units iterations warmup samples thunk)
  (dotimes (iteration warmup)
    (declare (ignore iteration))
    (funcall thunk))
  (let ((elapsed-values (make-array samples :element-type 'double-float))
        (byte-values (make-array samples :element-type 'integer))
        (throughput-values (make-array samples :element-type 'double-float)))
    (dotimes (sample samples)
      (multiple-value-bind (elapsed bytes throughput) (benchmark-sample thunk iterations units)
        (setf (aref elapsed-values sample) elapsed
              (aref byte-values sample) bytes
              (aref throughput-values sample) throughput)
        (emit-benchmark-row
          name
          "sample"
          (1+ sample)
          root
          size
          units
          iterations
          elapsed
          bytes
          throughput)))
    (emit-benchmark-row
      name
      "median"
      "-"
      root
      size
      units
      iterations
      (benchmark-median elapsed-values)
      (round (benchmark-median byte-values))
      (benchmark-median throughput-values))))

(defun make-tokenizer-benchmark (size)
  (let* ((tokenizer
        (cl-parser-kit:make-tokenizer
          :rules
          (list
            (cl-parser-kit:make-whitespace-rule :skip-p t)
            (cl-parser-kit:make-identifier-rule :type :identifier)
            (cl-parser-kit:make-number-rule :type :number)
            (cl-parser-kit:make-operator-rule :operator '("+" "-" "*" "/")))))
         (source
        (with-output-to-string (stream)
          (dotimes (index size)
            (declare (ignore index))
            (write-string "identifier + 42 " stream))))
         (expected (* size 3)))
    (values
      (lambda ()
        (let ((tokens (cl-parser-kit:tokenize source tokenizer)))
          (unless (= (length tokens) expected)
            (error
              "Tokenizer benchmark expected ~D tokens, got ~D"
              expected
              (length tokens)))))
      expected)))

(defun make-parser-benchmark (size)
  (let ((parser (cl-parser-kit:many (cl-parser-kit:type-token :identifier)))
        (tokens
        (map
          'vector
          (lambda (index)
            (cl-parser-kit:make-token
              :type
              :identifier
              :value
              index
              :start
              index
              :end
              (1+ index)))
          (loop for index below size
                collect index))))
    (values
      (lambda ()
        (multiple-value-bind (ok value next failure) (cl-parser-kit:parse-all parser tokens)
          (declare (ignore failure))
          (unless (and ok (= next size) (= (length value) size))
            (error "Parser benchmark failed full consumption at ~D/~D" next size))))
      size)))

(defun make-pratt-benchmark (size)
  (let ((table (cl-parser-kit:make-pratt-table))
        (tokens
        (coerce
          (loop for index below size
                append (if (zerop index) (list
                (cl-parser-kit:make-token
                  :type
                  :number
                  :value
                  1
                  :start
                  (* index 2)
                  :end
                  (1+ (* index 2))))
              (list
                (cl-parser-kit:make-token
                  :type
                  :plus
                  :text
                  "+"
                  :start
                  (1- (* index 2))
                  :end
                  (* index 2))
                (cl-parser-kit:make-token
                  :type
                  :number
                  :value
                  1
                  :start
                  (* index 2)
                  :end
                  (1+ (* index 2))))))
          'vector)))
    (cl-parser-kit:register-prefix-operator
      table
      :number
      0
      (lambda (token stream next current-table)
        (declare (ignore stream current-table))
        (values t (cl-parser-kit:token-value token) next nil)))
    (cl-parser-kit:register-infix-operator
      table
      :plus
      10
      11
      (lambda (left operator right next current-table)
        (declare (ignore operator current-table))
        (values t (+ left right) next nil)))
    (values
      (lambda ()
        (multiple-value-bind (ok value next failure) (cl-parser-kit:parse-pratt-all tokens table)
          (declare (ignore failure))
          (unless (and ok (= next (length tokens)) (= value size))
            (error "Pratt benchmark failed full consumption at ~D/~D" next (length tokens)))))
      (length tokens))))

(defun run-benchmarks ()
  (let* ((root (benchmark-root))
         (samples (benchmark-getenv-integer "BENCH_SAMPLES" 7))
         (warmup (benchmark-getenv-integer "BENCH_WARMUP" 2 :minimum 0))
         (common-size (benchmark-getenv-integer "BENCH_SIZE" 1024))
         (tokenizer-size (benchmark-getenv-integer "BENCH_TOKENIZER_SIZE" common-size))
         (parser-size (benchmark-getenv-integer "BENCH_PARSER_SIZE" common-size))
         (pratt-size (benchmark-getenv-integer "BENCH_PRATT_SIZE" common-size))
         (tokenizer-iterations
        (benchmark-getenv-integer "BENCH_TOKENIZER_ITERATIONS" 20))
         (parser-iterations (benchmark-getenv-integer "BENCH_PARSER_ITERATIONS" 100))
         (pratt-iterations (benchmark-getenv-integer "BENCH_PRATT_ITERATIONS" 40)))
    (load-benchmark-system root)
    (%write-tsv-row '("benchmark"
        "phase"
        "sample"
        "root"
        "size"
        "units_per_iteration"
        "iterations"
        "elapsed_seconds"
        "consed_bytes"
        "throughput_units_per_second"))
    (multiple-value-bind (thunk units) (make-tokenizer-benchmark tokenizer-size)
      (run-benchmark
        "tokenizer"
        root
        tokenizer-size
        units
        tokenizer-iterations
        warmup
        samples
        thunk))
    (multiple-value-bind (thunk units) (make-parser-benchmark parser-size)
      (run-benchmark
        "parser"
        root
        parser-size
        units
        parser-iterations
        warmup
        samples
        thunk))
    (multiple-value-bind (thunk units) (make-pratt-benchmark pratt-size)
      (run-benchmark
        "pratt"
        root
        pratt-size
        units
        pratt-iterations
        warmup
        samples
        thunk))
    (finish-output)))

(run-benchmarks)
