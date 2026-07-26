(in-package :cl-parser-kit/test)

(defun %tokenizer-continue-predicate (&optional (allow-dollar-p nil))
  (lambda (char)
    (or (alpha-char-p char)
        (digit-char-p char)
        (char= char #\_)
        (char= char #\-)
        (char= char #\?)
        (and allow-dollar-p
             (char= char #\$)))))

(defun %make-tokenizer-token-spec (&key (type nil type-supplied-p)
                                        (value nil value-supplied-p)
                                        (text nil text-supplied-p)
                                        (span nil span-supplied-p))
  (let ((spec '()))
    (when type-supplied-p
      (setf spec (append spec (list :type type))))
    (when value-supplied-p
      (setf spec (append spec (list :value value))))
    (when text-supplied-p
      (setf spec (append spec (list :text text))))
    (when span-supplied-p
      (setf spec (append spec (list :span span))))
    spec))

(defmacro assert-tokenizer-tokens (tokens expected-specs)
  `(let ((actual-tokens ,tokens)
         (expected-token-specs ,expected-specs))
     (expect (length actual-tokens) :to-equal (length expected-token-specs))
     (loop for expected in expected-token-specs
           for index from 0
           for token = (aref actual-tokens index)
           do (expect (token-type token) :to-equal (getf expected :type))
              (when (member :text expected)
                (expect (token-text token) :to-equal (getf expected :text)))
              (when (member :value expected)
                (expect (token-value token) :to-equal (getf expected :value)))
              (when (member :span expected)
                (destructuring-bind (start-line start-column end-line end-column)
                    (getf expected :span)
                  (let ((span (token-span token)))
                    (expect (span-start-line span) :to-equal start-line)
                    (expect (span-start-column span) :to-equal start-column)
                    (expect (span-end-line span) :to-equal end-line)
                    (expect (span-end-column span) :to-equal end-column)))))))
