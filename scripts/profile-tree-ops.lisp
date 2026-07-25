(require :asdf)

(let ((root (uiop:ensure-directory-pathname
             (truename (or (second sb-ext:*posix-argv*) (uiop:getcwd))))))
  (asdf:load-asd (merge-pathnames "cl-parser-kit.asd" root))
  (asdf:load-system :cl-parser-kit :verbose nil :print nil))

(defun bench (label thunk iterations)
  (sb-ext:gc :full t)
  (let ((bytes-before (sb-ext:get-bytes-consed))
        (time-before (get-internal-real-time)))
    (dotimes (i iterations) (funcall thunk))
    (let ((elapsed (/ (- (get-internal-real-time) time-before)
                      (float internal-time-units-per-second 1.0d0)))
          (bytes (- (sb-ext:get-bytes-consed) bytes-before)))
      (format t "~A~40Telapsed=~,6Fs~15Tconsed=~:D bytes~%" label elapsed bytes))))

;; A binary-ish tree of depth D (each internal node has 2 children), so most
;; nodes are leaves (children = NIL) -- the realistic shape %DO-TREE-CHILDREN's
;; fast path targets.
(defun make-binary-ast (depth)
  (if (zerop depth)
      (cl-parser-kit:make-ast-node :type :leaf :value depth)
      (cl-parser-kit:make-ast-node :type :branch
                                   :children (list (make-binary-ast (1- depth))
                                                   (make-binary-ast (1- depth))))))

(let* ((tree (make-binary-ast 14)) (iterations 30))
  (bench "ast-node-walk" (lambda () (cl-parser-kit:ast-node-walk tree (lambda (n) (declare (ignore n)) nil))) iterations)
  (bench "ast-node-equal" (lambda () (cl-parser-kit:ast-node-equal tree tree)) iterations)
  (bench "ast-node->sexp" (lambda () (cl-parser-kit:ast-node->sexp tree)) iterations)
  (bench "ast-node->string" (lambda () (cl-parser-kit:ast-node->string tree)) iterations)
  (bench "ast-node-count" (lambda () (cl-parser-kit:ast-node-count tree)) iterations))
