(in-package :cl-parser-kit)

(defun %tree-node-constructor-symbol (name)
  (intern (format nil "MAKE-~A"
                  (string-upcase (symbol-name name)))
          (symbol-package name)))

(defun %tree-node-accessor-symbol (name slot)
  (intern (format nil "~A-~A"
                  (string-upcase (symbol-name name))
                  (string-upcase (symbol-name slot)))
          (symbol-package name)))

(defun %tree-node-sexp-symbol (name)
  (intern (format nil "~A->SEXP"
                  (string-upcase (symbol-name name)))
          (symbol-package name)))

(defun %tree-node-symbol (name control-string)
  "Intern a symbol built by substituting NAME's upcased name into CONTROL-STRING
(a single ~A FORMAT template), in NAME's own package. Shared by every generated
member of a tree-node family's API -- e.g. \"~A-WALK\" for AST-NODE-WALK,
\"TOKEN->~A\" for TOKEN->AST-NODE."
  (intern (format nil control-string (string-upcase (symbol-name name)))
          (symbol-package name)))

(defmacro define-tree-node-family (name &key (article "a") (kind-noun "tree")
                                             (short-name (string-downcase (symbol-name name))))
  "Define NAME (e.g. AST-NODE, CST-NODE) as a located tree-node struct together
with its full construction/traversal/rendering API: NAME->SEXP, SEXP->NAME,
TOKEN->NAME, NAME-OF, NAME-WALK, NAME-REDUCE, NAME-MAP, NAME-EQUAL, NAME-FIND,
NAME-COLLECT, NAME-COUNT, NAME-DEPTH, NAME->STRING, and NAME->DOT.

Every generated function is a thin, family-specific binding of the generic
%TREE-* traversal logic earlier in this file to NAME's own constructor and
accessors -- a family contributes no traversal logic of its own, only its
shape. ARTICLE (\"a\" / \"an\"), KIND-NOUN (e.g. \"parse tree\"), and
SHORT-NAME (the default Graphviz digraph name) are the family-specific data
that fill in the generated docstrings and defaults."
  (let* ((constructor (%tree-node-constructor-symbol name))
         (type-accessor (%tree-node-accessor-symbol name 'type))
         (value-accessor (%tree-node-accessor-symbol name 'value))
         (children-accessor (%tree-node-accessor-symbol name 'children))
         (span-accessor (%tree-node-accessor-symbol name 'span))
         (data-accessor (%tree-node-accessor-symbol name 'data))
         (sexp-name (%tree-node-sexp-symbol name))
         (walk-name (%tree-node-symbol name "~A-WALK"))
         (reduce-name (%tree-node-symbol name "~A-REDUCE"))
         (token->name (%tree-node-symbol name "TOKEN->~A"))
         (of-name (%tree-node-symbol name "~A-OF"))
         (sexp->name (%tree-node-symbol name "SEXP->~A"))
         (->string-name (%tree-node-symbol name "~A->STRING"))
         (->dot-name (%tree-node-symbol name "~A->DOT"))
         (equal-name (%tree-node-symbol name "~A-EQUAL"))
         (find-name (%tree-node-symbol name "~A-FIND"))
         (collect-name (%tree-node-symbol name "~A-COLLECT"))
         (count-name (%tree-node-symbol name "~A-COUNT"))
         (depth-name (%tree-node-symbol name "~A-DEPTH"))
         (map-name (%tree-node-symbol name "~A-MAP"))
         (upper-name (string-upcase (symbol-name name))))
    `(progn
       (defstruct (,name (:constructor ,constructor (&key type value children span data)))
         ,(format nil "One node of the ~A this library builds from parsed input: ~
a TYPE naming what it is, an optional leaf VALUE, a list of CHILDREN, the SPAN ~
it covers in the source, and DATA for caller-specific payload the library ~
never interprets.~2%Nothing distinguishes a leaf from an interior node ~
structurally -- a leaf is simply a node with no CHILDREN -- so every ~A helper ~
works uniformly at any depth. Build one with ~A, TOKEN->~A, or SEXP->~A."
                  kind-noun upper-name constructor upper-name upper-name)
         type
         value
         children
         span
         data)

       (defun ,sexp-name (node &key include-span include-data)
         ,(format nil "Convert NODE and its descendants into a nested plist ~
s-expression: (:TYPE type :VALUE value :CHILDREN (...)), with :SPAN and :DATA ~
included only when INCLUDE-SPAN or INCLUDE-DATA is true.~2%The stable, ~
printable, EQUAL-comparable form of ~A ~A -- what tests, examples, and REPL ~
inspection compare against, since two structurally identical structs are not ~
EQUAL. SEXP->~A is the inverse."
                  article upper-name upper-name)
         (%tree-node->sexp node
                           #',type-accessor #',value-accessor #',children-accessor
                           #',span-accessor #',data-accessor
                           :include-span include-span
                           :include-data include-data))

       (defun ,walk-name (node function &key (order :pre))
         ,(format nil "Visit NODE and every descendant, calling FUNCTION on each for its ~
side effects; return NODE. ORDER is :PRE (NODE before its children, the ~
default) or :POST (children before NODE).")
         (%tree-walk node function #',children-accessor order))

       (defun ,reduce-name (node function initial-value &key (order :pre))
         ,(format nil "Fold FUNCTION over NODE and its descendants in ORDER (:PRE by ~
default) from INITIAL-VALUE, updating the accumulator to (FUNCALL FUNCTION ~
accumulator node) at each node; return the final accumulator.")
         (%tree-reduce node function initial-value #',children-accessor order))

       (defun ,token->name (token type &key (value-function #'token-text) data)
         ,(format nil "Build a leaf ~A of TYPE from TOKEN: its VALUE is (FUNCALL ~
VALUE-FUNCTION TOKEN) -- TOKEN-TEXT by default, pass #'TOKEN-VALUE for the ~
decoded payload -- and its SPAN is the token's source span. Removes the ~
boilerplate of pulling text and span out of a token by hand when building ~
located leaf nodes." upper-name)
         (,constructor :type type
                       :value (funcall value-function token)
                       :span (%token-effective-span token)
                       :data data))

       (defun ,of-name (type parser &key as-children data)
         ,(format nil "Run PARSER and wrap its result into ~A ~A of TYPE whose SPAN ~
covers the tokens PARSER consumed. By default the value goes in the node's ~
VALUE; with AS-CHILDREN true it becomes the node's CHILDREN (a non-list value ~
is wrapped in a one-element list). The idiomatic way to build a located node ~
from a grammar rule without threading spans by hand." article upper-name)
         (spanning (lambda (value span)
                     (if as-children
                         (,constructor :type type
                                       :children (if (listp value) value (list value))
                                       :span span
                                       :data data)
                         (,constructor :type type :value value :span span :data data)))
                   parser))

       (defun ,sexp->name (sexp)
         ,(format nil "Reconstruct ~A ~A tree from the plist ~(~A~) produced, ~
recursing into :CHILDREN and rebuilding an embedded :SPAN (from a ~
:INCLUDE-SPAN render). Round-trips: (~(~A~) node (~(~A~) (~(~A~) node))) is ~
true." article upper-name sexp-name equal-name sexp->name sexp-name)
         (%sexp->tree sexp #',constructor))

       (defun ,->string-name (node &key (indent 0))
         ,(format nil "Render NODE as a human-readable indented tree (one node per line: ~
TYPE, then VALUE when non-NIL), for debugging and REPL inspection. INDENT sets ~
the starting depth. Contrast ~(~A~), which yields a machine-readable plist."
                  sexp-name)
         (%tree->string node #',type-accessor #',value-accessor #',children-accessor indent))

       (defun ,->dot-name (node &key (graph-name ,short-name))
         ,(format nil "Render NODE as a Graphviz DOT digraph named GRAPH-NAME (a valid DOT ~
id), for visualizing ~A ~A with `dot`. Each node is labelled with its TYPE and, ~
when non-NIL, its VALUE." article kind-noun)
         (%tree->dot node #',type-accessor #',value-accessor #',children-accessor graph-name))

       (defun ,equal-name (left right &key (test #'equal) include-span include-data)
         ,(format nil "Return true when LEFT and RIGHT are structurally equal: equal TYPE ~
(EQL), equal VALUE (TEST), and children equal pairwise. Span and data are ~
compared only when INCLUDE-SPAN / INCLUDE-DATA are set.")
         (%tree-equal left right
                     #',type-accessor #',value-accessor #',children-accessor
                     #',span-accessor #',data-accessor
                     :test test :include-span include-span :include-data include-data))

       (defun ,find-name (node predicate)
         "Return the first node (pre-order, NODE first) satisfying PREDICATE, or NIL
when no node matches."
         (%tree-find node predicate #',children-accessor))

       (defun ,collect-name (node predicate)
         "Return, in pre-order, the list of every node satisfying PREDICATE."
         (%tree-collect node predicate #',children-accessor))

       (defun ,count-name (node &optional (predicate (constantly t)))
         "Return the number of nodes satisfying PREDICATE (every node by default)."
         (%tree-count node predicate #',children-accessor))

       (defun ,depth-name (node)
         "Return the maximum depth of the tree rooted at NODE (a leaf has depth 1)."
         (%tree-depth node #',children-accessor))

       (defun ,map-name (node function)
         ,(format nil "Rebuild the tree bottom-up, replacing each node with the result of ~
calling FUNCTION on a copy whose children have already been mapped. The ~
original NODE is left untouched.")
         (%tree-map node function #',children-accessor
                   (lambda (original mapped-children)
                     (,constructor :type (,type-accessor original)
                                   :value (,value-accessor original)
                                   :children mapped-children
                                   :span (,span-accessor original)
                                   :data (,data-accessor original))))))))
