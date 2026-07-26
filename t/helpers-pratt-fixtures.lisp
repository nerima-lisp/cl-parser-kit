(in-package :cl-parser-kit/test)

(defparameter *pratt-expression-tokens*
  '((:type :number :text "1" :value 1)
    (:type :plus :text "+")
    (:type :number :text "2" :value 2)))

(defparameter *pratt-postfix-tokens*
  '((:type :number :text "2" :value 2)
    (:type :bang :text "!")
    (:type :bang :text "!")))

(defparameter *pratt-postfix-precedence-tokens*
  '((:type :number :text "1" :value 1)
    (:type :plus :text "+")
    (:type :number :text "2" :value 2)
    (:type :bang :text "!")))

(defparameter *pratt-left-associative-tokens*
  '((:type :number :text "1" :value 1)
    (:type :plus :text "+")
    (:type :number :text "2" :value 2)
    (:type :plus :text "+")
    (:type :number :text "3" :value 3)))

(defparameter *pratt-right-associative-tokens*
  '((:type :number :text "2" :value 2)
    (:type :caret :text "^")
    (:type :number :text "3" :value 3)
    (:type :caret :text "^")
    (:type :number :text "4" :value 4)))

(defparameter *pratt-position-tokens*
  '((:type :comma :text ",")
    (:type :number :text "1" :value 1)
    (:type :plus :text "+")
    (:type :number :text "2" :value 2)))

(defparameter *pratt-min-binding-power-tokens*
  '((:type :number :text "1" :value 1)
    (:type :plus :text "+")
    (:type :number :text "2" :value 2)
    (:type :star :text "*")
    (:type :number :text "3" :value 3)))

(defparameter *number-plus-operators*
  '((:prefix :number 0 nil)
    (:infix :plus 10 %build-add 11)))

(defparameter *number-bang-operators*
  '((:prefix :number 0 nil)
    (:postfix :bang 30 %build-fact)))

(defparameter *number-plus-bang-operators*
  '((:prefix :number 0 nil)
    (:infix :plus 10 %build-add 11)
    (:postfix :bang 30 %build-fact)))

(defparameter *number-caret-operators*
  '((:prefix :number 0 nil)
    (:infix :caret 40 %build-pow 40)))

(defparameter *number-plus-star-operators*
  '((:prefix :number 0 nil)
    (:infix :plus 10 %build-add 11)
    (:infix :star 20 %build-mul 21)))

(defparameter *textual-number-plus-bang-tokens*
  '((:text "num" :value 1)
    (:text "+" :start 1 :end 2)
    (:text "num" :value 2)
    (:text "!" :start 3 :end 4)))

(defparameter *textual-number-plus-bang-operators*
  '((:prefix "num" 0 nil)
    (:infix "+" 10 %build-add 11)
    (:postfix "!" 30 %build-fact)))

(defparameter *pratt-source-plus-literals*
  '((:plus "+")))

(defparameter *pratt-source-position-literals*
  '((:comma ",")
    (:plus "+")
    (:star "*")))
