(in-package :cl-parser-kit/test)

(defun project-root ()
  (asdf:system-source-directory "cl-parser-kit"))

(eval-when (:load-toplevel :execute)
  (let ((*package* (find-package :cl-user)))
    (load (merge-pathnames "scripts/bootstrap.lisp" (project-root)))))

(defun project-file-path (name)
  (merge-pathnames name (project-root)))

(defun doc-file-path (name)
  (project-file-path name))

(defun file-contents (path)
  (with-open-file (stream path :direction :input)
    (with-output-to-string (output)
      (loop for line = (read-line stream nil nil)
            while line
            do (write-line line output)))))

(defun doc-file-contents (name)
  (file-contents (doc-file-path name)))

(defun repository-file-path (name)
  (project-file-path name))

(defun repository-file-contents (name)
  (file-contents (repository-file-path name)))

(defun repository-file-names (pattern)
  (sort (mapcar #'file-namestring
                (directory (project-file-path pattern)))
        #'string<))

(defun local-string-prefix-p (prefix string)
  (let ((prefix-length (length prefix)))
    (and (<= prefix-length (length string))
         (string= prefix string :end2 prefix-length))))

(defun string-contains-p (needle string)
  (not (null (search needle string))))

(defun assert-string-lacks-any (string snippets)
  (with-soft-assertions
    (dolist (snippet snippets)
      (expect (string-contains-p snippet string) :to-be-falsy))))

(defmacro assert-repository-files-do-not-match (pattern predicate)
  `(dolist (name (repository-file-names ,pattern))
     (expect (funcall ,predicate name) :to-be-falsy)))

(defmacro assert-example-shape-failure-snippet ()
  `(assert-example-values
    (parse-tokens
     (seq
      (alt
       (seq
        (literal "let" :type :let)
        (type-token :identifier))
       (seq
        (literal "const" :type :const)
        (label
         (type-token :identifier)
         :binding-name)
        (literal "=" :type :equals)
        (type-token :number)))
      (end-of-input))
     (vector (make-token :type :const :text "const")
             (make-token :type :equals :text "=")))
    (ok value next failure)
    (declare (ignore ok value next))
    (expect ok :to-be-falsy)
    (expect (parse-failure-position failure) :to-equal 1)
    (expect (parse-failure-expected failure) :to-equal :binding-name)
    (expect (parse-failure-committed-p failure) :to-be-truthy)
    (expect (token-type (parse-failure-actual failure)) :to-equal :equals)))
