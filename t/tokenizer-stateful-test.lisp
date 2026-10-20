(in-package :cl-parser-kit/test)

(defun %expect-tokenizer-resource-limit (thunk kind value limit)
  (let ((condition
          (handler-case (progn (funcall thunk) nil)
            (tokenizer-resource-limit-exceeded (caught) caught))))
    (expect condition :to-be-truthy)
    (when condition
      (expect (tokenizer-resource-limit-exceeded-kind condition) :to-equal kind)
      (expect (tokenizer-resource-limit-exceeded-value condition) :to-equal value)
      (expect (tokenizer-resource-limit-exceeded-limit condition) :to-equal limit))
    condition))
(it-sequential "stateful-tokenizer-push-pop-restores-prior-mode-test"
  (let* ((tokenizer
           (make-tokenizer
            :modes
            (list (cons :content
                        (list (make-literal-rule :open "<"
                                                 :action '(:push :inside))
                              (make-literal-rule :tail "z")))
                  (cons :inside
                        (list (make-literal-rule :close ">" :action :pop)
                              (make-literal-rule :inner "a"))))
            :initial-mode :content))
         (tokens (tokenize "<a>z" tokenizer)))
    (expect (map 'list #'token-type tokens)
            :to-equal '(:open :inner :close :tail))))
(it-sequential "stateful-tokenizer-applies-actions-on-skipped-rules-test"
  (let* ((tokenizer
           (make-tokenizer
            :modes
            (list (cons :content
                        (list (make-literal-rule :start "!"
                                                 :skip-p t
                                                 :action '(:push :quoted))
                              (make-literal-rule :tail "y")))
                  (cons :quoted
                        (list (make-literal-rule :end "!"
                                                 :skip-p t
                                                 :action :pop)
                              (make-literal-rule :text "x"))))
            :initial-mode :content))
         (tokens (tokenize "!x!y" tokenizer)))
    (expect (map 'list #'token-type tokens)
            :to-equal '(:text :tail))))
(it-sequential "stateful-tokenizer-switch-replaces-current-mode-test"
  (let* ((tokenizer
           (make-tokenizer
            :modes
            (list (cons :content
                        (list (make-literal-rule :open "<"
                                                 :action '(:switch :inside))
                              (make-literal-rule :tail "y")))
                  (cons :inside
                        (list (make-literal-rule :inner "x"
                                                 :action '(:switch :content)))))
            :initial-mode :content))
         (tokens (tokenize "<xy" tokenizer)))
    (expect (map 'list #'token-type tokens)
            :to-equal '(:open :inner :tail))))
(it-sequential "stateful-tokenizer-mode-selection-order-and-fallback-test"
  (let* ((content-tokenizer
           (make-tokenizer
            :modes
            (list (cons :content
                        (list (make-literal-rule :long "ab")
                              (make-literal-rule :short "a")))
                  (cons :comment
                        (list (make-literal-rule :comment "?"))))
            :unknown-token-type :unexpected))
         (content-tokens (tokenize "ab?" content-tokenizer))
         (comment-tokenizer
           (make-tokenizer
            :modes
            (list (cons :content nil)
                  (cons :comment (list (make-literal-rule :comment "?"))))
            :initial-mode :comment)))
    (expect (tokenizer-initial-mode content-tokenizer) :to-equal :content)
    (expect (map 'list #'car (tokenizer-modes content-tokenizer))
            :to-equal '(:content :comment))
    (expect (map 'list #'token-type content-tokens)
            :to-equal '(:long :unexpected))
    (expect (token-type (tokenizer-cursor-next
                         (make-tokenizer-cursor "?" comment-tokenizer)))
            :to-equal :comment)))
(it-sequential "stateful-tokenizer-rejects-malformed-mode-and-action-input-test"
  (expect (lambda () (make-tokenizer :modes nil)) :to-throw 'error)
  (expect (lambda ()
            (make-tokenizer :modes (list (cons :same nil)
                                         (cons :same nil))))
          :to-throw 'error)
  (expect (lambda ()
            (make-tokenizer :modes (list (list :content nil))))
          :to-throw 'error)
  (expect (lambda ()
            (make-tokenizer :modes (list (cons :content nil))
                            :initial-mode :missing))
          :to-throw 'error)
  (expect (lambda ()
            (make-token-rule :type :bad :matcher #'identity
                             :action '(:push)))
          :to-throw 'error)
  (let ((rule (make-token-rule :type :bad
                               :matcher #'identity
                               :action '(:push :missing))))
    (expect (lambda ()
              (make-tokenizer :modes (list (cons :content (list rule)))))
            :to-throw 'error)))
(it-sequential "stateful-tokenizer-reports-mode-stack-underflow-test"
  (let* ((tokenizer
           (make-tokenizer
            :modes (list (cons :content
                               (list (make-literal-rule :close ")" :action :pop))))))
         (cursor (make-tokenizer-cursor ")" tokenizer)))
    (expect (lambda () (tokenizer-cursor-next cursor)) :to-throw 'error)))
(it-sequential "stateful-tokenizer-pull-cursor-returns-one-token-and-eof-test"
  (let* ((tokenizer
           (make-tokenizer :rules (list (make-whitespace-rule :skip-p t)
                                        (make-identifier-rule))))
         (cursor (make-tokenizer-cursor "a b" tokenizer))
         (first-token (tokenizer-cursor-next cursor))
         (second-token (tokenizer-cursor-next cursor)))
    (expect (token-text first-token) :to-equal "a")
    (expect (token-text second-token) :to-equal "b")
    (expect (tokenizer-cursor-next cursor) :to-be-null)
    (expect (tokenizer-cursor-next cursor) :to-be-null)))
(it-sequential "stateful-tokenizer-pull-and-vector-apis-have-parity-test"
  (labels ((token-details (tokens)
             (map 'list
                  (lambda (token)
                    (let ((span (token-span token)))
                      (list (token-type token)
                            (token-text token)
                            (token-value token)
                            (token-start token)
                            (token-end token)
                            (span-start-line span)
                            (span-start-column span)
                            (span-end-line span)
                            (span-end-column span))))
                  tokens)))
    (let* ((tokenizer (make-tokenizer :rules (%basic-tokenizer-rules)))
           (source "sum + 42")
           (vector-tokens (tokenize source tokenizer))
           (cursor (make-tokenizer-cursor source tokenizer))
           (pull-tokens (loop for token = (tokenizer-cursor-next cursor)
                              while token
                              collect token)))
      (expect (token-details vector-tokens)
              :to-equal (token-details pull-tokens)))))
(it-sequential "stateful-tokenizer-pull-preserves-span-offsets-and-line-columns-test"
  (let* ((source (format nil "a~%b"))
         (cursor (make-tokenizer-cursor
                  source
                  (make-tokenizer :rules (list (make-identifier-rule)))))
         (first-token (tokenizer-cursor-next cursor))
         (newline-token (tokenizer-cursor-next cursor))
         (last-token (tokenizer-cursor-next cursor))
         (first-span (token-span first-token))
         (newline-span (token-span newline-token))
         (last-span (token-span last-token)))
    (expect (list (token-start first-token) (token-end first-token)
                  (span-start-line first-span) (span-start-column first-span)
                  (span-end-line first-span) (span-end-column first-span))
            :to-equal '(0 1 1 1 1 2))
    (expect (list (token-start newline-token) (token-end newline-token)
                  (span-start-line newline-span) (span-start-column newline-span)
                  (span-end-line newline-span) (span-end-column newline-span))
            :to-equal '(1 2 1 2 2 1))
    (expect (list (token-start last-token) (token-end last-token)
                  (span-start-line last-span) (span-start-column last-span)
                  (span-end-line last-span) (span-end-column last-span))
            :to-equal '(2 3 2 1 2 2))))
(it-sequential "stateful-tokenizer-explicit-resource-limits-report-readers-test"
  (let ((tokenizer (make-tokenizer :rules nil)))
    (%expect-tokenizer-resource-limit
     (lambda () (make-tokenizer-cursor "ab" tokenizer :max-source-length 1))
     :source-length 2 1))
  (let* ((tokenizer (make-tokenizer :rules nil))
         (cursor (make-tokenizer-cursor "ab" tokenizer :max-tokens 1)))
    (tokenizer-cursor-next cursor)
    (%expect-tokenizer-resource-limit
     (lambda () (tokenizer-cursor-next cursor))
     :token-count 2 1))
  (let ((tokenizer
          (make-tokenizer
           :modes
           (list (cons :content (list (make-literal-rule :a "a")))
                 (cons :comment (list (make-literal-rule :comment ";")))))))
    (%expect-tokenizer-resource-limit
     (lambda () (make-tokenizer-cursor "" tokenizer :max-rules 1))
     :rule-count 2 1))
  (let* ((tokenizer
           (make-tokenizer
            :modes
            (list (cons :content
                        (list (make-literal-rule :open "!"
                                                 :action '(:push :inside))))
                  (cons :inside (list (make-literal-rule :inner "x"))))))
         (cursor (make-tokenizer-cursor "!x" tokenizer :max-mode-depth 1)))
    (%expect-tokenizer-resource-limit
     (lambda () (tokenizer-cursor-next cursor))
     :mode-depth 2 1)))
(it-sequential "stateful-tokenizer-dynamic-limit-defaults-and-keyword-overrides-test"
  (let ((tokenizer (make-tokenizer :rules nil)))
    (let ((*maximum-tokenizer-source-length* 1))
      (%expect-tokenizer-resource-limit
       (lambda () (make-tokenizer-cursor "ab" tokenizer))
       :source-length 2 1))
    (let ((*maximum-tokenizer-tokens* 1))
      (%expect-tokenizer-resource-limit
       (lambda () (tokenize "ab" tokenizer))
       :token-count 2 1)))
  (let ((tokenizer
          (make-tokenizer :rules (list (make-literal-rule :a "a")
                                       (make-literal-rule :b "b")))))
    (let ((*maximum-tokenizer-rules* 1))
      (%expect-tokenizer-resource-limit
       (lambda () (make-tokenizer-cursor "" tokenizer))
       :rule-count 2 1)))
  (let* ((tokenizer
           (make-tokenizer
            :modes
            (list (cons :content
                        (list (make-literal-rule :open "a"
                                                 :action '(:push :inside))))
                  (cons :inside (list (make-literal-rule :inner "b"))))))
         (*maximum-tokenizer-mode-depth* 1)
         (cursor (make-tokenizer-cursor "ab" tokenizer)))
    (%expect-tokenizer-resource-limit
     (lambda () (tokenizer-cursor-next cursor))
     :mode-depth 2 1))
  (let* ((*maximum-tokenizer-source-length* 0)
         (*maximum-tokenizer-tokens* 0)
         (*maximum-tokenizer-rules* 0)
         (*maximum-tokenizer-mode-depth* 0)
         (tokenizer
           (make-tokenizer
            :modes
            (list (cons :content
                        (list (make-literal-rule :open "a"
                                                 :action '(:push :inside))))
                  (cons :inside (list (make-literal-rule :inner "b"))))))
         (tokens
           (tokenize "ab" tokenizer
                     :max-source-length 2
                     :max-tokens 2
                     :max-rules 2
                     :max-mode-depth 2)))
    (expect (map 'list #'token-type tokens) :to-equal '(:open :inner))))
(it-sequential "stateful-tokenizer-limit-callback-data-and-location-test"
  (let ((callback-args nil))
    (%expect-tokenizer-resource-limit
     (lambda ()
       (make-tokenizer-cursor
        (format nil "a~%bc")
        (make-tokenizer :rules nil)
        :max-source-length 2
        :on-limit-exceeded
        (lambda (&rest args) (setf callback-args args))))
     :source-length 4 2)
    (expect callback-args :to-equal '(:source-length 2 4 2 2 1)))
  (let ((callback-args nil)
        (tokenizer
          (make-tokenizer
           :modes (list (cons :content (list (make-literal-rule :a "a")))
                        (cons :comment (list (make-literal-rule :b "b")))))))
    (%expect-tokenizer-resource-limit
     (lambda ()
       (make-tokenizer-cursor
        "" tokenizer :max-rules 1
        :on-limit-exceeded
        (lambda (&rest args) (setf callback-args args))))
     :rule-count 2 1)
    (expect callback-args :to-equal '(:rule-count 1 2 0 1 1)))
  (let* ((callback-args nil)
         (cursor
           (make-tokenizer-cursor
            (format nil "x~%y") (make-tokenizer :rules nil)
            :max-tokens 1
            :on-limit-exceeded
            (lambda (&rest args) (setf callback-args args)))))
    (tokenizer-cursor-next cursor)
    (%expect-tokenizer-resource-limit
     (lambda () (tokenizer-cursor-next cursor))
     :token-count 2 1)
    (expect callback-args :to-equal '(:token-count 1 2 1 1 2)))
  (let* ((callback-args nil)
         (tokenizer
           (make-tokenizer
            :modes
            (list (cons :content
                        (list (make-whitespace-rule :skip-p t)
                              (make-literal-rule :open "!"
                                                 :action '(:push :inside))))
                  (cons :inside (list (make-literal-rule :inner "x"))))))
         (cursor
           (make-tokenizer-cursor
            (format nil "~%!") tokenizer
            :max-mode-depth 1
            :on-limit-exceeded
            (lambda (&rest args) (setf callback-args args)))))
    (%expect-tokenizer-resource-limit
     (lambda () (tokenizer-cursor-next cursor))
     :mode-depth 2 1)
    (expect callback-args :to-equal '(:mode-depth 1 2 1 2 1))))
(it-sequential "stateful-tokenizer-limit-callback-nonlocal-exit-test"
  (let ((result
          (catch 'limit-handled
            (make-tokenizer-cursor
             "ab" (make-tokenizer :rules nil)
             :max-source-length 1
             :on-limit-exceeded
             (lambda (&rest args)
               (declare (ignore args))
               (throw 'limit-handled :callback-exited))))))
    (expect result :to-equal :callback-exited)))
(it-sequential "stateful-tokenizer-custom-token-constructor-pull-vector-and-default-test"
  (let* ((calls nil)
         (constructor
           (lambda (type text value start end line column)
             (let ((record (list type text value start end line column)))
               (push record calls)
               (cons :custom record))))
         (tokenizer (make-tokenizer :rules (list (make-identifier-rule))))
         (expected '(:custom :identifier "abc" "abc" 0 3 1 1))
         (cursor (make-tokenizer-cursor
                  "abc" tokenizer :token-constructor constructor))
         (pulled (tokenizer-cursor-next cursor))
         (vector-token
           (aref (tokenize "abc" tokenizer :token-constructor constructor) 0)))
    (expect pulled :to-equal expected)
    (expect vector-token :to-equal expected)
    (expect (nreverse calls)
            :to-equal '((:identifier "abc" "abc" 0 3 1 1)
                        (:identifier "abc" "abc" 0 3 1 1))))
  (let* ((tokenizer (make-tokenizer :rules (list (make-identifier-rule))))
         (token (aref (tokenize "abc" tokenizer) 0))
         (span (token-span token)))
    (expect (typep token 'cl-parser-kit::token) :to-be-truthy)
    (expect (token-type token) :to-equal :identifier)
    (expect (token-text token) :to-equal "abc")
    (expect (list (token-start token) (token-end token)
                  (span-start-line span) (span-start-column span)
                  (span-end-line span) (span-end-column span))
            :to-equal '(0 3 1 1 1 4)))
  (let* ((tokenizer (make-tokenizer :rules (list (make-identifier-rule))))
         (nil-constructor
           (lambda (type text value start end line column)
             (declare (ignore type text value start end line column))
             nil)))
    (expect (lambda ()
              (tokenizer-cursor-next
               (make-tokenizer-cursor
                "abc" tokenizer :token-constructor nil-constructor)))
            :to-throw 'error)
    (expect (lambda ()
              (tokenize "abc" tokenizer :token-constructor nil-constructor))
            :to-throw 'error)))
(it-sequential "stateful-tokenizer-tokenize-string-forwards-constructor-and-limit-callback-test"
  (let* ((tokenizer (make-tokenizer :rules (list (make-identifier-rule))))
         (token
           (aref
            (tokenize-string
             "a" tokenizer
             :token-constructor
             (lambda (type text value start end line column)
               (list :custom type text value start end line column)))
            0)))
    (expect token :to-equal '(:custom :identifier "a" "a" 0 1 1 1)))
  (let ((callback-args nil))
    (%expect-tokenizer-resource-limit
     (lambda ()
       (tokenize-string
        "ab" (make-tokenizer :rules nil)
        :max-source-length 1
        :on-limit-exceeded
        (lambda (&rest args) (setf callback-args args))))
     :source-length 2 1)
    (expect callback-args :to-equal '(:source-length 1 2 1 1 2))))
(it-sequential "first-character-dispatch-priority-and-fallback-test"
  (flet ((char-rule (type character first-characters)
           (make-token-rule
            :type type
            :first-characters first-characters
            :matcher
            (lambda (source index)
              (when (and (< index (length source))
                         (char= (char source index) character))
                (values t 1 (string character) character))))))
    (let* ((specific-before-fallback
             (tokenize
              "a"
              (make-tokenizer
               :rules (list (char-rule :specific #\a "a")
                            (char-rule :fallback #\a nil)))))
           (fallback-before-specific
             (tokenize
              "a"
              (make-tokenizer
               :rules (list (char-rule :fallback #\a nil)
                            (char-rule :specific #\a "a")))))
           (fallback-on-unlisted-character
             (tokenize
              "b"
              (make-tokenizer
               :rules (list (char-rule :a #\a "a")
                            (char-rule :fallback #\b nil)))))
           (unknown-on-unlisted-character
             (tokenize
              "b"
              (make-tokenizer
               :rules (list (char-rule :a #\a "a"))))))
      (expect (map 'list #'token-type specific-before-fallback)
              :to-equal '(:specific))
      (expect (map 'list #'token-type fallback-before-specific)
              :to-equal '(:fallback))
      (expect (map 'list #'token-type fallback-on-unlisted-character)
              :to-equal '(:fallback))
      (expect (map 'list #'token-type unknown-on-unlisted-character)
              :to-equal '(:unknown))))
  (expect (lambda () (make-token-rule :first-characters #()))
          :to-throw 'error)
  (expect (lambda ()
            (make-token-rule :first-characters (list #\a 1)))
          :to-throw 'error))
(it-sequential "first-character-dispatch-failed-candidate-falls-back-test"
  (let* ((source "a")
         (specific
           (make-token-rule
            :type :specific
            :first-characters "a"
            :matcher (lambda (source index)
                       (declare (ignore source index))
                       nil)))
         (fallback
           (make-token-rule
            :type :fallback
            :matcher (lambda (source index)
                       (when (char= (char source index) #\a)
                         (values t 1 "a" #\a)))))
         (tokens
           (tokenize source (make-tokenizer :rules (list specific fallback)))))
    (expect (map 'list #'token-type tokens)
            :to-equal '(:fallback))))
(it-sequential "first-character-dispatch-mode-transitions-update-index-test"
  (flet ((char-rule (type character first-characters &optional action)
           (make-token-rule
            :type type
            :action action
            :first-characters first-characters
            :matcher
            (lambda (source index)
              (when (and (< index (length source))
                         (char= (char source index) character))
                (values t 1 (string character) character)))))
         (content-rule ()
           (make-token-rule
            :type :text
            :matcher
            (lambda (source index)
              (when (< index (length source))
                (let ((character (char source index)))
                  (unless (char= character #\<)
                    (values t 1 (string character) character))))))))
    (let* ((tokenizer
             (make-tokenizer
              :modes
              (list
               (cons :content
                     (list (char-rule :open #\< "<" '(:push :tag))
                           (content-rule)))
               (cons :tag
                     (list (char-rule :name #\x "x" '(:switch :inside))))
               (cons :inside
                     (list (char-rule :close #\> ">" :pop))))
              :initial-mode :content))
           (tokens (tokenize "<x>a" tokenizer)))
      (expect (map 'list #'token-type tokens)
              :to-equal '(:open :name :close :text)))))
