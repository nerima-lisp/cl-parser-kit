(require :asdf)
(require :sb-sprof)

;;;; Statistical profiler over the tokenizer/parser/Pratt hot paths, for
;;;; finding real bottlenecks before optimizing (see scripts/run-benchmarks.lisp
;;;; for before/after throughput measurement once a fix is in hand).
;;;;
;;;; Usage: sbcl --script scripts/profile-hotpaths.lisp [project-root]
;;;; Env vars: PROFILE_MODE (cpu|alloc, default cpu), PROFILE_SIZE,
;;;; PROFILE_ITERATIONS.

(defun profile-getenv-integer (name default)
  (let ((raw (uiop:getenv name)))
    (if (or (null raw) (zerop (length raw)))
        default
        (parse-integer raw :junk-allowed nil))))

(defun profile-root ()
  (uiop:ensure-directory-pathname
   (truename (or (second sb-ext:*posix-argv*)
                 (uiop:getenv "CL_PARSER_KIT_ROOT")
                 (uiop:getcwd)))))

(defun profile-mode ()
  (let ((raw (uiop:getenv "PROFILE_MODE")))
    (if (and raw (string-equal raw "alloc")) :alloc :cpu)))

(let ((root (profile-root)))
  (asdf:load-asd (merge-pathnames "cl-parser-kit.asd" root))
  (asdf:load-system :cl-parser-kit :verbose nil :print nil))

(defun profile-report-type ()
  (if (uiop:getenv "PROFILE_GRAPH") :graph :flat))

(defmacro with-hotpath-profiling ((label) &body body)
  `(progn
     (format t "~%~%----- ~A PROFILE (~A) -----~%" ,label (profile-mode))
     (sb-sprof:with-profiling (:max-samples 200000 :report nil :mode (profile-mode))
       ,@body)
     (sb-sprof:report :type (profile-report-type))))

(defun profile-tokenizer (size iterations)
  (let* ((tokenizer
          (cl-parser-kit:make-tokenizer
           :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                        (cl-parser-kit:make-identifier-rule :type :identifier)
                        (cl-parser-kit:make-number-rule :type :number)
                        (cl-parser-kit:make-operator-rule :operator '("+" "-" "*" "/")))))
         (source (with-output-to-string (stream)
                   (dotimes (index size) (write-string "identifier + 42 " stream)))))
    (with-hotpath-profiling ("TOKENIZER")
      (dotimes (index iterations)
        (cl-parser-kit:tokenize source tokenizer)))))

(defun profile-many-combinator (size iterations)
  (let ((parser (cl-parser-kit:many (cl-parser-kit:type-token :identifier)))
        (tokens (map 'vector
                     (lambda (index)
                       (cl-parser-kit:make-token :type :identifier :value index
                                                 :start index :end (1+ index)))
                     (loop for index below size collect index))))
    (with-hotpath-profiling ("PARSER (MANY)")
      (dotimes (index iterations)
        (cl-parser-kit:parse-all parser tokens)))))

(defun profile-pratt (size iterations)
  (let ((table (cl-parser-kit:make-pratt-table))
        (tokens (coerce
                 (loop for index below size
                       append (if (zerop index)
                                  (list (cl-parser-kit:make-token :type :number :value 1
                                                                  :start 0 :end 1))
                                  (list (cl-parser-kit:make-token :type :plus :text "+"
                                                                  :start (1- (* index 2)) :end (* index 2))
                                        (cl-parser-kit:make-token :type :number :value 1
                                                                  :start (* index 2) :end (1+ (* index 2))))))
                 'vector)))
    (cl-parser-kit:register-prefix-operator
     table :number 0
     (lambda (token stream next current-table)
       (declare (ignore stream current-table))
       (values t (cl-parser-kit:token-value token) next nil)))
    (cl-parser-kit:register-infix-operator
     table :plus 10 11
     (lambda (left operator right next current-table)
       (declare (ignore operator current-table))
       (values t (+ left right) next nil)))
    (with-hotpath-profiling ("PRATT")
      (dotimes (index iterations)
        (cl-parser-kit:parse-pratt-all tokens table)))))

(defun %deep-ast-chain (depth)
  (let ((leaf (cl-parser-kit:make-ast-node :type :leaf :value 0)))
    (dotimes (index depth leaf)
      (setf leaf (cl-parser-kit:make-ast-node :type :wrap :children (list leaf))))))

(defun profile-tree-walk (depth iterations)
  (let ((tree (%deep-ast-chain depth)))
    (with-hotpath-profiling ("TREE (AST-NODE-WALK / EQUAL / ->SEXP)")
      (dotimes (index iterations)
        (cl-parser-kit:ast-node-walk tree (lambda (node) (declare (ignore node)) nil))
        (cl-parser-kit:ast-node-equal tree tree)
        (cl-parser-kit:ast-node->sexp tree)))))

(let ((size (profile-getenv-integer "PROFILE_SIZE" 4096))
      (iterations (profile-getenv-integer "PROFILE_ITERATIONS" 300)))
  (profile-tokenizer size iterations)
  (profile-many-combinator size iterations)
  (profile-pratt (min size 1900) iterations)
  (profile-tree-walk (min size 2000) iterations))
