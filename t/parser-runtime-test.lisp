(in-package :cl-parser-kit/test)

(it-sequential "bootstrap-load-project-asd-definitions-preserves-relative-component-paths-test"
  (let* ((project-root (common-lisp-user::current-project-root))
         (expected-path (common-lisp-user::project-file project-root
                                                        "src/package.lisp")))
    (ensure-project-asd-registered)
    (let* ((system (common-lisp-user::package-symbol-call "ASDF/SYSTEM-REGISTRY"
                                                          "REGISTERED-SYSTEM"
                                                          "cl-parser-kit"))
           (component (and system
                           (common-lisp-user::package-symbol-call "ASDF/INTERFACE"
                                                                  "FIND-COMPONENT"
                                                                  system
                                                                  "package")))
           (actual-path (and component
                             (common-lisp-user::package-symbol-call "ASDF/INTERFACE"
                                                                    "COMPONENT-PATHNAME"
                                                                    component))))
      (expect component :to-be-truthy)
      ;; Compare TRUENAMEs, not raw namestrings: ASDF resolves symlinks when it
      ;; registers a system, CURRENT-PROJECT-ROOT does not, so a checkout under
      ;; a symlinked path yields two correct spellings of the same file
      ;; ("/private/tmp/..." vs "/tmp/..." on macOS) and a spurious failure.
      ;; The claim under test is that the component resolves to the project's
      ;; own src/package.lisp, which is a file identity question.
      (expect (namestring (truename actual-path))
              :to-equal (namestring (truename expected-path))))))
