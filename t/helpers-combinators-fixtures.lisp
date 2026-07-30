(in-package :cl-parser-kit/test)

(defparameter *identifier-plus-number-token-specs*
  '((:type :identifier :text "foo")
    (:type :plus :text "+")
    (:type :number :text "1" :value 1)))

(defparameter *identifier-comma-number-token-specs*
  '((:type :identifier :text "foo")
    (:type :comma :text ",")
    (:type :number :text "1" :value 1)))

(defparameter *positioned-identifier-comma-token-specs*
  '((:type :identifier :text "foo" :start 0 :end 3)
    (:type :comma :text "," :start 3 :end 4)))

(defparameter *positioned-identifier-semicolon-token-specs*
  '((:type :identifier :text "answer" :start 0 :end 6)
    (:type :semicolon :text ";" :start 6 :end 7)))

(defparameter *identifier-only-token-specs*
  '((:type :identifier :text "foo")))

(defparameter *identifier-comma-token-specs*
  '((:type :identifier :text "foo")
    (:type :comma :text ",")))

(defparameter *positioned-identifier-token-with-span-specs*
  '((:type :identifier
     :text "foo"
     :span (:source "foo"
            :start 0 :end 3
            :start-line 1 :start-column 1
            :end-line 1 :end-column 4))))

(defparameter *offset-identifier-token-specs*
  '((:type :identifier :text "foo" :start 4 :end 7)))

(defparameter *offset-identifier-token-near-eoi-specs*
  '((:type :identifier :text "foo" :start 2 :end 5)))

(defparameter *paren-identifier-comma-identifier-token-specs*
  '((:type :lparen :text "(")
    (:type :identifier :text "foo")
    (:type :comma :text ",")
    (:type :identifier :text "bar")
    (:type :rparen :text ")")))

(defparameter *paren-identifier-comma-rparen-token-specs*
  '((:type :lparen :text "(")
    (:type :identifier :text "foo")
    (:type :comma :text ",")
    (:type :rparen :text ")")))

(defparameter *paren-identifier-comma-identifier-comma-rparen-token-specs*
  '((:type :lparen :text "(")
    (:type :identifier :text "foo")
    (:type :comma :text ",")
    (:type :identifier :text "bar")
    (:type :comma :text ",")
    (:type :rparen :text ")")))
