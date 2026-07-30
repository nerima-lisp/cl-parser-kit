(in-package :cl-parser-kit/test)

(defun %sample-ast ()
  (make-ast-node
   :type :root :value :top
   :children (list (make-ast-node :type :leaf :value 1)
                   (make-ast-node :type :branch :value :mid
                                  :children (list (make-ast-node :type :leaf :value 2))))))

(defun %deep-ast (depth)
  (loop repeat (1- depth)
        with node = (make-ast-node :type :leaf)
        do (setf node (make-ast-node :type :branch :children (list node)))
        finally (return node)))

(defun %wide-ast (child-count)
  (make-ast-node :type :root
                 :children (loop repeat child-count
                                 collect (make-ast-node :type :leaf))))

(defun %gen-branching-ast (&key (max-depth 4))
  "A CL-WEAVE property generator for AST-NODE trees with genuinely ragged
branching -- unlike %DEEP-AST (a single linear spine) and %WIDE-AST (one flat
fan-out), GEN-RECURSIVE's per-level coin flip between the leaf and branch
generators produces shapes with a mix of both at every depth, which is what
actually exercises %TREE-WALK/%TREE-REDUCE/%TREE-EQUAL's recursion over
multiple, unevenly-deep children."
  (gen-recursive
   (gen-map (lambda (value) (make-ast-node :type :leaf :value value))
            (gen-member '(:leaf-a :leaf-b)))
   (lambda (self)
     (gen-map (lambda (children) (make-ast-node :type :branch :children children))
              (gen-list self :min-length 1 :max-length 3)))
   :max-depth max-depth))

(defun %cyclic-child-ast ()
  (let* ((child (make-ast-node :type :leaf))
         (children (list child))
         (root (make-ast-node :type :root :children children)))
    (setf (cdr children) children)
    root))

(defun %improper-child-ast ()
  (make-ast-node :type :root
                 :children (cons (make-ast-node :type :leaf) :not-a-list)))

(it-sequential "ast-node-walk-visits-preorder-test"
  (let ((types '()))
    (let ((returned (ast-node-walk (%sample-ast)
                                   (lambda (node)
                                     (push (ast-node-type node) types)))))
      (expect (ast-node-type returned) :to-equal :root)
      (expect (nreverse types) :to-equal '(:root :leaf :branch :leaf)))))

(it-sequential "ast-node-find-returns-first-match-test"
  (let ((found (ast-node-find (%sample-ast)
                              (lambda (node)
                                (eql (ast-node-type node) :leaf)))))
    (expect (ast-node-value found) :to-equal 1))
  (let ((missing (ast-node-find (%sample-ast)
                                (lambda (node)
                                  (eql (ast-node-type node) :nonexistent)))))
    (expect missing :to-be-falsy)))

(it-sequential "ast-node-map-rebuilds-without-mutating-original-test"
  (let* ((original (%sample-ast))
         (mapped (ast-node-map original
                               (lambda (node)
                                 (when (numberp (ast-node-value node))
                                   (setf (ast-node-value node)
                                         (* 10 (ast-node-value node))))
                                 node))))
    ;; mapped leaves are scaled ...
    (expect (ast-node-value (first (ast-node-children mapped))) :to-equal 10)
    (expect (ast-node-value (first (ast-node-children
                                    (second (ast-node-children mapped)))))
            :to-equal 20)
    ;; ... and the original tree is untouched
    (expect (ast-node-value (first (ast-node-children original))) :to-equal 1)))

(it-sequential "ast-node-collect-returns-all-matches-test"
  (let ((leaves (ast-node-collect (%sample-ast)
                                  (lambda (node)
                                    (eql (ast-node-type node) :leaf)))))
    (expect (mapcar #'ast-node-value leaves) :to-equal '(1 2))))

(it-sequential "ast-node-count-counts-nodes-test"
  (expect (ast-node-count (%sample-ast)) :to-equal 4)
  (expect (ast-node-count (%sample-ast)
                          (lambda (node) (eql (ast-node-type node) :leaf)))
          :to-equal 2))

(it-sequential "ast-node-depth-measures-deepest-path-test"
  (expect (ast-node-depth (%sample-ast)) :to-equal 3)
  (expect (ast-node-depth (make-ast-node :type :lone :value 0)) :to-equal 1))

(it-sequential "tree-helpers-enforce-depth-limit-test"
  (let ((*maximum-tree-depth* 3)
        (deep (%deep-ast 4)))
    (expect (lambda () (ast-node-depth deep)) :to-throw 'tree-depth-limit-exceeded)
    (expect (lambda () (ast-node-walk deep (lambda (node) (declare (ignore node)))))
            :to-throw 'tree-depth-limit-exceeded)
    (expect (lambda () (ast-node->sexp deep)) :to-throw 'tree-depth-limit-exceeded)
    (expect (lambda () (ast-node->string deep)) :to-throw 'tree-depth-limit-exceeded)
    (expect (lambda () (ast-node->dot deep)) :to-throw 'tree-depth-limit-exceeded)
    (expect (lambda () (ast-node-map deep #'identity))
            :to-throw 'tree-depth-limit-exceeded)
    (expect (lambda () (ast-node-equal deep deep))
            :to-throw 'tree-depth-limit-exceeded)
    (expect (lambda () (sexp->ast-node '(:type :a :children
                                         ((:type :b :children
                                           ((:type :c :children
                                             ((:type :d)))))))))
            :to-throw 'tree-depth-limit-exceeded)))

(it-sequential "tree-helpers-enforce-node-limit-test"
  (let ((*maximum-tree-nodes* 3)
        (tree (%wide-ast 3))
        (sexp '(:type :root :value nil :children
                ((:type :leaf :value nil :children ())
                 (:type :leaf :value nil :children ())
                 (:type :leaf :value nil :children ())))))
    (dolist (thunk (list (lambda () (ast-node-count tree))
                         (lambda () (ast-node-walk tree
                                                   (lambda (node)
                                                     (declare (ignore node)))))
                         (lambda () (ast-node->sexp tree))
                         (lambda () (ast-node->string tree))
                         (lambda () (ast-node->dot tree))
                         (lambda () (ast-node-map tree #'identity))
                         (lambda () (ast-node-equal tree tree))))
      (expect thunk :to-throw 'tree-node-limit-exceeded))
    (expect (lambda () (sexp->ast-node sexp))
            :to-throw 'tree-node-limit-exceeded)))

(it-sequential "tree-helpers-reject-circular-child-list-test"
  (let ((tree (%cyclic-child-ast)))
    (dolist (thunk (list (lambda () (ast-node-count tree))
                         (lambda () (ast-node-walk tree
                                                   (lambda (node)
                                                     (declare (ignore node)))))
                         (lambda () (ast-node-find tree
                                                   (lambda (node)
                                                     (declare (ignore node))
                                                     nil)))
                         (lambda () (ast-node-depth tree))
                         (lambda () (ast-node->sexp tree))
                         (lambda () (ast-node->string tree))
                         (lambda () (ast-node->dot tree))
                         (lambda () (ast-node-map tree #'identity))
                         (lambda () (ast-node-equal tree tree))))
      (expect thunk :to-throw 'tree-child-list-invalid))))

(it-sequential "tree-helpers-reject-improper-child-list-test"
  (let ((tree (%improper-child-ast)))
    (dolist (thunk (list (lambda () (ast-node-count tree))
                         (lambda () (ast-node-walk tree
                                                   (lambda (node)
                                                     (declare (ignore node)))))
                         (lambda () (ast-node-find tree
                                                   (lambda (node)
                                                     (declare (ignore node))
                                                     nil)))
                         (lambda () (ast-node-depth tree))
                         (lambda () (ast-node->sexp tree))
                         (lambda () (ast-node->string tree))
                         (lambda () (ast-node->dot tree))
                         (lambda () (ast-node-map tree #'identity))
                         (lambda () (ast-node-equal tree tree))))
      (expect thunk :to-throw 'tree-child-list-invalid))))

(it-sequential "sexp->ast-node-rejects-circular-children-list-test"
  (let ((children (list '(:type :leaf))))
    (setf (cdr children) children)
    (expect (lambda () (sexp->ast-node (list :type :root :children children)))
            :to-throw 'tree-child-list-invalid)))

(it-sequential "ast-node-walk-visits-postorder-test"
  (let ((types '()))
    (ast-node-walk (%sample-ast)
                   (lambda (node) (push (ast-node-type node) types))
                   :order :post)
    ;; Children before their parent: leaf, (leaf, branch), root.
    (expect (nreverse types) :to-equal '(:leaf :leaf :branch :root))))

(it-sequential "ast-node-reduce-folds-over-nodes-test"
  ;; Sum the numeric leaf values; non-numbers contribute 0.
  (let ((sum (ast-node-reduce (%sample-ast)
                              (lambda (acc node)
                                (+ acc (if (numberp (ast-node-value node))
                                           (ast-node-value node)
                                           0)))
                              0)))
    (expect sum :to-equal 3))
  ;; Node count via reduce matches ast-node-count.
  (expect (ast-node-reduce (%sample-ast)
                           (lambda (acc node) (declare (ignore node)) (1+ acc))
                           0)
          :to-equal 4))

(it-sequential "ast-node-equal-compares-structure-test"
  (expect (ast-node-equal (%sample-ast) (%sample-ast)) :to-be-truthy)
  ;; Differing value breaks equality.
  (let ((other (make-ast-node
                :type :root :value :top
                :children (list (make-ast-node :type :leaf :value 99)
                                (make-ast-node :type :branch :value :mid
                                               :children (list (make-ast-node :type :leaf :value 2)))))))
    (expect (ast-node-equal (%sample-ast) other) :to-be-falsy))
  ;; Differing child count breaks equality.
  (expect (ast-node-equal (make-ast-node :type :n :value 1)
                          (make-ast-node :type :n :value 1
                                         :children (list (make-ast-node :type :c :value 2))))
          :to-be-falsy))

(it-sequential "ast-node-equal-can-include-span-test"
  (let ((a (make-ast-node :type :n :value 1 :span (make-span :start 0 :end 3)))
        (b (make-ast-node :type :n :value 1 :span (make-span :start 0 :end 5))))
    (expect (ast-node-equal a b) :to-be-truthy)
    (expect (ast-node-equal a b :include-span t) :to-be-falsy)))

(it-sequential "ast-node-equal-with-include-span-detects-a-differing-start-test"
  ;; The sibling test above only ever varies END, so it never exercises
  ;; SPAN-EQUAL's START comparison specifically returning false; this pins
  ;; matching ENDs and differing STARTs to isolate that branch.
  (let ((a (make-ast-node :type :n :value 1 :span (make-span :start 0 :end 5)))
        (b (make-ast-node :type :n :value 1 :span (make-span :start 2 :end 5))))
    (expect (ast-node-equal a b :include-span t) :to-be-falsy)))

(it-sequential "cst-node-reduce-and-equal-are-provided-too-test"
  (let ((root (make-cst-node
               :type :root :value nil
               :children (list (make-cst-node :type :token :value "x")
                               (make-cst-node :type :token :value "y")))))
    (expect (cst-node-reduce root (lambda (acc n) (declare (ignore n)) (1+ acc)) 0)
            :to-equal 3)
    (expect (cst-node-equal root root) :to-be-truthy)))

(it-sequential "cst-node-of-wraps-parser-value-with-span-test"
  (with-combinator-tokens (tokens '((:type :id :text "x" :start 0 :end 1)))
    (let ((parser (cst-node-of :name (type-token-text :id))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect (cst-node-type value) :to-equal :name)
        (expect (cst-node-value value) :to-equal "x")
        (expect (cst-node-span value) :to-be-truthy)))))

(it-sequential "cst-node-of-as-children-collects-into-children-test"
  (with-combinator-tokens (tokens '((:type :a :text "a") (:type :b :text "b")))
    (let ((parser (cst-node-of :pair
                               (seq-map (lambda (a b)
                                          (list (token->cst-node a :a) (token->cst-node b :b)))
                                        (type-token :a) (type-token :b))
                               :as-children t)))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect (cst-node-type value) :to-equal :pair)
        (expect (length (cst-node-children value)) :to-equal 2)
        (expect (cst-node-value value) :to-be-falsy)))))

(it-sequential "cst-node-map-rebuilds-without-mutating-original-test"
  (let* ((original (make-cst-node
                    :type :root :value nil
                    :children (list (make-cst-node :type :token :value 1)
                                    (make-cst-node :type :token :value 2))))
         (mapped (cst-node-map original
                               (lambda (node)
                                 (when (numberp (cst-node-value node))
                                   (setf (cst-node-value node)
                                         (* 10 (cst-node-value node))))
                                 node))))
    (expect (cst-node-value (first (cst-node-children mapped))) :to-equal 10)
    (expect (cst-node-value (second (cst-node-children mapped))) :to-equal 20)
    (expect (cst-node-value (first (cst-node-children original))) :to-equal 1)))

(it-sequential "token->ast-node-builds-leaf-from-token-test"
  (let* ((token (make-token :type :number :text "42" :value 42 :start 0 :end 2))
         (node (token->ast-node token :num)))
    (expect (ast-node-type node) :to-equal :num)
    (expect (ast-node-value node) :to-equal "42")           ; token-text by default
    (expect (ast-node-span node) :to-be-truthy))
  ;; :value-function selects the decoded payload instead of the text.
  (let* ((token (make-token :type :number :text "42" :value 42))
         (node (token->ast-node token :num :value-function #'token-value)))
    (expect (ast-node-value node) :to-equal 42)))

(it-sequential "ast-node-of-wraps-parser-value-with-span-test"
  (with-combinator-tokens (tokens '((:type :id :text "x" :start 0 :end 1)))
    (let ((parser (ast-node-of :name (type-token-text :id))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect (ast-node-type value) :to-equal :name)
        (expect (ast-node-value value) :to-equal "x")
        (expect (ast-node-span value) :to-be-truthy)))))

(it-sequential "ast-node-of-as-children-collects-into-children-test"
  (with-combinator-tokens (tokens '((:type :a :text "a") (:type :b :text "b")))
    (let ((parser (ast-node-of :pair
                               (seq-map (lambda (a b)
                                          (list (token->ast-node a :a) (token->ast-node b :b)))
                                        (type-token :a) (type-token :b))
                               :as-children t)))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect (ast-node-type value) :to-equal :pair)
        (expect (length (ast-node-children value)) :to-equal 2)
        (expect (ast-node-value value) :to-be-falsy)))))

(it-sequential "sexp->ast-node-round-trips-test"
  (let* ((original (%sample-ast))
         (rebuilt (sexp->ast-node (ast-node->sexp original))))
    (expect (ast-node-equal original rebuilt) :to-be-truthy))
  ;; Span survives the round trip when included in the sexp.
  (let* ((original (make-ast-node :type :n :value 1 :span (make-span :start 2 :end 5)))
         (rebuilt (sexp->ast-node (ast-node->sexp original :include-span t))))
    (expect (ast-node-equal original rebuilt :include-span t) :to-be-truthy)))

(it-sequential "sexp->ast-node-round-trips-every-span-field-test"
  ;; AST-NODE-EQUAL's :INCLUDE-SPAN comparison only checks START/END (per its
  ;; own documented contract), so the two tests above cannot catch %SPAN->PLIST
  ;; and %PLIST->SPAN silently drifting out of sync on SOURCE/*-LINE/*-COLUMN --
  ;; each hand-lists the same seven span fields independently. This checks
  ;; every field individually, with values distinct enough that transposing any
  ;; two would fail.
  (let* ((original (make-ast-node
                    :type :n :value 1
                    :span (make-span :source "src" :start 10 :end 20
                                     :start-line 3 :start-column 4
                                     :end-line 5 :end-column 6)))
         (rebuilt (sexp->ast-node (ast-node->sexp original :include-span t)))
         (span (ast-node-span rebuilt)))
    (expect (span-source span) :to-equal "src")
    (expect (span-start span) :to-equal 10)
    (expect (span-end span) :to-equal 20)
    (expect (span-start-line span) :to-equal 3)
    (expect (span-start-column span) :to-equal 4)
    (expect (span-end-line span) :to-equal 5)
    (expect (span-end-column span) :to-equal 6)))

(it-property "property-ast-node-sexp-round-trips-for-any-depth"
    ((depth (gen-integer :min 1 :max 50)))
  ;; SEXP->AST-NODE-ROUND-TRIPS-TEST above is one fixed example; this checks
  ;; the same law -- (AST-NODE-EQUAL node (SEXP->AST-NODE (AST-NODE->SEXP
  ;; node))) -- holds across a randomly generated range of linear depths.
  (let* ((original (%deep-ast depth))
         (rebuilt (sexp->ast-node (ast-node->sexp original))))
    (expect (ast-node-equal original rebuilt) :to-be-truthy)))

(it-property "property-ast-node-sexp-round-trips-for-any-child-count"
    ((child-count (gen-integer :min 0 :max 50)))
  (let* ((original (%wide-ast child-count))
         (rebuilt (sexp->ast-node (ast-node->sexp original))))
    (expect (ast-node-equal original rebuilt) :to-be-truthy)))

(it-property "property-ast-node-sexp-round-trips-for-any-branching-shape"
    ((tree (%gen-branching-ast)))
  ;; %DEEP-AST and %WIDE-AST above only ever generate a single spine or a
  ;; single flat fan-out -- every generated tree is either a path or a star,
  ;; never a shape with more than one child AND more than one level, which is
  ;; the case that actually exercises multiple children at multiple depths
  ;; together. GEN-RECURSIVE's per-level leaf/branch coin flip covers that gap.
  (let ((rebuilt (sexp->ast-node (ast-node->sexp tree))))
    (expect (ast-node-equal tree rebuilt) :to-be-truthy)))

(it-sequential "cst-node-construction-and-serialization-provided-too-test"
  (let* ((token (make-token :type :ident :text "y"))
         (leaf (token->cst-node token :identifier)))
    (expect (cst-node-value leaf) :to-equal "y"))
  (let* ((original (make-cst-node :type :root :value nil
                                  :children (list (make-cst-node :type :token :value "x"))))
         (rebuilt (sexp->cst-node (cst-node->sexp original))))
    (expect (cst-node-equal original rebuilt) :to-be-truthy)))

(it-sequential "ast-node->string-renders-indented-tree-test"
  (let ((rendered (ast-node->string (%sample-ast))))
    ;; Root at column 0, its children indented two spaces, the grandchild four.
    (expect (search ":ROOT :TOP" rendered) :to-be-truthy)
    (expect (search (format nil "~%  :LEAF 1") rendered) :to-be-truthy)
    (expect (search (format nil "~%  :BRANCH :MID") rendered) :to-be-truthy)
    (expect (search (format nil "~%    :LEAF 2") rendered) :to-be-truthy)
    ;; No trailing newline.
    (expect (char= (char rendered (1- (length rendered))) #\Newline) :to-be-falsy)))

(it-sequential "ast-node->string-omits-nil-value-test"
  (let ((rendered (ast-node->string (make-ast-node :type :bare :value nil))))
    (expect rendered :to-equal ":BARE")))

(it-sequential "ast-node->dot-renders-digraph-test"
  (let ((dot (ast-node->dot (%sample-ast) :graph-name "sample")))
    (expect (search "digraph sample {" dot) :to-be-truthy)
    (expect (search "n0 [label=\"" dot) :to-be-truthy)
    ;; root (n0) points at its first child (n1).
    (expect (search "n0 -> n1;" dot) :to-be-truthy)
    (expect (char= (char dot (1- (length dot))) #\Newline) :to-be-truthy)))

(it-sequential "ast-node->dot-escapes-label-test"
  ;; A value containing a double quote must be escaped, not left raw.
  (let ((dot (ast-node->dot (make-ast-node :type :str :value "a\"b"))))
    (expect (search "\\\"" dot) :to-be-truthy)))

(it-sequential "ast-node->dot-escapes-a-newline-in-the-label-test"
  ;; %DOT-ESCAPE's #\Newline case is distinct from its #\" and #\\ cases --
  ;; a raw newline would break DOT's one-line-per-label-attribute syntax.
  (let ((dot (ast-node->dot (make-ast-node :type :str
                                           :value (format nil "a~%b")))))
    (expect (search "\\n" dot) :to-be-truthy)))

(it-sequential "ast-node-equal-with-include-data-detects-a-difference-test"
  ;; Every other AST-NODE-EQUAL test above compares structure/value/span; none
  ;; passes :INCLUDE-DATA T, so the DATA comparison itself was unexercised.
  (let ((a (make-ast-node :type :n :value 1 :data :a))
        (b (make-ast-node :type :n :value 1 :data :b)))
    (expect (ast-node-equal a b) :to-be-truthy)
    (expect (ast-node-equal a b :include-data t) :to-be-falsy)
    (expect (ast-node-equal a a :include-data t) :to-be-truthy)))

(it-sequential "cst-node-rendering-is-provided-too-test"
  (let ((root (make-cst-node :type :root :value nil
                             :children (list (make-cst-node :type :token :value "x")))))
    (expect (search ":ROOT" (cst-node->string root)) :to-be-truthy)
    (expect (search "\"x\"" (cst-node->string root)) :to-be-truthy)
    (expect (search "digraph cst {" (cst-node->dot root)) :to-be-truthy)))

(it-sequential "cst-node-query-utilities-are-generated-too-test"
  (let ((root (make-cst-node
               :type :root :value nil
               :children (list (make-cst-node :type :token :value "x")
                               (make-cst-node :type :token :value "y")))))
    (expect (cst-node-count root) :to-equal 3)
    (expect (length (cst-node-collect root
                                      (lambda (n) (eql (cst-node-type n) :token))))
            :to-equal 2)
    (expect (cst-node-depth root) :to-equal 2)))

(it-sequential "cst-node-traversal-is-generated-too-test"
  (let ((root (make-cst-node
               :type :root :value nil
               :children (list (make-cst-node :type :token :value "x")
                               (make-cst-node :type :token :value "y")))))
    (let ((values '()))
      (cst-node-walk root (lambda (node) (push (cst-node-value node) values)))
      (expect (remove nil (nreverse values)) :to-equal '("x" "y")))
    (expect (cst-node-value (cst-node-find root
                                           (lambda (n)
                                             (equal (cst-node-value n) "y"))))
            :to-equal "y")))
