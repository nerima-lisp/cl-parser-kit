(in-package :cl-parser-kit/test)

(defun %basic-tokenizer-rules ()
  (list (make-whitespace-rule :skip-p t)
        (make-literal-rule :plus "+")
        (make-number-rule)
        (make-identifier-rule)))

(defun %number-only-tokenizer-rules ()
  (list (make-whitespace-rule :skip-p t)
        (make-number-rule)))

(defun %skip-line-comment-tokenizer-rules ()
  (list (make-whitespace-rule :skip-p t)
        (make-line-comment-rule :skip-p t)
        (make-number-rule)
        (make-identifier-rule)))

(defun %skip-block-comment-tokenizer-rules ()
  (list (make-whitespace-rule :skip-p t)
        (make-block-comment-rule :skip-p t)
        (make-number-rule)
        (make-identifier-rule)))

(defun %make-line-comment-tokenizer (&key (skip-p t) (value-function #'identity))
  (make-tokenizer
   :rules (list (make-whitespace-rule :skip-p t)
                (make-line-comment-rule :skip-p skip-p
                                        :value-function value-function)
                (make-number-rule))))

(defun %make-block-comment-tokenizer (&key (skip-p t) (value-function #'identity))
  (make-tokenizer
   :rules (list (make-whitespace-rule :skip-p t)
                (make-block-comment-rule :skip-p skip-p
                                         :value-function value-function)
                (make-number-rule))))

(defun %make-arrow-tokenizer ()
  (make-tokenizer
   :rules (list (make-whitespace-rule :skip-p t)
                (make-literal-rule :arrow "->")
                (make-identifier-rule))))

(defun %make-let-keyword-tokenizer (&key include-lparen-p)
  (make-tokenizer
   :rules (append (list (make-whitespace-rule :skip-p t)
                        (make-keyword-rule :let "let"))
                  (when include-lparen-p
                    (list (make-literal-rule :lparen "(")))
                  (list (make-identifier-rule)))))

(defun %make-custom-boundary-keyword-tokenizer ()
  (let ((identifier-continue-p (%tokenizer-continue-predicate)))
    (make-tokenizer
     :rules (list (make-whitespace-rule :skip-p t)
                  (make-keyword-rule :if "if"
                                     :identifier-char-predicate
                                     identifier-continue-p)
                  (make-identifier-rule
                   :continue-predicate identifier-continue-p)))))

(defun %make-string-tokenizer (&key escape-char)
  (make-tokenizer
   :rules (list (make-whitespace-rule :skip-p t)
                (make-string-rule :escape-char escape-char)
                (make-identifier-rule))))

(defun %make-predicate-word-tokenizer ()
  (make-tokenizer
   :rules (list (make-whitespace-rule :skip-p t)
                (make-predicate-rule :word #'alpha-char-p
                                     :min-length 2
                                     :value-function #'string-downcase))))

(defun %make-custom-identifier-tokenizer ()
  (let ((identifier-continue-p (%tokenizer-continue-predicate t)))
    (make-tokenizer
     :rules (list (make-whitespace-rule :skip-p t)
                  (make-identifier-rule
                   :start-predicate identifier-continue-p
                   :continue-predicate identifier-continue-p)))))
