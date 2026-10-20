(in-package :cl-parser-kit)

(defparameter *maximum-tokenizer-source-length* 10000000
  "Maximum SOURCE length (in characters) TOKENIZE accepts before signaling
TOKENIZER-RESOURCE-LIMIT-EXCEEDED instead of tokenizing. Guards against an
adversarially huge source string exhausting memory. Rebind or SETF to raise
it for intentionally large legitimate inputs.")

(defparameter *maximum-tokenizer-tokens* 2000000
  "Maximum number of tokens TOKENIZE emits before signaling
TOKENIZER-RESOURCE-LIMIT-EXCEEDED instead of continuing. Guards against a
source that is short but expands into an unbounded number of token structs
(each carrying its own span). Rebind or SETF to raise it for intentionally
token-dense inputs.")

(defparameter *maximum-tokenizer-rules* 100000
  "Maximum number of token rules TOKENIZE accepts on a tokenizer before
signaling TOKENIZER-RESOURCE-LIMIT-EXCEEDED. Guards against circular or
adversarially huge rule lists at the public tokenizer boundary.")

(defparameter *maximum-tokenizer-rule-alternatives* 100000
  "Maximum number of literal alternatives accepted by rule constructors such as
MAKE-OPERATOR-RULE before signaling TOKENIZER-RESOURCE-LIMIT-EXCEEDED.")
(defparameter *maximum-tokenizer-mode-depth* 100000
  "Maximum nesting depth of the tokenizer's mode stack. Rebind or SETF this
value, or supply :MAX-MODE-DEPTH to MAKE-TOKENIZER-CURSOR, to limit pushed
tokenizer modes.")

(define-resource-limit-condition tokenizer-resource-limit-exceeded
    "Tokenizer resource limit exceeded: ~A is ~A, limit is ~A"
  :documentation "Signaled by TOKENIZE and tokenizer rule constructors when a
public tokenizer boundary exceeds its configured resource limits. Catchable so
embedders can turn a hostile input into a diagnostic instead of an unbounded
allocation.")

(defstruct (token-rule (:constructor %make-token-rule
                            (&key type matcher skip-p action first-characters)))
  "One tokenizer rule. MATCHER is called with (SOURCE INDEX) and returns NIL
for no match, or T plus the matched length and optionally token text and value.
SKIP-P consumes a match without emitting a token. ACTION is a static mode
transition: (:PUSH mode), :POP, or (:SWITCH mode). FIRST-CHARACTERS is NIL for
a matcher that may start with any character, or a vector of possible starts."
  type
  matcher
  skip-p
  action
  first-characters)

(defstruct (tokenizer (:constructor %make-tokenizer
                            (&key rules modes initial-mode legacy-p mode-dispatches
                                  (unknown-token-type :unknown))))
  "An ordered tokenizer with optional named rule modes.

Rules retain their order within each mode. When no rule matches, one character
is emitted with UNKNOWN-TOKEN-TYPE. Legacy :RULES tokenizers use an internal
:DEFAULT mode."
  rules
  modes
  initial-mode
  legacy-p
  mode-dispatches
  unknown-token-type)
(defstruct (%tokenizer-mode-dispatch
             (:constructor %make-tokenizer-mode-dispatch
                 (&key rules fallback-rules fallback-indices
                       by-first-character indexed-p)))
  rules
  fallback-rules
  fallback-indices
  by-first-character
  indexed-p)

(defun token-rule-match (rule source index)
  (funcall (token-rule-matcher rule) source index))

(defun %build-tokenizer-mode-dispatch (rule-sequence)
  (let ((rules (if (vectorp rule-sequence)
                   (copy-seq rule-sequence)
                   (coerce rule-sequence 'vector)))
        (fallback-rules (make-array 0 :adjustable t :fill-pointer 0))
        (fallback-indices (make-array 0 :adjustable t :fill-pointer 0))
        (by-first-character (make-hash-table :test #'eql)))
    (loop for rule across rules
          for index from 0
          for first-characters = (token-rule-first-characters rule)
          do (if first-characters
                 (loop for character across first-characters
                       for candidates = (or (gethash character by-first-character)
                                            (setf (gethash character by-first-character)
                                                  (make-array 0 :adjustable t
                                                              :fill-pointer 0)))
                       do (vector-push-extend index candidates))
                 (progn
                   (vector-push-extend rule fallback-rules)
                   (vector-push-extend index fallback-indices))))
    (%make-tokenizer-mode-dispatch
     :rules rules
     :fallback-rules fallback-rules
     :fallback-indices fallback-indices
     :by-first-character by-first-character
     :indexed-p (plusp (hash-table-count by-first-character)))))

(defun %ensure-tokenizer-rule-alternatives-vector (alternatives kind)
  (multiple-value-bind (stream count too-many-p)
      (ensure-vector-up-to alternatives *maximum-tokenizer-rule-alternatives*)
    (when too-many-p
      (error 'tokenizer-resource-limit-exceeded
             :kind kind
             :value count
             :limit *maximum-tokenizer-rule-alternatives*))
    stream))

(defun %tokenize-emit (source type text value start end
                       start-line start-column end-line end-column
                       &optional token-constructor)
  (if token-constructor
      (let ((token (funcall token-constructor type text value start end
                            start-line start-column)))
        (when (null token)
          (error "TOKEN-CONSTRUCTOR returned NIL."))
        token)
      (make-token :type type
                  :text text
                  :value value
                  :start start
                  :end end
                  :span (make-span :source source
                                   :start start
                                   :end end
                                   :start-line start-line
                                   :start-column start-column
                                   :end-line end-line
                                   :end-column end-column))))

(defun %tokenize-rule-match (rule source index line column
                            &optional token-constructor)
  "Try RULE at INDEX, returning its end position and emitted token if any."
  (multiple-value-bind (ok rule-length text value)
      (token-rule-match rule source index)
    (if ok
        (progn
          (when (<= rule-length 0)
            (error "Tokenizer rule ~S matched without consuming input at position ~D"
                   rule index))
          (let ((end (+ index rule-length)))
            (multiple-value-bind (end-line end-column)
                (advance-position source index end line column)
              (values t end end-line end-column
                      (unless (token-rule-skip-p rule)
                        (%tokenize-emit source (token-rule-type rule) text value
                                        index end line column end-line end-column
                                        token-constructor))))))
        (values nil index line column nil))))

(defun %tokenize-first-match (rules source index line column
                             &optional token-constructor)
  "Return the first matching rule and its token and next source position."
  (loop for rule across rules
        do (multiple-value-bind (matched-p end end-line end-column token)
               (%tokenize-rule-match rule source index line column
                                     token-constructor)
             (when matched-p
               (return (values t rule end end-line end-column token))))
        finally (return (values nil nil index line column nil))))
(defun %tokenize-dispatch-first-match (dispatch source index line column
                                       &optional token-constructor)
  "Try the current character's indexed rules and fallback rules in definition order."
  (let* ((rules (%tokenizer-mode-dispatch-rules dispatch))
         (specific
           (gethash (char source index)
                    (%tokenizer-mode-dispatch-by-first-character dispatch)))
         (fallback-rules (%tokenizer-mode-dispatch-fallback-rules dispatch)))
    (if (null specific)
        (%tokenize-first-match fallback-rules source index line column
                               token-constructor)
        (let ((specific-length (length specific))
              (fallback-indices
                (%tokenizer-mode-dispatch-fallback-indices dispatch))
              (fallback-position 0)
              (specific-position 0))
          (loop while (or (< specific-position specific-length)
                          (< fallback-position (length fallback-indices)))
                for fallback-p =
                  (or (>= specific-position specific-length)
                      (and (< fallback-position (length fallback-indices))
                           (< (aref fallback-indices fallback-position)
                              (aref specific specific-position))))
                for rule-index =
                  (if fallback-p
                      (aref fallback-indices fallback-position)
                      (aref specific specific-position))
                for rule = (aref rules rule-index)
                do (multiple-value-bind (matched-p end end-line end-column token)
                       (%tokenize-rule-match rule source index line column
                                             token-constructor)
                     (when matched-p
                       (return (values t rule end end-line end-column token))))
                   (if fallback-p
                       (incf fallback-position)
                       (incf specific-position))
                finally (return (values nil nil index line column nil)))))))

(defun %tokenize-unknown (tokenizer source index line column
                         &optional token-constructor)
  "Build an unknown-token fallback and return its next source position."
  (let* ((char (char source index))
         (text (string char))
         (end (1+ index)))
    (multiple-value-bind (end-line end-column)
        (advance-position source index end line column)
      (values end end-line end-column
              (%tokenize-emit source (tokenizer-unknown-token-type tokenizer)
                              text char index end
                              line column end-line end-column
                              token-constructor)))))

(defun tokenize (source tokenizer
                        &key (max-source-length *maximum-tokenizer-source-length*)
                        (max-tokens *maximum-tokenizer-tokens*)
                        (max-rules *maximum-tokenizer-rules*)
                        (max-mode-depth *maximum-tokenizer-mode-depth*)
                        on-limit-exceeded token-constructor)
  "Tokenize SOURCE into a vector using TOKENIZER-CURSOR-NEXT.

ON-LIMIT-EXCEEDED receives limit details before the usual condition is signaled.
TOKEN-CONSTRUCTOR receives (TYPE TEXT VALUE START END LINE COLUMN) and must
return a non-NIL object for each emitted token."
  (let ((cursor (make-tokenizer-cursor source tokenizer
                                       :max-source-length max-source-length
                                       :max-tokens max-tokens
                                       :max-rules max-rules
                                       :max-mode-depth max-mode-depth
                                       :on-limit-exceeded on-limit-exceeded
                                       :token-constructor token-constructor)))
    (coerce (loop for token = (tokenizer-cursor-next cursor)
                  while token
                  collect token)
            'vector)))

(defun tokenize-string (source tokenizer &rest options)
  "Alias for TOKENIZE that forwards all tokenizer options."
  (apply #'tokenize source tokenizer options))

(defun %token-rule-action-components (action)
  (cond
    ((null action) (values nil nil))
    ((eq action :pop) (values :pop nil))
    ((consp action)
     (multiple-value-bind (parts count too-many-p)
         (handler-case
             (ensure-vector-up-to action 2)
           (error (condition)
             (error "Malformed token rule action ~S: ~A" action condition)))
       (when (or too-many-p (/= count 2))
         (error "Malformed token rule action ~S; expected (:PUSH mode), :POP, or (:SWITCH mode)."
                action))
       (let ((operation (aref parts 0))
             (mode (aref parts 1)))
         (unless (member operation '(:push :switch))
           (error "Malformed token rule action ~S; expected (:PUSH mode), :POP, or (:SWITCH mode)."
                  action))
         (unless (symbolp mode)
           (error "Malformed token rule action ~S; mode must be a symbol." action))
         (values operation mode))))
    (t
     (error "Malformed token rule action ~S; expected (:PUSH mode), :POP, or (:SWITCH mode)."
            action))))
(defun %ensure-token-rule-first-characters (first-characters)
  (when first-characters
    (let ((sequence
            (cond
              ((stringp first-characters) first-characters)
              ((vectorp first-characters) first-characters)
              ((listp first-characters)
               (%check-proper-acyclic-list first-characters)
               (coerce first-characters 'vector))
              (t
               (error "FIRST-CHARACTERS must be a character sequence, got ~S."
                      first-characters))))
          (seen (make-hash-table :test #'eql))
          (characters (make-array 0 :element-type 'character
                                  :adjustable t :fill-pointer 0)))
      (loop for character across sequence
            do (unless (characterp character)
                 (error "FIRST-CHARACTERS contains non-character ~S." character))
               (unless (gethash character seen)
                 (setf (gethash character seen) t)
                 (vector-push-extend character characters)))
      (when (zerop (length characters))
        (error "FIRST-CHARACTERS must contain at least one character."))
      (coerce characters 'vector))))

(defun make-token-rule (&key type matcher skip-p action first-characters)
  "Construct a TOKEN-RULE with an optional static mode ACTION.

FIRST-CHARACTERS declares every character at which MATCHER may match. Omit it
when MATCHER can begin with any character; the rule then remains a fallback
candidate for every input character."
  (%token-rule-action-components action)
  (%make-token-rule :type type
                    :matcher matcher
                    :skip-p skip-p
                    :action action
                    :first-characters
                    (%ensure-token-rule-first-characters first-characters)))

(defun make-tokenizer (&key (rules nil rules-p)
                            (modes nil modes-p)
                            (initial-mode nil initial-mode-p)
                            (unknown-token-type :unknown))
  "Build a tokenizer from legacy :RULES or ordered named :MODES.

Each named mode entry is a dotted pair of its symbol and ordered rule sequence.
The initial mode defaults to the first named mode; a legacy tokenizer uses the
internal :DEFAULT mode. Rule actions must refer to a declared mode."
  (when (and rules-p modes-p)
    (error "Supply either :RULES or :MODES, not both."))
  (labels ((validate-rule-sequence (sequence)
             (unless (or (null sequence)
                         (and (consp sequence) (listp sequence))
                         (and (vectorp sequence) (not (stringp sequence))))
               (error "Tokenizer rules must be a proper list or vector, got ~S."
                      sequence))
             (labels ((validate-rule (rule)
                        (unless (token-rule-p rule)
                          (error "Tokenizer rule sequence contains ~S, not a token rule."
                                 rule))
                        (%token-rule-action-components (token-rule-action rule))))
               (if (listp sequence)
                   (progn
                     (%check-proper-acyclic-list sequence)
                     (dolist (rule sequence) (validate-rule rule)))
                   (loop for rule across sequence do (validate-rule rule)))))
           (validate-action-targets (sequence entries)
             (labels ((validate-rule (rule)
                        (multiple-value-bind (operation mode)
                            (%token-rule-action-components (token-rule-action rule))
                          (when (and (member operation '(:push :switch))
                                     (not (assoc mode entries :test #'eq)))
                            (error "Tokenizer action ~S refers to unknown mode ~S."
                                   (token-rule-action rule) mode)))))
               (if (listp sequence)
                   (dolist (rule sequence) (validate-rule rule))
                   (loop for rule across sequence do (validate-rule rule)))))
           (validate-entry (entry seen)
             (unless (and (consp entry) (symbolp (car entry)))
               (error "Malformed tokenizer mode entry ~S; expected (mode . rules)."
                      entry))
             (when (member (car entry) seen :test #'eq)
               (error "Duplicate tokenizer mode ~S." (car entry)))
             (validate-rule-sequence (cdr entry))))
    (let ((entries (if modes-p modes (list (cons :default rules))))
          (seen nil))
      (unless (and modes-p (listp entries) entries)
        (when modes-p
          (error ":MODES must be a non-empty proper list of (mode . rules) entries.")))
      (when modes-p
        (%check-proper-acyclic-list entries)
        (dolist (entry entries)
          (validate-entry entry seen)
          (push (car entry) seen)))
      (unless modes-p
        (validate-rule-sequence rules))
      (let ((selected-mode (if initial-mode-p
                               initial-mode
                               (if modes-p (caar entries) :default))))
        (unless (and (symbolp selected-mode)
                     (assoc selected-mode entries :test #'eq))
          (error "Unknown initial tokenizer mode ~S." selected-mode))
        (dolist (entry entries)
          (validate-action-targets (cdr entry) entries))
        (let ((mode-dispatches
                (loop for (mode . rule-sequence) in entries
                      collect (cons mode
                                    (%build-tokenizer-mode-dispatch rule-sequence)))))
          (%make-tokenizer :rules rules
                           :modes entries
                           :initial-mode selected-mode
                           :legacy-p (not modes-p)
                           :mode-dispatches mode-dispatches
                           :unknown-token-type unknown-token-type))))))
(defstruct (tokenizer-cursor
             (:constructor %make-tokenizer-cursor
                 (&key source tokenizer modes current-rules current-dispatch
                       mode-stack index line column token-count max-tokens
                       max-mode-depth on-limit-exceeded token-constructor)))
  "Incremental token-production state over one complete source string."
  source
  tokenizer
  modes
  current-rules
  current-dispatch
  mode-stack
  index
  line
  column
  token-count
  max-tokens
  max-mode-depth
  on-limit-exceeded
  token-constructor)

(defun %tokenizer-rule-sequence-count (sequence)
  (cond
   ((null sequence) 0)
   ((consp sequence)
    (%check-proper-acyclic-list sequence)
    (length sequence))
   ((and (vectorp sequence) (not (stringp sequence)))
    (length sequence))
   (t
    (error "Tokenizer rules must be a proper list or vector, got ~S."
           sequence))))

(defun make-tokenizer-cursor (source tokenizer
                                     &key
                                     (max-source-length
                                      *maximum-tokenizer-source-length*)
                                     (max-tokens *maximum-tokenizer-tokens*)
                                     (max-rules *maximum-tokenizer-rules*)
                                     (max-mode-depth *maximum-tokenizer-mode-depth*)
                                     on-limit-exceeded token-constructor)
  "Create a pull cursor over SOURCE using TOKENIZER.

ON-LIMIT-EXCEEDED receives (KIND LIMIT VALUE OFFSET LINE COLUMN) before the
usual condition is signaled. TOKEN-CONSTRUCTOR receives (TYPE TEXT VALUE START
END LINE COLUMN) for each emitted token and must return a non-NIL object."
  (check-type source string)
  (check-type tokenizer tokenizer)
  (check-type max-source-length (integer 0 *))
  (check-type max-tokens (integer 0 *))
  (check-type max-rules (integer 0 *))
  (check-type max-mode-depth (integer 0 *))
  (let ((source-length (length source))
        (mode-entries (tokenizer-modes tokenizer))
        (mode-dispatches (tokenizer-mode-dispatches tokenizer))
        (rule-count 0))
    (when (> source-length max-source-length)
      (when on-limit-exceeded
        (multiple-value-bind (line column)
            (advance-position source 0 max-source-length 1 1)
          (funcall on-limit-exceeded :source-length max-source-length
                   source-length max-source-length line column)))
      (error 'tokenizer-resource-limit-exceeded
             :kind :source-length :value source-length
             :limit max-source-length))
    (%check-proper-acyclic-list mode-entries)
    (dolist (entry mode-entries)
      (unless (and (consp entry) (symbolp (car entry)))
        (error "Malformed tokenizer mode entry ~S." entry))
      (incf rule-count (%tokenizer-rule-sequence-count (cdr entry)))
      (when (> rule-count max-rules)
        (when on-limit-exceeded
          (funcall on-limit-exceeded :rule-count max-rules rule-count 0 1 1))
        (error 'tokenizer-resource-limit-exceeded
               :kind :rule-count :value rule-count :limit max-rules)))
    (let* ((initial-mode (tokenizer-initial-mode tokenizer))
           (initial-mode-entry
             (assoc initial-mode mode-dispatches :test #'eq)))
      (unless initial-mode-entry
        (error "Unknown initial tokenizer mode ~S." initial-mode))
      (when (> 1 max-mode-depth)
        (when on-limit-exceeded
          (funcall on-limit-exceeded :mode-depth max-mode-depth 1 0 1 1))
        (error 'tokenizer-resource-limit-exceeded
               :kind :mode-depth :value 1 :limit max-mode-depth))
      (%make-tokenizer-cursor :source source
                              :tokenizer tokenizer
                              :modes mode-dispatches
                              :current-rules
                              (%tokenizer-mode-dispatch-rules
                               (cdr initial-mode-entry))
                              :current-dispatch (cdr initial-mode-entry)
                              :mode-stack (list initial-mode)
                              :index 0
                              :line 1
                              :column 1
                              :token-count 0
                              :max-tokens max-tokens
                              :max-mode-depth max-mode-depth
                              :on-limit-exceeded on-limit-exceeded
                              :token-constructor token-constructor))))

(defun %tokenizer-cursor-apply-action (cursor rule offset line column)
  (multiple-value-bind (operation mode)
      (%token-rule-action-components (token-rule-action rule))
    (case operation
      (:push
       (let ((mode-entry
               (assoc mode (tokenizer-cursor-modes cursor) :test #'eq)))
         (unless mode-entry
           (error "Tokenizer action refers to unknown mode ~S." mode))
         (let ((depth (1+ (length (tokenizer-cursor-mode-stack cursor)))))
           (when (> depth (tokenizer-cursor-max-mode-depth cursor))
             (let ((callback (tokenizer-cursor-on-limit-exceeded cursor)))
               (when callback
                 (funcall callback :mode-depth
                          (tokenizer-cursor-max-mode-depth cursor)
                          depth offset line column)))
             (error 'tokenizer-resource-limit-exceeded
                    :kind :mode-depth
                    :value depth
                    :limit (tokenizer-cursor-max-mode-depth cursor)))
           (push mode (tokenizer-cursor-mode-stack cursor))
           (setf (tokenizer-cursor-current-rules cursor)
                 (%tokenizer-mode-dispatch-rules (cdr mode-entry))
                 (tokenizer-cursor-current-dispatch cursor)
                 (cdr mode-entry)))))
      (:pop
       (unless (cdr (tokenizer-cursor-mode-stack cursor))
         (error "Tokenizer mode stack underflow while applying :POP."))
       (let* ((mode-stack (cdr (tokenizer-cursor-mode-stack cursor)))
              (mode-entry
                (assoc (car mode-stack)
                       (tokenizer-cursor-modes cursor)
                       :test #'eq)))
         (setf (tokenizer-cursor-mode-stack cursor) mode-stack
               (tokenizer-cursor-current-rules cursor)
               (%tokenizer-mode-dispatch-rules (cdr mode-entry))
               (tokenizer-cursor-current-dispatch cursor)
               (cdr mode-entry))))
      (:switch
       (let ((mode-entry
               (assoc mode (tokenizer-cursor-modes cursor) :test #'eq)))
         (unless mode-entry
           (error "Tokenizer action refers to unknown mode ~S." mode))
         (setf (car (tokenizer-cursor-mode-stack cursor)) mode
               (tokenizer-cursor-current-rules cursor)
               (%tokenizer-mode-dispatch-rules (cdr mode-entry))
               (tokenizer-cursor-current-dispatch cursor)
               (cdr mode-entry)))))))

(defun %tokenizer-cursor-count-token (cursor offset line column)
  (let* ((next-count (1+ (tokenizer-cursor-token-count cursor)))
         (limit (tokenizer-cursor-max-tokens cursor))
         (callback (tokenizer-cursor-on-limit-exceeded cursor)))
    (when (> next-count limit)
      (when callback
        (funcall callback :token-count limit next-count offset line column))
      (error 'tokenizer-resource-limit-exceeded
             :kind :token-count
             :value next-count
             :limit limit))
    (setf (tokenizer-cursor-token-count cursor) next-count)))

(defun tokenizer-cursor-next (cursor)
  "Return the next emitted token, processing skipped rules, or NIL at EOF."
  (check-type cursor tokenizer-cursor)
  (loop
   for source = (tokenizer-cursor-source cursor)
   for index = (tokenizer-cursor-index cursor)
   for line = (tokenizer-cursor-line cursor)
   for column = (tokenizer-cursor-column cursor)
   while (< index (length source))
   do (let* ((rules (tokenizer-cursor-current-rules cursor))
             (dispatch (tokenizer-cursor-current-dispatch cursor)))
        (multiple-value-bind (matched-p rule end end-line end-column token)
            (if (%tokenizer-mode-dispatch-indexed-p dispatch)
                (%tokenize-dispatch-first-match
                 dispatch source index line column
                 (tokenizer-cursor-token-constructor cursor))
                (%tokenize-first-match
                 rules source index line column
                 (tokenizer-cursor-token-constructor cursor)))
          (if matched-p
              (progn
                (setf (tokenizer-cursor-index cursor) end
                      (tokenizer-cursor-line cursor) end-line
                      (tokenizer-cursor-column cursor) end-column)
                (when (token-rule-action rule)
                  (%tokenizer-cursor-apply-action cursor rule index line column))
                (when token
                  (%tokenizer-cursor-count-token cursor index line column)
                  (return token)))
            (multiple-value-bind (end end-line end-column unknown-token)
                (%tokenize-unknown
                 (tokenizer-cursor-tokenizer cursor) source index line column
                 (tokenizer-cursor-token-constructor cursor))
              (setf (tokenizer-cursor-index cursor) end
                    (tokenizer-cursor-line cursor) end-line
                    (tokenizer-cursor-column cursor) end-column)
              (%tokenizer-cursor-count-token cursor index line column)
              (return unknown-token)))))
   finally (return nil)))
