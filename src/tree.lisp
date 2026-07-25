(in-package :cl-parser-kit)

(defparameter *maximum-tree-depth* 100000
  "Maximum AST/CST depth accepted by tree traversal, conversion, comparison, and
rendering helpers. Rebind or SETF to raise it for intentionally deep generated
trees.")

(defparameter *maximum-tree-nodes* 1000000
  "Maximum AST/CST node count visited by one tree helper call.")

(define-value-limit-condition tree-depth-limit-exceeded depth
    "Tree depth ~D exceeds maximum ~D"
  :reader-prefix tree-depth-limit)

(define-value-limit-condition tree-node-limit-exceeded count
    "Tree node count ~D exceeds maximum ~D"
  :reader-prefix tree-node-limit)

(define-condition tree-child-list-invalid (error)
  ((kind :initarg :kind :reader tree-child-list-invalid-kind))
  (:report (lambda (condition stream)
             (format stream "Tree child list is ~A"
                     (ecase (tree-child-list-invalid-kind condition)
                       (:circular "circular")
                       (:improper "improper"))))))

(defun %check-tree-depth-limit (depth)
  (when (> depth *maximum-tree-depth*)
    (error 'tree-depth-limit-exceeded
           :depth depth
           :limit *maximum-tree-depth*)))

(defun %make-tree-resource-state ()
  (list 0))

(defun %check-tree-node-limit (state)
  (let ((count (incf (car state))))
    (when (> count *maximum-tree-nodes*)
      (error 'tree-node-limit-exceeded
             :count count
             :limit *maximum-tree-nodes*))))

(defmacro %do-tree-children ((child children &optional result) &body body)
  (let ((tail (gensym "TAIL"))
        (seen (gensym "SEEN")))
    `(loop with ,seen = (make-hash-table :test 'eq)
           for ,tail = ,children then (cdr ,tail)
           while ,tail
           do (cond
                ((consp ,tail)
                 (when (gethash ,tail ,seen)
                   (error 'tree-child-list-invalid :kind :circular))
                 (setf (gethash ,tail ,seen) t)
                 (let ((,child (car ,tail)))
                   ,@body))
                (t
                 (error 'tree-child-list-invalid :kind :improper)))
           finally (return ,result))))

(defun %tree-children-list (children)
  "Same cycle-detecting walk as %DO-TREE-CHILDREN, collecting each child into a
fresh list -- the two functional (non-macro) forms of that walk,
%TREE-CHILDREN-LIST (collects) and %VALIDATE-TREE-CHILD-LIST (validates only),
differ from each other and from %DO-TREE-CHILDREN's macro-generated call sites
only in what happens per child, never in the walk itself."
  (let ((items '()))
    (%do-tree-children (child children (nreverse items))
      (push child items))))

(defun %validate-tree-child-list (children)
  (%do-tree-children (child children)
    (declare (ignore child))))

(defun %tree-node-children (node children-fn)
  (%tree-children-list (funcall children-fn node)))

(defun %span->plist (span)
  (when span
    (list :source (span-source span)
          :start (span-start span)
          :end (span-end span)
          :start-line (span-start-line span)
          :start-column (span-start-column span)
          :end-line (span-end-line span)
          :end-column (span-end-column span))))

(defun %tree-node->sexp (node type-fn value-fn children-fn span-fn data-fn
                         &key include-span include-data)
  (let ((state (%make-tree-resource-state)))
    (labels ((serialize (current depth)
               (%check-tree-depth-limit depth)
               (%check-tree-node-limit state)
               (append (list :type (funcall type-fn current)
                             :value (funcall value-fn current)
                             :children (mapcar (lambda (child)
                                                  (serialize child (1+ depth)))
                                                (%tree-node-children current children-fn)))
                       (when include-span
                         (list :span (%span->plist (funcall span-fn current))))
                       (when include-data
                         (list :data (funcall data-fn current))))))
      (serialize node 1))))

(defun %tree-walk (node function children-fn &optional (order :pre) (depth 1)
                                                (state (%make-tree-resource-state)))
  "Visit NODE and every descendant, calling FUNCTION on each for its side effects;
return NODE. ORDER is :PRE (NODE before its children, the default) or :POST
(children before NODE)."
  (%check-tree-depth-limit depth)
  (%check-tree-node-limit state)
  (ecase order
    (:pre
     (funcall function node)
     (%do-tree-children (child (funcall children-fn node))
       (%tree-walk child function children-fn :pre (1+ depth) state)))
    (:post
     (%do-tree-children (child (funcall children-fn node))
       (%tree-walk child function children-fn :post (1+ depth) state))
     (funcall function node)))
  node)

(defun %tree-reduce (node function initial-value children-fn &optional (order :pre))
  "Fold FUNCTION over NODE and its descendants in ORDER (:PRE by default), from
INITIAL-VALUE: each visited node updates the accumulator to
(FUNCALL FUNCTION accumulator node). Returns the final accumulator."
  (let ((accumulator initial-value))
    (%tree-walk node
                (lambda (current)
                  (setf accumulator (funcall function accumulator current)))
                children-fn
                order)
    accumulator))

(defun %tree-equal (left right type-fn value-fn children-fn span-fn data-fn
                    &key (test #'equal) include-span include-data)
  "Structural equality of two trees: equal TYPE (compared with EQL), equal VALUE
(with TEST), and the same number of children compared pairwise. Span and data are
ignored unless INCLUDE-SPAN / INCLUDE-DATA request them (spans compare by their
START/END offsets, data with TEST)."
  (let ((state (%make-tree-resource-state)))
    (labels ((span-equal (a b)
               (or (eq a b)
                   (and a b
                        (eql (span-start a) (span-start b))
                        (eql (span-end a) (span-end b)))))
             (children-equal-p (a b depth)
               ;; Named separately from NODE-EQUAL's checklist below so that
               ;; checklist reads as "type, value, span?, data?, children"
               ;; without this pairwise-walk's mechanics interrupting it.
               (let ((left-children (funcall children-fn a))
                     (right-children (funcall children-fn b)))
                 (%validate-tree-child-list left-children)
                 (%validate-tree-child-list right-children)
                 (loop with left-tail = left-children
                       with right-tail = right-children
                       do (cond
                            ((and (null left-tail) (null right-tail))
                             (return t))
                            ((or (null left-tail) (null right-tail))
                             (return nil))
                            ((not (node-equal (car left-tail)
                                              (car right-tail)
                                              (1+ depth)))
                             (return nil))
                            (t
                             (setf left-tail (cdr left-tail)
                                   right-tail (cdr right-tail)))))))
             (node-equal (a b depth)
               (%check-tree-depth-limit depth)
               (%check-tree-node-limit state)
               (and (eql (funcall type-fn a) (funcall type-fn b))
                    (funcall test (funcall value-fn a) (funcall value-fn b))
                    (or (not include-span)
                        (span-equal (funcall span-fn a) (funcall span-fn b)))
                    (or (not include-data)
                        (funcall test (funcall data-fn a) (funcall data-fn b)))
                    (children-equal-p a b depth))))
      (node-equal left right 1))))

(defun %tree-find (node predicate children-fn &optional (depth 1)
                                                (state (%make-tree-resource-state)))
  "Return the first node (pre-order, NODE first) for which PREDICATE is true, or
NIL when no node matches."
  (%check-tree-depth-limit depth)
  (%check-tree-node-limit state)
  (if (funcall predicate node)
      node
      (let ((children (funcall children-fn node)))
        (%validate-tree-child-list children)
        (dolist (child children nil)
          (let ((found (%tree-find child predicate children-fn (1+ depth) state)))
            (when found
              (return found)))))))

(defun %tree-collect (node predicate children-fn)
  "Return, in pre-order, the list of every node satisfying PREDICATE."
  (let ((matches '()))
    (%tree-walk node
                (lambda (current)
                  (when (funcall predicate current)
                    (push current matches)))
                children-fn)
    (nreverse matches)))

(defun %tree-count (node predicate children-fn)
  "Return the number of nodes satisfying PREDICATE."
  (let ((count 0))
    (%tree-walk node
                (lambda (current)
                  (when (funcall predicate current)
                    (incf count)))
                children-fn)
    count))

(defun %tree-depth (node children-fn)
  "Return the maximum depth of the tree rooted at NODE (a leaf has depth 1)."
  (let ((state (%make-tree-resource-state)))
    (labels ((measure (current depth)
               (%check-tree-depth-limit depth)
               (%check-tree-node-limit state)
               (let ((maximum-child-depth 0))
                 (%do-tree-children (child (funcall children-fn current))
                   (setf maximum-child-depth
                         (max maximum-child-depth
                              (measure child (1+ depth)))))
                 (if (zerop maximum-child-depth)
                     1
                     (1+ maximum-child-depth)))))
      (measure node 1))))

(defun %tree-map (node function children-fn rebuild-fn &optional (depth 1)
                                                       (state (%make-tree-resource-state)))
  "Rebuild the tree bottom-up: map each child first, then call FUNCTION on a copy
of the node whose children are the mapped children, returning FUNCTION's result.
REBUILD-FN takes (node mapped-children) and returns a node copy with those
children."
  (%check-tree-depth-limit depth)
  (%check-tree-node-limit state)
  (let ((mapped-children (mapcar (lambda (child)
                                   (%tree-map child function children-fn rebuild-fn
                                              (1+ depth) state))
                                 (%tree-node-children node children-fn))))
    (funcall function (funcall rebuild-fn node mapped-children))))

(defun %tree-node-label (node type-fn value-fn)
  "Render NODE as \"TYPE VALUE\" (via ~S, not ~A, so a keyword type keeps its
colon and a string value keeps its quotes -- the render stays
readable/faithful), or just \"TYPE\" when VALUE is NIL. Shared by
%TREE->STRING and %TREE->DOT, which differ only in whether the result is
written directly to a stream or escaped for a DOT label first."
  (let ((value (funcall value-fn node)))
    (if value
        (format nil "~S ~S" (funcall type-fn node) value)
        (format nil "~S" (funcall type-fn node)))))

(defun %tree->string (node type-fn value-fn children-fn &optional (indent 0))
  "Render NODE and its descendants as a human-readable indented tree, one node per
line: TYPE, followed by VALUE (via ~S, so strings and keywords print readably)
when the value is non-NIL, with each level indented two spaces further. INDENT is
the starting depth. No trailing newline is emitted."
  (let ((state (%make-tree-resource-state)))
    (with-output-to-string (out)
      (labels ((emit (current indent-level depth)
                 (%check-tree-depth-limit depth)
                 (%check-tree-node-limit state)
                 (dotimes (level indent-level)
                   (declare (ignorable level))
                   (write-string "  " out))
                 (write-string (%tree-node-label current type-fn value-fn) out)
                 (%do-tree-children (child (funcall children-fn current))
                   (terpri out)
                   (emit child (1+ indent-level) (1+ depth)))))
        (emit node indent 1)))))

(defun %dot-escape (string)
  "Escape STRING for use inside a Graphviz DOT double-quoted label."
  (with-output-to-string (out)
    (loop for char across string
          do (case char
               (#\" (write-string "\\\"" out))
               (#\\ (write-string "\\\\" out))
               (#\Newline (write-string "\\n" out))
               (t (write-char char out))))))

(defun %tree->dot (node type-fn value-fn children-fn &optional (graph-name "tree"))
  "Render NODE and its descendants as a Graphviz DOT digraph named GRAPH-NAME.
Each node becomes `nN [label=\"TYPE VALUE\"]` (VALUE included when non-NIL, escaped
for DOT) and each parent/child link an `nN -> nM` edge. Node ids are assigned in
pre-order; the result is a complete `digraph { ... }` document."
  (let ((counter -1)
        (state (%make-tree-resource-state)))
    (with-output-to-string (out)
      (format out "digraph ~A {~%" graph-name)
      (labels ((label-of (current)
                 (%tree-node-label current type-fn value-fn))
               (emit (current depth)
                 (%check-tree-depth-limit depth)
                 (%check-tree-node-limit state)
                 (let ((id (incf counter)))
                   (format out "  n~D [label=\"~A\"];~%" id (%dot-escape (label-of current)))
                   (%do-tree-children (child (funcall children-fn current))
                     (let ((child-id (emit child (1+ depth))))
                       (format out "  n~D -> n~D;~%" id child-id)))
                   id)))
        (emit node 1))
      (format out "}~%"))))

(defun %plist->span (plist)
  "Reconstruct a SPAN from the plist %SPAN->PLIST produced (as embedded by
->SEXP with :INCLUDE-SPAN). Missing keys fall back to a zero-length span at
line/column 1."
  (when plist
    (destructuring-bind (&key source start end start-line start-column
                              end-line end-column)
        plist
      (make-span :source source
                 :start (or start 0)
                 :end (or end 0)
                 :start-line (or start-line 1)
                 :start-column (or start-column 1)
                 :end-line (or end-line 1)
                 :end-column (or end-column 1)))))

(defun %sexp->tree (sexp constructor &optional (depth 1)
                                      (state (%make-tree-resource-state)))
  "Rebuild a tree node from the plist SEXP (as produced by ->SEXP), recursing into
:CHILDREN and reconstructing an embedded :SPAN. CONSTRUCTOR is MAKE-AST-NODE /
MAKE-CST-NODE (a &key TYPE VALUE CHILDREN SPAN DATA function)."
  (%check-tree-depth-limit depth)
  (%check-tree-node-limit state)
  (destructuring-bind (&key type value children span data) sexp
    (funcall constructor
             :type type
             :value value
             :children (mapcar (lambda (child)
                                  (%sexp->tree child constructor (1+ depth) state))
                                (%tree-children-list children))
             :span (%plist->span span)
             :data data)))
