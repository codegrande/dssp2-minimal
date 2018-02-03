;;; cil-mode.el --- CIL mode -*- lexical-binding:t -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; The base major mode for editing CIL code. Derived from Emacs
;; Lisp-mode (https://www.gnu.org/software/emacs/) Copyright (C)
;; 1985-1986, 1999-2018 Free Software Foundation, Inc.

;;; Code:

(eval-when-compile (require 'cl-lib))

(defvar font-lock-comment-face)
(defvar font-lock-doc-face)
(defvar font-lock-keywords-case-fold-search)
(defvar font-lock-string-face)

(define-abbrev-table 'cil-mode-abbrev-table ()
  "Abbrev table for CIL mode.")

(defvar cil--mode-syntax-table
  (let ((table (make-syntax-table))
	(i 0))
    (while (< i ?0)
      (modify-syntax-entry i "_   " table)
      (setq i (1+ i)))
    (setq i (1+ ?9))
    (while (< i ?A)
      (modify-syntax-entry i "_   " table)
      (setq i (1+ i)))
    (setq i (1+ ?Z))
    (while (< i ?a)
      (modify-syntax-entry i "_   " table)
      (setq i (1+ i)))
    (setq i (1+ ?z))
    (while (< i 128)
      (modify-syntax-entry i "_   " table)
      (setq i (1+ i)))
    (modify-syntax-entry ?\s "    " table)
    ;; Non-break space acts as whitespace.
    (modify-syntax-entry ?\xa0 "    " table)
    (modify-syntax-entry ?\t "    " table)
    (modify-syntax-entry ?\f "    " table)
    (modify-syntax-entry ?\n ">   " table)
    ;; This is probably obsolete since nowadays such features use overlays.
    ;; ;; Give CR the same syntax as newline, for selective-display.
    ;; (modify-syntax-entry ?\^m ">   " table)
    (modify-syntax-entry ?\; "<   " table)
    (modify-syntax-entry ?` "'   " table)
    (modify-syntax-entry ?' "'   " table)
    (modify-syntax-entry ?, "'   " table)
    (modify-syntax-entry ?@ "_ p" table)
    ;; Used to be singlequote; changed for flonums.
    (modify-syntax-entry ?. "_   " table)
    (modify-syntax-entry ?# "'   " table)
    (modify-syntax-entry ?\" "\"    " table)
    (modify-syntax-entry ?\\ "\\   " table)
    (modify-syntax-entry ?\( "()  " table)
    (modify-syntax-entry ?\) ")(  " table)
    table)
  "Parent syntax table used in CIL modes.")

(defvar cil-mode-syntax-table
  (let ((table (make-syntax-table cil--mode-syntax-table)))
    (modify-syntax-entry ?\[ "_   " table)
    (modify-syntax-entry ?\] "_   " table)
    (modify-syntax-entry ?# "' 14" table)
    (modify-syntax-entry ?| "\" 23bn" table)
    table)
  "Syntax table used in `CIL-mode'.")

(eval-and-compile
  (defconst cil-mode-symbol-regexp "\\(?:\\sw\\|\\s_\\|\\\\.\\)+"))

;; This was originally in autoload.el and is still used there.
(put 'autoload 'doc-string-elt 3)
(put 'defmethod 'doc-string-elt 3)
(put 'defvar   'doc-string-elt 3)
(put 'defconst 'doc-string-elt 3)
(put 'defalias 'doc-string-elt 3)
(put 'defvaralias 'doc-string-elt 3)
(put 'define-category 'doc-string-elt 2)
;; CL
(put 'defconstant 'doc-string-elt 3)
(put 'defparameter 'doc-string-elt 3)

(defvar cil-doc-string-elt-property 'doc-string-elt
  "The symbol property that holds the docstring position info.")

(defconst cil-prettify-symbols-alist '(("lambda"  . ?λ))
  "Alist of symbol/\"pretty\" characters to be displayed.")

;;;; Font-lock support.

(defun cil--match-hidden-arg (limit)
  (let ((res nil))
    (while
	(let ((ppss (parse-partial-sexp (line-beginning-position)
                                        (line-end-position)
                                        -1)))
	  (skip-syntax-forward " )")
          (if (or (>= (car ppss) 0)
                  (looking-at ";\\|$"))
              (progn
                (forward-line 1)
                (< (point) limit))
            (looking-at ".*")           ;Set the match-data.
	    (forward-line 1)
            (setq res (point))
            nil)))
    res))

(defun cil--el-non-funcall-position-p (pos)
  "Heuristically determine whether POS is an evaluated position."
  (save-match-data
    (save-excursion
      (ignore-errors
        (goto-char pos)
        (or (eql (char-before) ?\')
            (let* ((ppss (syntax-ppss))
                   (paren-posns (nth 9 ppss))
                   (parent
                    (when paren-posns
                      (goto-char (car (last paren-posns))) ;(up-list -1)
                      (cond
                       ((ignore-errors
                          (and (eql (char-after) ?\()
                               (when (cdr paren-posns)
                                 (goto-char (car (last paren-posns 2)))
                                 (looking-at "(\\_<let\\*?\\_>"))))
                        (goto-char (match-end 0))
                        'let)
                       ((looking-at
                         (rx "("
                             (group-n 1 (+ (or (syntax w) (syntax _))))
                             symbol-end))
                        (prog1 (intern-soft (match-string-no-properties 1))
                          (goto-char (match-end 1))))))))
              (or (eq parent 'declare)
                  (and (eq parent 'let)
                       (progn
                         (forward-sexp 1)
                         (< pos (point))))
                  (and (eq parent 'condition-case)
                       (progn
                         (forward-sexp 2)
                         (< (point) pos))))))))))

(defun cil--el-match-keyword (limit)
  ;; FIXME: Move to elisp-mode.el.
  (catch 'found
    (while (re-search-forward
            (eval-when-compile
              (concat "(\\(" cil-mode-symbol-regexp "\\)\\_>"))
            limit t)
      (let ((sym (intern-soft (match-string 1))))
	(when (or (special-form-p sym)
		  (and (macrop sym)
                       (not (get sym 'no-font-lock-keyword))
                       (not (cil--el-non-funcall-position-p
                             (match-beginning 0)))))
	  (throw 'found t))))))

(defmacro let-when-compile (bindings &rest body)
  "Like `let*', but allow for compile time optimization.
Use BINDINGS as in regular `let*', but in BODY each usage should
be wrapped in `eval-when-compile'.
This will generate compile-time constants from BINDINGS."
  (declare (indent 1) (debug let))
  (letrec ((loop
            (lambda (bindings)
              (if (null bindings)
                  (macroexpand-all (macroexp-progn body)
                                   macroexpand-all-environment)
                (let ((binding (pop bindings)))
                  (cl-progv (list (car binding))
                      (list (eval (nth 1 binding) t))
                    (funcall loop bindings)))))))
    (funcall loop bindings)))

(defun cil--font-lock-backslash ()
  (let* ((beg0 (match-beginning 0))
         (end0 (match-end 0))
         (ppss (save-excursion (syntax-ppss beg0))))
    (and (nth 3 ppss)                  ;Inside a string.
         (not (nth 5 ppss))            ;The \ is not itself \-escaped.
         ;; Don't highlight the \( introduced because of
         ;; `open-paren-in-column-0-is-defun-start'.
         (not (eq ?\n (char-before beg0)))
         (equal (ignore-errors
                  (car (read-from-string
                        (format "\"%s\""
                                (buffer-substring-no-properties
                                 beg0 end0)))))
                (buffer-substring-no-properties (1+ beg0) end0))
         `(face ,font-lock-warning-face
                help-echo "This \\ has no effect"))))

(let-when-compile
    ((lisp-fdefs '("defmacro" "defun"))
     (lisp-vdefs '("defvar"))
     (lisp-kw '("cond" "if" "while" "let" "let*" "progn" "prog1"
                "prog2" "lambda" "unwind-protect" "condition-case"
                "when" "unless" "with-output-to-string"
                "ignore-errors" "dotimes" "dolist" "declare"))
     (lisp-errs '("warn" "error" "signal"))
     ;; Elisp constructs.  Now they are update dynamically
     ;; from obarray but they are also used for setting up
     ;; the keywords for Common Lisp.
     (el-fdefs '("defsubst" "cl-defsubst" "define-inline"
                 "define-advice" "defadvice" "defalias"
                 "define-derived-mode" "define-minor-mode"
                 "define-generic-mode" "define-global-minor-mode"
                 "define-globalized-minor-mode" "define-skeleton"
                 "define-widget" "ert-deftest"))
     (el-vdefs '("defconst" "defcustom" "defvaralias" "defvar-local"
                 "defface"))
     (el-tdefs '("defgroup" "deftheme"))
     (el-errs '("user-error"))
     ;; Common-Lisp constructs supported by EIEIO.  FIXME: namespace.
     (eieio-fdefs '("defgeneric" "defmethod"))
     (eieio-tdefs '("defclass"))
     ;; Common-Lisp constructs supported by cl-lib.
     (cl-lib-fdefs '("defmacro" "defsubst" "defun" "defmethod" "defgeneric"))
     (cl-lib-tdefs '("defstruct" "deftype"))
     (cl-lib-errs '("assert" "check-type"))
     ;; Common-CIL constructs not supported by cl-lib.
     (cl-fdefs '("macro"))
     (cl-vdefs '("call" "context" "ipaddr" "filecon" "portcon" "netifcon" "fsuse" "genfscon"
		 "ibpkeycon" "ibendportcon" "sensitivity" "sensitivityalias" "sensitivityaliasactual"
		 "sensitivityorder" "category" "categoryalias" "categoryaliasactual" "categoryorder"
		 "categoryset" "sensitivitycategory" "level" "netifcon" "nodecon" "sidcontext"
		 "iomemcon" "ioportcon" "pcidevicecon" "pirqcon" "devicetreecon"))
     (cl-tdefs '("type" "role" "user" "boolean" "tunable" "class" "name" "string"
		 "levelrange" "classcommon" "classorder" "classpermissionset"
		 "classmap" "classmapping" "permissionx" "common" "classpermission"
		 "validatetrans" "mlsvalidatetrans" "mls" "handleunknown" "policycap" "roleattribute"
		 "sid" "typealias" "typeattribute" "userattribute"))
     (cl-kw '("block" "in" "blockabstract" "blockinherit" "optional" "allowx" "auditallowx" "dontauditx" "neverallowx"
              "allow" "neverallow" "dontaudit" "auditallow" "typetransition" "roletransition"
              "rangetransition" "userrole" "roleallow" "rolebounds" "roletype" "typebounds" "typechange"
              "typemember" "userbounds" "sidorder" "userrole" "userattributeset" "userlevel" "userrange"
              "userprefix" "typeattributeset" "selinuxuser" "selinuxuserdefault" "typealiasactual"
              "roleattributeset" "defaultrange" "defaulttype" "defaultrole" "defaultuser"
              "constrain" "mlsconstrain" "booleanif" "tunableif" "true" "false" "and" "or" "xor" "eq" "neq" "not"))
     (cl-errs '("abort" "cerror")))
  (let ((vdefs (eval-when-compile
                 (append lisp-vdefs el-vdefs cl-vdefs)))
        (tdefs (eval-when-compile
                 (append el-tdefs eieio-tdefs cl-tdefs cl-lib-tdefs
                         (mapcar (lambda (s) (concat "cl-" s)) cl-lib-tdefs))))
        ;; Elisp and Common Lisp definers.
        (el-defs-re (eval-when-compile
                      (regexp-opt (append lisp-fdefs lisp-vdefs
                                          el-fdefs el-vdefs el-tdefs
                                          (mapcar (lambda (s) (concat "cl-" s))
                                                  (append cl-lib-fdefs cl-lib-tdefs))
                                          eieio-fdefs eieio-tdefs)
                                  t)))
        (cl-defs-re (eval-when-compile
                      (regexp-opt (append lisp-fdefs lisp-vdefs
                                          cl-lib-fdefs cl-lib-tdefs
                                          eieio-fdefs eieio-tdefs
                                          cl-fdefs cl-vdefs cl-tdefs)
                                  t)))
        ;; Common Lisp keywords (Elisp keywords are handled dynamically).
        (cl-kws-re (eval-when-compile
                     (regexp-opt (append lisp-kw cl-kw) t)))
        ;; Elisp and Common Lisp "errors".
        (el-errs-re (eval-when-compile
                      (regexp-opt (append (mapcar (lambda (s) (concat "cl-" s))
                                                  cl-lib-errs)
                                          lisp-errs el-errs)
                                  t)))
        (cl-errs-re (eval-when-compile
                      (regexp-opt (append lisp-errs cl-lib-errs cl-errs) t))))
    (dolist (v vdefs)
      (put (intern v) 'cil-define-type 'var))
    (dolist (v tdefs)
      (put (intern v) 'cil-define-type 'type))

    (define-obsolete-variable-alias 'cil-font-lock-keywords-1
      'cil-el-font-lock-keywords-1 "24.4")
    (defconst cil-el-font-lock-keywords-1
      `( ;; Definitions.
        (,(concat "(" el-defs-re "\\_>"
                  ;; Any whitespace and defined object.
                  "[ \t']*"
                  "\\(([ \t']*\\)?" ;; An opening paren.
                  "\\(\\(setf\\)[ \t]+" cil-mode-symbol-regexp
                  "\\|" cil-mode-symbol-regexp "\\)?")
	 (1 font-lock-keyword-face)
	 (3 (let ((type (get (intern-soft (match-string 1)) 'cil-define-type)))
	      (cond ((eq type 'var) font-lock-variable-name-face)
		    ((eq type 'type) font-lock-type-face)
		    ;; If match-string 2 is non-nil, we encountered a
		    ;; form like (defalias (intern (concat s "-p"))),
		    ;; unless match-string 4 is also there.  Then its a
		    ;; defmethod with (setf foo) as name.
		    ((or (not (match-string 2)) ;; Normal defun.
			 (and (match-string 2)  ;; Setf method.
			      (match-string 4)))
		     font-lock-function-name-face)))
	    nil t))
        ;; Emacs Lisp autoload cookies.  Supports the slightly different
        ;; forms used by mh-e, calendar, etc.
        ("^;;;###\\([-a-z]*autoload\\)" 1 font-lock-warning-face prepend))
      "Subdued level highlighting for Emacs CIL mode.")

    (defconst cil-cl-font-lock-keywords-1
      `( ;; Definitions.
        (,(concat "(" cl-defs-re "\\_>"
                  ;; Any whitespace and defined object.
                  "[ \t']*"
                  "\\(([ \t']*\\)?" ;; An opening paren.
                  "\\(\\(setf\\)[ \t]+" cil-mode-symbol-regexp
                  "\\|" cil-mode-symbol-regexp "\\)?")
	 (1 font-lock-keyword-face)
	 (3 (let ((type (get (intern-soft (match-string 1)) 'lisp-define-type)))
	      (cond ((eq type 'var) font-lock-variable-name-face)
		    ((eq type 'type) font-lock-type-face)
		    ((or (not (match-string 2)) ;; Normal defun.
			 (and (match-string 2)  ;; Setf function.
			      (match-string 4)))
		     font-lock-function-name-face)))
	    nil t)))
      "Subdued level highlighting for CIL modes.")

    (define-obsolete-variable-alias 'cil-font-lock-keywords-2
      'cil-el-font-lock-keywords-2 "24.4")
    (defconst cil-el-font-lock-keywords-2
      (append
       cil-el-font-lock-keywords-1
       `( ;; Regexp negated char group.
         ("\\[\\(\\^\\)" 1 font-lock-negation-char-face prepend)
         ;; Erroneous structures.
         (,(concat "(" el-errs-re "\\_>")
          (1 font-lock-warning-face))
         ;; Control structures.  Common Lisp forms.
         (cil--el-match-keyword . 1)
         ;; Exit/Feature symbols as constants.
         (,(concat "(\\(catch\\|throw\\|featurep\\|provide\\|require\\)\\_>"
                   "[ \t']*\\(" cil-mode-symbol-regexp "\\)?")
	  (1 font-lock-keyword-face)
	  (2 font-lock-constant-face nil t))
         ;; Words inside \\[] tend to be for `substitute-command-keys'.
         (,(concat "\\\\\\\\\\[\\(" cil-mode-symbol-regexp "\\)\\]")
          (1 font-lock-constant-face prepend))
         ;; Ineffective backslashes (typically in need of doubling).
         ("\\(\\\\\\)\\([^\"\\]\\)"
          (1 (cil--font-lock-backslash) prepend))
         ;; Words inside ‘’ and `' tend to be symbol names.
         (,(concat "[`‘]\\(\\(?:\\sw\\|\\s_\\|\\\\.\\)"
                   cil-mode-symbol-regexp "\\)['’]")
          (1 font-lock-constant-face prepend))
         ;; Constant values.
         (,(concat "\\_<:" cil-mode-symbol-regexp "\\_>")
          (0 font-lock-builtin-face))
         ;; ELisp and CLisp `&' keywords as types.
         (,(concat "\\_<\\&" cil-mode-symbol-regexp "\\_>")
          . font-lock-type-face)
         ;; ELisp regexp grouping constructs
         (,(lambda (bound)
             (catch 'found
               ;; The following loop is needed to continue searching after matches
               ;; that do not occur in strings.  The associated regexp matches one
               ;; of `\\\\' `\\(' `\\(?:' `\\|' `\\)'.  `\\\\' has been included to
               ;; avoid highlighting, for example, `\\(' in `\\\\('.
               (while (re-search-forward "\\(\\\\\\\\\\)\\(?:\\(\\\\\\\\\\)\\|\\((\\(?:\\?[0-9]*:\\)?\\|[|)]\\)\\)" bound t)
                 (unless (match-beginning 2)
                   (let ((face (get-text-property (1- (point)) 'face)))
                     (when (or (and (listp face)
                                    (memq 'font-lock-string-face face))
                               (eq 'font-lock-string-face face))
                       (throw 'found t)))))))
	  (1 'font-lock-regexp-grouping-backslash prepend)
	  (3 'font-lock-regexp-grouping-construct prepend))
         (lisp--match-hidden-arg
          (0 '(face font-lock-warning-face
		    help-echo "Hidden behind deeper element; move to another line?")))
         ))
      "Gaudy level highlighting for Emacs Lisp mode.")

    (defconst cil-cl-font-lock-keywords-2
      (append
       cil-cl-font-lock-keywords-1
       `( ;; Regexp negated char group.
         ("\\[\\(\\^\\)" 1 font-lock-negation-char-face prepend)
         ;; Control structures.  Common Lisp forms.
         (,(concat "(" cl-kws-re "\\_>") . 1)
         ;; Exit/Feature symbols as constants.
         (,(concat "(\\(catch\\|throw\\|provide\\|require\\)\\_>"
                   "[ \t']*\\(" cil-mode-symbol-regexp "\\)?")
	  (1 font-lock-keyword-face)
	  (2 font-lock-constant-face nil t))
         ;; Erroneous structures.
         (,(concat "(" cl-errs-re "\\_>")
	  (1 font-lock-warning-face))
         ;; Words inside ‘’ and `' tend to be symbol names.
         (,(concat "[`‘]\\(\\(?:\\sw\\|\\s_\\|\\\\.\\)"
                   cil-mode-symbol-regexp "\\)['’]")
          (1 font-lock-constant-face prepend))
         ;; Uninterned symbols, e.g., (defpackage #:my-package ...)
         ;; must come before keywords below to have effect
         (,(concat "\\(#:\\)\\(" cil-mode-symbol-regexp "\\)")
	  (1 font-lock-comment-delimiter-face)
	  (2 font-lock-doc-face))
         ;; Constant values.
         (,(concat "\\_<:" cil-mode-symbol-regexp "\\_>")
          (0 font-lock-builtin-face))
         ;; ELisp and CLisp `&' keywords as types.
         (,(concat "\\_<\\&" cil-mode-symbol-regexp "\\_>")
          . font-lock-type-face)
         ;; This is too general -- rms.
         ;; A user complained that he has functions whose names start with `do'
         ;; and that they get the wrong color.
         ;; That user has violated the http://www.cliki.net/Naming+conventions:
         ;; CL (but not EL!) `with-' (context) and `do-' (iteration)
         (,(concat "(\\(\\(do-\\|with-\\)" cil-mode-symbol-regexp "\\)")
	  (1 font-lock-keyword-face))
         (lisp--match-hidden-arg
          (0 '(face font-lock-warning-face
		    help-echo "Hidden behind deeper element; move to another line?")))
         ))
      "Gaudy level highlighting for CIL modes.")))

(define-obsolete-variable-alias 'cil-font-lock-keywords
  'cil-el-font-lock-keywords "24.4")
(defvar cil-el-font-lock-keywords cil-el-font-lock-keywords-1
  "Default expressions to highlight in Emacs CIL mode.")
(defvar cil-cl-font-lock-keywords cil-cl-font-lock-keywords-1
  "Default expressions to highlight in CIL modes.")

(defun cil-string-in-doc-position-p (listbeg startpos)
  "Return true if a doc string may occur at STARTPOS inside a list.
LISTBEG is the position of the start of the innermost list
containing STARTPOS."
  (let* ((firstsym (and listbeg
                        (save-excursion
                          (goto-char listbeg)
                          (and (looking-at
                                (eval-when-compile
                                  (concat "([ \t\n]*\\("
                                          cil-mode-symbol-regexp "\\)")))
                               (match-string 1)))))
         (docelt (and firstsym
                      (function-get (intern-soft firstsym)
                                    cil-doc-string-elt-property))))
    (and docelt
         ;; It's a string in a form that can have a docstring.
         ;; Check whether it's in docstring position.
         (save-excursion
           (when (functionp docelt)
             (goto-char (match-end 1))
             (setq docelt (funcall docelt)))
           (goto-char listbeg)
           (forward-char 1)
           (condition-case nil
               (while (and (> docelt 0) (< (point) startpos)
                           (progn (forward-sexp 1) t))
                 (setq docelt (1- docelt)))
             (error nil))
           (and (zerop docelt) (<= (point) startpos)
                (progn (forward-comment (point-max)) t)
                (= (point) startpos))))))

(defun cil-string-after-doc-keyword-p (listbeg startpos)
  "Return true if `:documentation' symbol ends at STARTPOS inside a list.
LISTBEG is the position of the start of the innermost list
containing STARTPOS."
  (and listbeg                          ; We are inside a Lisp form.
       (save-excursion
         (goto-char startpos)
         (ignore-errors
           (progn (backward-sexp 1)
                  (looking-at ":documentation\\_>"))))))

(defun cil-font-lock-syntactic-face-function (state)
  "Return syntactic face function for the position represented by STATE.
STATE is a `parse-partial-sexp' state, and the returned function is the
Lisp font lock syntactic face function."
  (if (nth 3 state)
      ;; This might be a (doc)string or a |...| symbol.
      (let ((startpos (nth 8 state)))
        (if (eq (char-after startpos) ?|)
            ;; This is not a string, but a |...| symbol.
            nil
          (let ((listbeg (nth 1 state)))
            (if (or (cil-string-in-doc-position-p listbeg startpos)
                    (cil-string-after-doc-keyword-p listbeg startpos))
                font-lock-doc-face
              font-lock-string-face))))
    font-lock-comment-face))

(defun cil-adaptive-fill ()
  "Return fill prefix found at point.
Value for `adaptive-fill-function'."
  ;; Adaptive fill mode gets the fill wrong for a one-line paragraph made of
  ;; a single docstring.  Let's fix it here.
  (if (looking-at "\\s-+\"[^\n\"]+\"\\s-*$") ""))

(defun cil-mode-variables (&optional cil-syntax keywords-case-insensitive
				     elisp)
  "Common initialization routine for lisp modes.
The LISP-SYNTAX argument is used by code in inf-lisp.el and is
\(uselessly) passed from pp.el, chistory.el, gnus-kill.el and
score-mode.el.  KEYWORDS-CASE-INSENSITIVE non-nil means that for
font-lock keywords will not be case sensitive."
  (when cil-syntax
    (set-syntax-table cil-mode-syntax-table))
  (setq-local paragraph-ignore-fill-prefix t)
  (setq-local fill-paragraph-function 'cil-fill-paragraph)
  (setq-local adaptive-fill-function #'cil-adaptive-fill)
  ;; Adaptive fill mode gets in the way of auto-fill,
  ;; and should make no difference for explicit fill
  ;; because lisp-fill-paragraph should do the job.
  ;;  I believe that newcomment's auto-fill code properly deals with it  -stef
  ;;(set (make-local-variable 'adaptive-fill-mode) nil)
  (setq-local indent-line-function 'cil-indent-line)
  (setq-local indent-region-function 'cil-indent-region)
  (setq-local comment-indent-function #'cil-comment-indent)
  (setq-local outline-regexp ";;;\\(;* [^ \t\n]\\|###autoload\\)\\|(")
  (setq-local outline-level 'cil-outline-level)
  (setq-local add-log-current-defun-function #'cil-current-defun-name)
  (setq-local comment-start ";")
  (setq-local comment-start-skip ";+ *")
  (setq-local comment-add 1)        ;default to `;;' in comment-region
  (setq-local comment-column 40)
  (setq-local comment-use-syntax t)
  (setq-local multibyte-syntax-as-symbol t)
  ;; (setq-local syntax-begin-function 'beginning-of-defun)  ;;Bug#16247.
  (setq font-lock-defaults
	`(,(if elisp '(cil-el-font-lock-keywords
                       cil-el-font-lock-keywords-1
                       cil-el-font-lock-keywords-2)
             '(cil-cl-font-lock-keywords
               cil-cl-font-lock-keywords-1
               cil-cl-font-lock-keywords-2))
	  nil ,keywords-case-insensitive nil nil
	  (font-lock-mark-block-function . mark-defun)
          (font-lock-extra-managed-props help-echo)
	  (font-lock-syntactic-face-function
	   . cil-font-lock-syntactic-face-function)))
  (setq-local prettify-symbols-alist cil-prettify-symbols-alist)
  (setq-local electric-pair-skip-whitespace 'chomp)
  (setq-local electric-pair-open-newline-between-pairs nil))

(defun cil-outline-level ()
  "CIL mode `outline-level' function."
  (let ((len (- (match-end 0) (match-beginning 0))))
    (if (looking-at "(\\|;;;###autoload")
	1000
      len)))

(defun cil-current-defun-name ()
  "Return the name of the defun at point, or nil."
  (save-excursion
    (let ((location (point)))
      ;; If we are now precisely at the beginning of a defun, make sure
      ;; beginning-of-defun finds that one rather than the previous one.
      (or (eobp) (forward-char 1))
      (beginning-of-defun)
      ;; Make sure we are really inside the defun found, not after it.
      (when (and (looking-at "\\s(")
		 (progn (end-of-defun)
			(< location (point)))
		 (progn (forward-sexp -1)
			(>= location (point))))
	(if (looking-at "\\s(")
	    (forward-char 1))
	;; Skip the defining construct name, typically "defun" or
	;; "defvar".
	(forward-sexp 1)
	;; The second element is usually a symbol being defined.  If it
	;; is not, use the first symbol in it.
	(skip-chars-forward " \t\n'(")
	(buffer-substring-no-properties (point)
					(progn (forward-sexp 1)
					       (point)))))))

(defvar cil-mode-shared-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map prog-mode-map)
    (define-key map "\e\C-q" 'indent-sexp)
    (define-key map "\177" 'backward-delete-char-untabify)
    ;; This gets in the way when viewing a Lisp file in view-mode.  As
    ;; long as [backspace] is mapped into DEL via the
    ;; function-key-map, this should remain disabled!!
    ;;;(define-key map [backspace] 'backward-delete-char-untabify)
    map)
  "Keymap for commands shared by all sorts of CIL modes.")

(defcustom cil-mode-hook nil
  "Hook run when entering CIL mode."
  :type 'hook
  :group 'cil)

(defcustom cil-interaction-mode-hook nil
  "Hook run when entering CIL Interaction mode."
  :options '(eldoc-mode)
  :type 'hook
  :group 'cil)

;;; Generic CIL mode.

(defvar cil-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map cil-mode-shared-map)
    (define-key map "\e\C-x" 'cil-eval-defun)
    (define-key map "\C-c\C-z" 'run-cil)
    map)
  "Keymap for ordinary CIL mode.
All commands in `cil-mode-shared-map' are inherited by this map.")

(define-derived-mode cil-mode prog-mode "CIL"
  "Major mode for editing CIL code.
Commands:
Delete converts tabs to spaces as it moves back.
Blank lines separate paragraphs.  Semicolons start comments.

\\{cil-mode-map}
Note that `run-cil' may be used either to start an inferior CIL job
or to switch back to an existing one."
  (cil-mode-variables nil t)
  (setq-local find-tag-default-function 'cil-find-tag-default)
  (setq-local comment-start-skip
	      "\\(\\(^\\|[^\\\\\n]\\)\\(\\\\\\\\\\)*\\)\\(;+\\|#|\\) *"))

(defun cil-find-tag-default ()
  (let ((default (find-tag-default)))
    (when (stringp default)
      (if (string-match ":+" default)
          (substring default (match-end 0))
        default))))

;; Used in old LispM code.
(defalias 'common-cil-mode 'cil-mode)

(autoload 'cil-eval-defun "inf-cil" nil t)

(defun cil-comment-indent ()
  "Like `comment-indent-default', but don't put space after open paren."
  (or (when (looking-at "\\s<\\s<")
        (let ((pt (point)))
          (skip-syntax-backward " ")
          (if (eq (preceding-char) ?\()
              (cons (current-column) (current-column))
            (goto-char pt)
            nil)))
      (comment-indent-default)))

(define-obsolete-function-alias 'cil-mode-auto-fill 'do-auto-fill "23.1")

(defcustom cil-indent-offset nil
  "If non-nil, indent second line of expressions that many more columns."
  :group 'cil
  :type '(choice (const nil) integer))
(put 'cil-indent-offset 'safe-local-variable
     (lambda (x) (or (null x) (integerp x))))

(defcustom cil-indent-function 'cil-indent-function
  "A function to be called by `calculate-cil-indent'.
It indents the arguments of a CIL function call.  This function
should accept two arguments: the indent-point, and the
`parse-partial-sexp' state at that position.  One option for this
function is `common-cil-indent-function'."
  :type 'function
  :group 'cil)

(defun cil-ppss (&optional pos)
  "Return Parse-Partial-Sexp State at POS, defaulting to point.
Like `syntax-ppss' but includes the character address of the last
complete sexp in the innermost containing list at position
2 (counting from 0).  This is important for CIL indentation."
  (unless pos (setq pos (point)))
  (let ((pss (syntax-ppss pos)))
    (if (nth 9 pss)
        (let ((sexp-start (car (last (nth 9 pss)))))
          (parse-partial-sexp sexp-start pos nil nil (syntax-ppss sexp-start)))
      pss)))

(cl-defstruct (cil-indent-state
               (:constructor nil)
               (:constructor cil-indent-initial-state
                             (&aux (ppss (cil-ppss))
                                   (ppss-point (point))
                                   (stack (make-list (1+ (car ppss)) nil)))))
  stack ;; Cached indentation, per depth.
  ppss
  ppss-point)

(defun cil-indent-calc-next (state)
  "Move to next line and return calculated indent for it.
STATE is updated by side effect, the first state should be
created by `cil-indent-initial-state'.  This function may move
by more than one line to cross a string literal."
  (pcase-let* (((cl-struct cil-indent-state
                           (stack indent-stack) ppss ppss-point)
                state)
               (indent-depth (car ppss)) ; Corresponding to indent-stack.
               (depth indent-depth))
    ;; Parse this line so we can learn the state to indent the
    ;; next line.
    (while (let ((last-sexp (nth 2 ppss)))
             (setq ppss (parse-partial-sexp
                         ppss-point (progn (end-of-line) (point))
                         nil nil ppss))
             ;; Preserve last sexp of state (position 2) for
             ;; `calculate-lisp-indent', if we're at the same depth.
             (if (and (not (nth 2 ppss)) (= depth (car ppss)))
                 (setf (nth 2 ppss) last-sexp)
               (setq last-sexp (nth 2 ppss)))
             (setq depth (car ppss))
             ;; Skip over newlines within strings.
             (nth 3 ppss))
      (let ((string-start (nth 8 ppss)))
        (setq ppss (parse-partial-sexp (point) (point-max)
                                       nil nil ppss 'syntax-table))
        (setf (nth 2 ppss) string-start) ; Finished a complete string.
        (setq depth (car ppss)))
      (setq ppss-point (point)))
    (setq ppss-point (point))
    (let* ((depth-delta (- depth indent-depth)))
      (cond ((< depth-delta 0)
             (setq indent-stack (nthcdr (- depth-delta) indent-stack)))
            ((> depth-delta 0)
             (setq indent-stack (nconc (make-list depth-delta nil)
                                       indent-stack)))))
    (prog1
        (let (indent)
          (cond ((= (forward-line 1) 1) nil)
                ((car indent-stack))
                ((integerp (setq indent (calculate-cil-indent ppss)))
                 (setf (car indent-stack) indent))
                ((consp indent)       ; (COLUMN CONTAINING-SEXP-START)
                 (car indent))
                ;; This only happens if we're in a string.
                (t (error "This shouldn't happen"))))
      (setf (cil-indent-state-stack state) indent-stack)
      (setf (cil-indent-state-ppss-point state) ppss-point)
      (setf (cil-indent-state-ppss state) ppss))))

(defun cil-indent-region (start end)
  "Indent region as CIL code, efficiently."
  (save-excursion
    (setq end (copy-marker end))
    (goto-char start)
    (beginning-of-line)
    ;; The default `indent-region-line-by-line' doesn't hold a running
    ;; parse state, which forces each indent call to reparse from the
    ;; beginning.  That has O(n^2) complexity.
    (let* ((parse-state (cil-indent-initial-state))
           (pr (unless (minibufferp)
                 (make-progress-reporter "Indenting region..." (point) end))))
      (let ((ppss (cil-indent-state-ppss parse-state)))
        (unless (or (and (bolp) (eolp)) (nth 3 ppss))
          (cil-indent-line (calculate-cil-indent ppss))))
      (let ((indent nil))
        (while (progn (setq indent (cil-indent-calc-next parse-state))
                      (< (point) end))
          (unless (or (and (bolp) (eolp)) (not indent))
            (cil-indent-line indent))
          (and pr (progress-reporter-update pr (point)))))
      (and pr (progress-reporter-done pr))
      (move-marker end nil))))

(defun cil-indent-line (&optional indent)
  "Indent current line as CIL code."
  (interactive)
  (let ((pos (- (point-max) (point)))
        (indent (progn (beginning-of-line)
                       (or indent (calculate-cil-indent (cil-ppss))))))
    (skip-chars-forward " \t")
    (if (or (null indent) (looking-at "\\s<\\s<\\s<"))
	;; Don't alter indentation of a ;;; comment line
	;; or a line that starts in a string.
        ;; FIXME: inconsistency: comment-indent moves ;;; to column 0.
	(goto-char (- (point-max) pos))
      (if (and (looking-at "\\s<") (not (looking-at "\\s<\\s<")))
	  ;; Single-semicolon comment lines should be indented
	  ;; as comment lines, not as code.
	  (progn (indent-for-comment) (forward-char -1))
	(if (listp indent) (setq indent (car indent)))
        (indent-line-to indent))
      ;; If initial point was within line's indentation,
      ;; position after the indentation.  Else stay at same point in text.
      (if (> (- (point-max) pos) (point))
	  (goto-char (- (point-max) pos))))))

(defvar calculate-cil-indent-last-sexp)

(defun calculate-cil-indent (&optional parse-start)
  "Return appropriate indentation for current line as CIL code.
In usual case returns an integer: the column to indent to.
If the value is nil, that means don't change the indentation
because the line starts inside a string.
PARSE-START may be a buffer position to start parsing from, or a
parse state as returned by calling `parse-partial-sexp' up to the
beginning of the current line.
The value can also be a list of the form (COLUMN CONTAINING-SEXP-START).
This means that following lines at the same level of indentation
should not necessarily be indented the same as this line.
Then COLUMN is the column to indent to, and CONTAINING-SEXP-START
is the buffer position of the start of the containing expression."
  (save-excursion
    (beginning-of-line)
    (let ((indent-point (point))
          state
          ;; setting this to a number inhibits calling hook
          (desired-indent nil)
          (retry t)
          calculate-cil-indent-last-sexp containing-sexp)
      (cond ((or (markerp parse-start) (integerp parse-start))
             (goto-char parse-start))
            ((null parse-start) (beginning-of-defun))
            (t (setq state parse-start)))
      (unless state
        ;; Find outermost containing sexp
        (while (< (point) indent-point)
          (setq state (parse-partial-sexp (point) indent-point 0))))
      ;; Find innermost containing sexp
      (while (and retry
		  state
                  (> (elt state 0) 0))
        (setq retry nil)
        (setq calculate-cil-indent-last-sexp (elt state 2))
        (setq containing-sexp (elt state 1))
        ;; Position following last unclosed open.
        (goto-char (1+ containing-sexp))
        ;; Is there a complete sexp since then?
        (if (and calculate-cil-indent-last-sexp
		 (> calculate-cil-indent-last-sexp (point)))
            ;; Yes, but is there a containing sexp after that?
            (let ((peek (parse-partial-sexp calculate-cil-indent-last-sexp
					    indent-point 0)))
              (if (setq retry (car (cdr peek))) (setq state peek)))))
      (if retry
          nil
        ;; Innermost containing sexp found
        (goto-char (1+ containing-sexp))
        (if (not calculate-cil-indent-last-sexp)
	    ;; indent-point immediately follows open paren.
	    ;; Don't call hook.
            (setq desired-indent (current-column))
	  ;; Find the start of first element of containing sexp.
	  (parse-partial-sexp (point) calculate-cil-indent-last-sexp 0 t)
	  (cond ((looking-at "\\s(")
		 ;; First element of containing sexp is a list.
		 ;; Indent under that list.
		 )
		((> (save-excursion (forward-line 1) (point))
		    calculate-cil-indent-last-sexp)
		 ;; This is the first line to start within the containing sexp.
		 ;; It's almost certainly a function call.
		 (if (= (point) calculate-cil-indent-last-sexp)
		     ;; Containing sexp has nothing before this line
		     ;; except the first element.  Indent under that element.
		     nil
		   ;; Skip the first element, find start of second (the first
		   ;; argument of the function call) and indent under.
		   (progn (forward-sexp 1)
			  (parse-partial-sexp (point)
					      calculate-cil-indent-last-sexp
					      0 t)))
		 (backward-prefix-chars))
		(t
		 ;; Indent beneath first sexp on same line as
		 ;; `calculate-lisp-indent-last-sexp'.  Again, it's
		 ;; almost certainly a function call.
		 (goto-char calculate-cil-indent-last-sexp)
		 (beginning-of-line)
		 (parse-partial-sexp (point) calculate-cil-indent-last-sexp
				     0 t)
		 (backward-prefix-chars)))))
      ;; Point is at the point to indent under unless we are inside a string.
      ;; Call indentation hook except when overridden by lisp-indent-offset
      ;; or if the desired indentation has already been computed.
      (let ((normal-indent (current-column)))
        (cond ((elt state 3)
               ;; Inside a string, don't change indentation.
	       nil)
              ((and (integerp cil-indent-offset) containing-sexp)
               ;; Indent by constant offset
               (goto-char containing-sexp)
               (+ (current-column) cil-indent-offset))
              ;; in this case calculate-lisp-indent-last-sexp is not nil
              (calculate-cil-indent-last-sexp
               (or
                ;; try to align the parameters of a known function
                (and cil-indent-function
                     (not retry)
                     (funcall cil-indent-function indent-point state))
                ;; If the function has no special alignment
		;; or it does not apply to this argument,
		;; try to align a constant-symbol under the last
                ;; preceding constant symbol, if there is such one of
                ;; the last 2 preceding symbols, in the previous
                ;; uncommented line.
                (and (save-excursion
                       (goto-char indent-point)
                       (skip-chars-forward " \t")
                       (looking-at ":"))
                     ;; The last sexp may not be at the indentation
                     ;; where it begins, so find that one, instead.
                     (save-excursion
                       (goto-char calculate-cil-indent-last-sexp)
		       ;; Handle prefix characters and whitespace
		       ;; following an open paren.  (Bug#1012)
                       (backward-prefix-chars)
                       (while (not (or (looking-back "^[ \t]*\\|([ \t]+"
						     (line-beginning-position))
                                       (and containing-sexp
                                            (>= (1+ containing-sexp) (point)))))
                         (forward-sexp -1)
                         (backward-prefix-chars))
                       (setq calculate-cil-indent-last-sexp (point)))
                     (> calculate-cil-indent-last-sexp
                        (save-excursion
                          (goto-char (1+ containing-sexp))
                          (parse-partial-sexp (point) calculate-cil-indent-last-sexp 0 t)
                          (point)))
                     (let ((parse-sexp-ignore-comments t)
                           indent)
                       (goto-char calculate-cil-indent-last-sexp)
                       (or (and (looking-at ":")
                                (setq indent (current-column)))
                           (and (< (line-beginning-position)
                                   (prog2 (backward-sexp) (point)))
                                (looking-at ":")
                                (setq indent (current-column))))
                       indent))
                ;; another symbols or constants not preceded by a constant
                ;; as defined above.
                normal-indent))
              ;; in this case calculate-lisp-indent-last-sexp is nil
              (desired-indent)
              (t
	       normal-indent))))))

(defun cil-indent-function (indent-point state)
  "This function is the normal value of the variable `cil-indent-function'.
The function `calculate-cil-indent' calls this to determine
if the arguments of a CIL function call should be indented specially.
INDENT-POINT is the position at which the line being indented begins.
Point is located at the point to indent under (for default indentation);
STATE is the `parse-partial-sexp' state for that position.
If the current line is in a call to a CIL function that has a non-nil
property `cil-indent-function' (or the deprecated `cil-indent-hook'),
it specifies how to indent.  The property value can be:
* `defun', meaning indent `defun'-style
  (this is also the case if there is no property and the function
  has a name that begins with \"def\", and three or more arguments);
* an integer N, meaning indent the first N arguments specially
  (like ordinary function arguments), and then indent any further
  arguments like a body;
* a function to call that returns the indentation (or nil).
  `cil-indent-function' calls this function with the same two arguments
  that it itself received.
This function returns either the indentation to use, or nil if the
CIL function does not specify a special indentation."
  (let ((normal-indent (current-column)))
    (goto-char (1+ (elt state 1)))
    (parse-partial-sexp (point) calculate-cil-indent-last-sexp 0 t)
    (if (and (elt state 2)
             (not (looking-at "\\sw\\|\\s_")))
        ;; car of form doesn't seem to be a symbol
        (progn
          (if (not (> (save-excursion (forward-line 1) (point))
                      calculate-cil-indent-last-sexp))
	      (progn (goto-char calculate-cil-indent-last-sexp)
		     (beginning-of-line)
		     (parse-partial-sexp (point)
					 calculate-cil-indent-last-sexp 0 t)))
	  ;; Indent under the list or under the first sexp on the same
	  ;; line as calculate-lisp-indent-last-sexp.  Note that first
	  ;; thing on that line has to be complete sexp since we are
          ;; inside the innermost containing sexp.
          (backward-prefix-chars)
          (current-column))
      (let ((function (buffer-substring (point)
					(progn (forward-sexp 1) (point))))
	    method)
	(setq method (or (function-get (intern-soft function)
                                       'cil-indent-function)
			 (get (intern-soft function) 'lisp-indent-hook)))
	(cond ((or (eq method 'defun)
		   (and (null method)
			(> (length function) 3)
			(string-match "\\`def" function)))
	       (cil-indent-defform state indent-point))
	      ((integerp method)
	       (cil-indent-specform method state
				    indent-point normal-indent))
	      (method
	       (funcall method indent-point state)))))))

(defcustom cil-body-indent 2
  "Number of columns to indent the second line of a `(def...)' form."
  :group 'cil
  :type 'integer)
(put 'cil-body-indent 'safe-local-variable 'integerp)

(defun cil-indent-specform (count state indent-point normal-indent)
  (let ((containing-form-start (elt state 1))
        (i count)
        body-indent containing-form-column)
    ;; Move to the start of containing form, calculate indentation
    ;; to use for non-distinguished forms (> count), and move past the
    ;; function symbol.  cil-indent-function guarantees that there is at
    ;; least one word or symbol character following open paren of containing
    ;; form.
    (goto-char containing-form-start)
    (setq containing-form-column (current-column))
    (setq body-indent (+ cil-body-indent containing-form-column))
    (forward-char 1)
    (forward-sexp 1)
    ;; Now find the start of the last form.
    (parse-partial-sexp (point) indent-point 1 t)
    (while (and (< (point) indent-point)
                (condition-case ()
                    (progn
                      (setq count (1- count))
                      (forward-sexp 1)
                      (parse-partial-sexp (point) indent-point 1 t))
                  (error nil))))
    ;; Point is sitting on first character of last (or count) sexp.
    (if (> count 0)
        ;; A distinguished form.  If it is the first or second form use double
        ;; cil-body-indent, else normal indent.  With cil-body-indent bound
        ;; to 2 (the default), this just happens to work the same with if as
        ;; the older code, but it makes unwind-protect, condition-case,
        ;; with-output-to-temp-buffer, et. al. much more tasteful.  The older,
        ;; less hacked, behavior can be obtained by replacing below with
        ;; (list normal-indent containing-form-start).
        (if (<= (- i count) 1)
            (list (+ containing-form-column (* 2 lisp-body-indent))
                  containing-form-start)
	  (list normal-indent containing-form-start))
      ;; A non-distinguished form.  Use body-indent if there are no
      ;; distinguished forms and this is the first undistinguished form,
      ;; or if this is the first undistinguished form and the preceding
      ;; distinguished form has indentation at least as great as body-indent.
      (if (or (and (= i 0) (= count 0))
              (and (= count 0) (<= body-indent normal-indent)))
          body-indent
	normal-indent))))

(defun cil-indent-defform (state _indent-point)
  (goto-char (car (cdr state)))
  (forward-line 1)
  (if (> (point) (car (cdr (cdr state))))
      (progn
	(goto-char (car (cdr state)))
	(+ cil-body-indent (current-column)))))

;; (put 'progn 'cil-indent-function 0), say, causes progn to be indented
;; like defun if the first form is placed on the next line, otherwise
;; it is indented like any other form (i.e. forms line up under first).

(put 'autoload 'cil-indent-function 'defun) ;Elisp
(put 'progn 'cil-indent-function 0)
(put 'prog1 'cil-indent-function 1)
(put 'prog2 'cil-indent-function 2)
(put 'save-excursion 'cil-indent-function 0)      ;Elisp
(put 'save-restriction 'cil-indent-function 0)    ;Elisp
(put 'save-current-buffer 'cil-indent-function 0) ;Elisp
(put 'let 'cil-indent-function 1)
(put 'let* 'cil-indent-function 1)
(put 'while 'cil-indent-function 1)
(put 'if 'cil-indent-function 2)
(put 'catch 'cil-indent-function 1)
(put 'condition-case 'cil-indent-function 2)
(put 'handler-case 'cil-indent-function 1) ;CL
(put 'handler-bind 'cil-indent-function 1) ;CL
(put 'unwind-protect 'cil-indent-function 1)
(put 'with-output-to-temp-buffer 'cil-indent-function 1)

(defun indent-sexp (&optional endpos)
  "Indent each line of the list starting just after point.
If optional arg ENDPOS is given, indent each line, stopping when
ENDPOS is encountered."
  (interactive)
  (let* ((parse-state (cil-indent-initial-state)))
    ;; We need a marker because we modify the buffer
    ;; text preceding endpos.
    (setq endpos (copy-marker
                  (if endpos endpos
                    ;; Get error now if we don't have a complete sexp
                    ;; after point.
                    (save-excursion (forward-sexp 1) (point)))))
    (save-excursion
      (while (let ((indent (cil-indent-calc-next parse-state))
                   (ppss (cil-indent-state-ppss parse-state)))
               ;; If the line contains a comment indent it now with
               ;; `indent-for-comment'.
               (when (and (nth 4 ppss) (<= (nth 8 ppss) endpos))
                 (save-excursion
                   (goto-char (cil-indent-state-ppss-point parse-state))
                   (indent-for-comment)
                   (setf (cil-indent-state-ppss-point parse-state)
                         (line-end-position))))
               (when (< (point) endpos)
                 ;; Indent the next line, unless it's blank, or just a
                 ;; comment (we will `indent-for-comment' the latter).
                 (skip-chars-forward " \t")
                 (unless (or (eolp) (not indent)
                             (eq (char-syntax (char-after)) ?<))
                   (indent-line-to indent))
                 t))))
    (move-marker endpos nil)))

(defun indent-pp-sexp (&optional arg)
  "Indent each line of the list starting just after point, or prettyprint it.
A prefix argument specifies pretty-printing."
  (interactive "P")
  (if arg
      (save-excursion
        (save-restriction
          (narrow-to-region (point) (progn (forward-sexp 1) (point)))
          (pp-buffer)
          (goto-char (point-max))
          (if (eq (char-before) ?\n)
              (delete-char -1)))))
  (indent-sexp))

;;;; CIL paragraph filling commands.

(defcustom emacs-cil-docstring-fill-column 65
  "Value of `fill-column' to use when filling a docstring.
Any non-integer value means do not use a different value of
`fill-column' when filling docstrings."
  :type '(choice (integer)
                 (const :tag "Use the current `fill-column'" t))
  :group 'cil)
(put 'emacs-cil-docstring-fill-column 'safe-local-variable
     (lambda (x) (or (eq x t) (integerp x))))

(defun cil-fill-paragraph (&optional justify)
  "Like \\[fill-paragraph], but handle Emacs CIL comments and docstrings.
If any of the current line is a comment, fill the comment or the
paragraph of it that point is in, preserving the comment's indentation
and initial semicolons."
  (interactive "P")
  (or (fill-comment-paragraph justify)
      ;; Since fill-comment-paragraph returned nil, that means we're not in
      ;; a comment: Point is on a program line; we are interested
      ;; particularly in docstring lines.
      ;;
      ;; We bind `paragraph-start' and `paragraph-separate' temporarily.  They
      ;; are buffer-local, but we avoid changing them so that they can be set
      ;; to make `forward-paragraph' and friends do something the user wants.
      ;;
      ;; `paragraph-start': The `(' in the character alternative and the
      ;; left-singlequote plus `(' sequence after the \\| alternative prevent
      ;; sexps and backquoted sexps that follow a docstring from being filled
      ;; with the docstring.  This setting has the consequence of inhibiting
      ;; filling many program lines that are not docstrings, which is sensible,
      ;; because the user probably asked to fill program lines by accident, or
      ;; expecting indentation (perhaps we should try to do indenting in that
      ;; case).  The `;' and `:' stop the paragraph being filled at following
      ;; comment lines and at keywords (e.g., in `defcustom').  Left parens are
      ;; escaped to keep font-locking, filling, & paren matching in the source
      ;; file happy.  The `:' must be preceded by whitespace so that keywords
      ;; inside of the docstring don't start new paragraphs (Bug#7751).
      ;;
      ;; `paragraph-separate': A clever regexp distinguishes the first line of
      ;; a docstring and identifies it as a paragraph separator, so that it
      ;; won't be filled.  (Since the first line of documentation stands alone
      ;; in some contexts, filling should not alter the contents the author has
      ;; chosen.)  Only the first line of a docstring begins with whitespace
      ;; and a quotation mark and ends with a period or (rarely) a comma.
      ;;
      ;; The `fill-column' is temporarily bound to
      ;; `emacs-cil-docstring-fill-column' if that value is an integer.
      (let ((paragraph-start
             (concat paragraph-start
                     "\\|\\s-*\\([(;\"]\\|\\s-:\\|`(\\|#'(\\)"))
	    (paragraph-separate
	     (concat paragraph-separate "\\|\\s-*\".*[,\\.]$"))
            (fill-column (if (and (integerp emacs-cil-docstring-fill-column)
                                  (derived-mode-p 'emacs-lisp-mode))
                             emacs-cil-docstring-fill-column
                           fill-column)))
	(fill-paragraph justify))
      ;; Never return nil.
      t))

(defun indent-code-rigidly (start end arg &optional nochange-regexp)
  "Indent all lines of code, starting in the region, sideways by ARG columns.
Does not affect lines starting inside comments or strings, assuming that
the start of the region is not inside them.
Called from a program, takes args START, END, COLUMNS and NOCHANGE-REGEXP.
The last is a regexp which, if matched at the beginning of a line,
means don't indent that line."
  (interactive "r\np")
  (let (state)
    (save-excursion
      (goto-char end)
      (setq end (point-marker))
      (goto-char start)
      (or (bolp)
	  (setq state (parse-partial-sexp (point)
					  (progn
					    (forward-line 1) (point))
					  nil nil state)))
      (while (< (point) end)
	(or (car (nthcdr 3 state))
	    (and nochange-regexp
		 (looking-at nochange-regexp))
	    ;; If line does not start in string, indent it
	    (let ((indent (current-indentation)))
	      (delete-region (point) (progn (skip-chars-forward " \t") (point)))
	      (or (eolp)
		  (indent-to (max 0 (+ indent arg)) 0))))
	(setq state (parse-partial-sexp (point)
					(progn
					  (forward-line 1) (point))
					nil nil state))))))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.cil\\'" . cil-mode))

(provide 'cil-mode)

;;; cil-mode.el ends here