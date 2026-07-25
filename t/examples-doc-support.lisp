(in-package :cl-parser-kit/test)

(defun markdown-local-links (name)
  (let ((contents (doc-file-contents name))
        (links '()))
    (loop with position = 0
          for start = (search "](" contents :start2 position)
          while start
          do (let ((end (position #\) contents :start (+ start 2))))
               (unless end
                 (return))
               (let ((target (subseq contents (+ start 2) end)))
                 (unless (or (local-string-prefix-p "#" target)
                             (string-contains-p "://" target)
                             (local-string-prefix-p "mailto:" target))
                   (push target links)))
               (setf position (1+ end)))
          finally (return (nreverse links)))))

(defun markdown-code-identifiers (name)
  (let ((contents (doc-file-contents name))
        (identifiers '()))
    (loop with position = 0
          for start = (position #\` contents :start position)
          while start
          do (let ((end (position #\` contents :start (1+ start))))
               (unless end
                 (return))
               (let ((identifier (subseq contents (1+ start) end)))
                 (when (> (length identifier) 0)
                   (push (string-downcase identifier) identifiers)))
               (setf position (1+ end)))
          finally (return (nreverse identifiers)))))

(defun markdown-heading-prefix-p (line)
  (or (local-string-prefix-p "## " line)
      (local-string-prefix-p "### " line)))

(defun markdown-section-contents (name heading)
  (with-input-from-string (stream (doc-file-contents name))
    (with-output-to-string (output)
      (loop with in-section = nil
            for line = (read-line stream nil nil)
            while line
            do (cond
                 ((string= line heading)
                  (setf in-section t))
                 ((and in-section
                       (markdown-heading-prefix-p line))
                  (return))
                 (in-section
                  (write-line line output)))))))

(defun markdown-bullet-code-items (name heading)
  (let ((contents (markdown-section-contents name heading))
        (items '()))
    (with-input-from-string (stream contents)
      (loop for line = (read-line stream nil nil)
            while line
            do (when (local-string-prefix-p "- `" line)
                 (let ((end (position #\` line :start 3)))
                   (when end
                     (push (subseq line 3 end) items))))))
    (nreverse items)))

(defun markdown-link-pathname (doc-name target)
  (let* ((fragment-start (position #\# target))
         (path (if fragment-start
                   (subseq target 0 fragment-start)
                   target))
         (doc-directory (make-pathname :name nil :type nil
                                       :defaults (doc-file-path doc-name))))
    (merge-pathnames path doc-directory)))

(defun assert-document-contains-all (doc-name snippets)
  (assert-string-contains-all (doc-file-contents doc-name) snippets))

(defmacro register-document-snippet-test (name document snippets)
  `(it-sequential ,(string-downcase (string name))
     (assert-document-contains-all ,document ,snippets)))

(defmacro register-document-snippet-tests (&body specs)
  `(progn
     ,@(loop for (name document snippets) in specs
             collect `(register-document-snippet-test ,name ,document ,snippets))))
