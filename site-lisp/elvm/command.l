;;; -*- mode:lisp; package:elvm -*-
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "elvm/package")
  (require "elvm/8cc")
  (require "elvm/elc"))

(in-package :elvm)

(export '(*include-path*
	  compile-c-to-eir
	  assemble-eir
	  ))

(defvar *include-path* nil)
(defvar *8cc-libc-path*
  (merge-pathnames "libc" (directory-namestring *load-pathname*)))

(defparameter *supported-target*
  '(("xl" . "xyzzy lisp")
    ("rb" . "Ruby")
    ("py" . "Python")
    ("js" . "JavaScript")
    ("el" . "Emacs Lisp")
    ("vim" . "VimScript")
    ("tex" . "TeX")
    ("cl" . "Common Lisp")
    ("sh" . "Bash")
    ("java" . "Java")
    ("c" . "C")
    ("x86" . "x86")
    ("i" . "C-INTERCAL")
    ("ws" . "Whitespace")
    ("piet" . "piet")
    ("pietasm" . "pietasm")
    ("bef" . "Befunge")
    ("bf" . "Brainf*ck")
    ("unl" . "Unlambda")
    ("eir" . "ELVM IR")))

(defmacro ensure-buffer (var)
  `(if (bufferp ,var) ,var
     (if (stringp ,var)
	 (setq ,var (or (find-buffer ,var)
			(error "Buffer not found: ~A" ,var)))
       (error (make-condition 'type-error
			      :datum ,var
			      :expected-type '(or buffer string))))))

(defun all-include-path ()
  (append *include-path* (list *8cc-libc-path*)))

(defun find-header-file (name wd)
  (if (string-match "^\\." name)
      (let ((path (merge-pathnames name wd)))
	(when (file-exist-p path)
	  path))
    (dolist (d (all-include-path))
      (let ((files (directory d :wild name :file-only t :recursive nil)))
	(when files
	  (return-from find-header-file (merge-pathnames (car files) d)))))))

(defun process-include (buf &optional used)
  (unless (bufferp buf) (setq buf (find-buffer buf)))
  (save-excursion
    (set-buffer buf)
    (goto-char 0)
    (let ((wd (directory-namestring (or (get-buffer-file-name buf)
					(get-buffer-alternate-file-name buf)
					"."))))
      (while (scan-buffer "#[ \t]*include[ \t]*[\"<]\\(.*?\\)[\">]" :regexp t)
	(let* ((hn (match-string 1))
	       (beg (match-beginning 0))
	       (end (match-end 0))
	       (path (find-header-file hn wd)))
	  (unless path
	    (error "File not found: ~A" hn))
	  (if (find path used :test 'string=)
	      (delete-region beg end)
	    (let ((tmpbuf (create-new-buffer "*elvm-cpp*")))
	      (unwind-protect
		  (progn
		    (set-buffer tmpbuf)
		    (set-buffer-alternate-file-name path tmpbuf)
		    (insert-file-contents path)
		    (process-include tmpbuf (cons path used))
		    (let ((s (buffer-substring 0 (point-max))))
		      (set-buffer buf)
		      (delete-region beg end)
		      (goto-char beg)
		      (insert s)))
		(delete-buffer tmpbuf)))))))))

(defun compile-c-to-eir (input-buffer output-buffer)
  (ensure-buffer input-buffer)
  (ensure-buffer output-buffer)
  (let ((tmpbuf (create-new-buffer " *elvm-8cc-tmp*")))
    (set-buffer-alternate-file-name (get-buffer-file-name input-buffer) tmpbuf)
    (save-excursion
      (set-buffer tmpbuf)
      (insert-buffer input-buffer)
      (erase-buffer output-buffer)
      (unwind-protect
	  (progn
	    (process-include tmpbuf)
	    (with-input-from-buffer (tmpbuf)
	      (with-output-to-buffer (output-buffer)
		(elvm.8cc:main))))
	(delete-buffer tmpbuf))))
  t)

(defun assemble-eir (target input-buffer output-buffer)
  (ensure-buffer input-buffer)
  (ensure-buffer output-buffer)
  (unless (find target *supported-target* :test 'string= :key #'car)
    (error "Unsupported target: ~A" target))
  (with-input-from-buffer (input-buffer)
    (with-open-stream (head (make-string-input-stream (concat target "\n")))
      (with-open-stream (is (make-concatenated-stream head *standard-input*))
	(erase-buffer output-buffer)
	(with-output-to-buffer (output-buffer)
	  (elvm.elc:main is)))))
  t)

(defun bytecompile-and-run-buffer (&optional (buf (selected-buffer)))
  (ensure-buffer buf)
  (let* ((filename (get-buffer-file-name buf))
	 (usetemp (null filename)))
    (when usetemp
      (setq filename (make-temp-file-name "xl-elvm" "tmp.l"))
      (save-excursion
	(set-buffer buf)
	(write-file filename)))
    (let ((lc (compile-file-pathname filename)))
      (unwind-protect
	  (progn
	    (with-open-stream (*standard-output* (make-string-output-stream))
	      (byte-compile-file filename))
	    (load lc))
	(when usetemp
	  (delete-file filename :if-does-not-exist :skip)
	  (delete-file lc :if-does-not-exist :skip))))
    (let ((p (find-package "elvm-compiled")))
      (unless p
	(error "package not found: elvm-compiled"))
      (let ((main (find-symbol "main" p)))
	(unless (and main (symbol-function main))
	  (error "elvm-compiled:main function not found"))
	(let ((out (get-buffer-create "*elvm-output*")))
	  (setup-temp-buffer out)
	  (erase-buffer out)
	  (with-input-from-string (i "")
	    (with-output-to-buffer (out)
	      (funcall main)))
	  (pop-to-buffer out)
	  (set-buffer-modified-p nil))))))

(defun read-target ()
  (let ((target (completing-read "Target: " (mapcar #'cdr *supported-target*)
				 :case-fold t
				 :default (cdar *supported-target*)
				 :must-match t)))
    (car (rassoc target *supported-target* :test 'string=))))


;;; user commands
(defun user::elvm-compile-buffer (srcbuf target)
  (interactive (list (read-exist-buffer-name "ELVM compile buffer: " :default (selected-buffer))
		     (read-target)))
  (let* ((filename (get-buffer-file-name srcbuf))
	 (eirbuf (create-new-buffer (concat (buffer-name srcbuf) ".eir"))))
    (compile-c-to-eir srcbuf eirbuf)
    (when filename
      (set-buffer-file-name (concat filename ".eir") eirbuf))
    (when (string= target "eir")
      (pop-to-buffer eirbuf)
      (return-from user::elvm-compile-buffer))
    (unwind-protect
	(user::elvm-assemble-buffer eirbuf target))
      (unless (deleted-buffer-p eirbuf)
	(delete-buffer eirbuf))))

(defun user::elvm-assemble-buffer (eirbuf target)
  (interactive (list (read-exist-buffer-name "ELVM assemble buffer: " :default (selected-buffer))
		     (read-target)))
  (let* ((filename (get-buffer-file-name eirbuf))
	 (ext (if (string= target "xl") "l" target))
	 (asmbuf (create-new-buffer (concat (buffer-name eirbuf) "." ext))))
    (assemble-eir target eirbuf asmbuf)
    (pop-to-buffer asmbuf)
    (when filename
      (set-buffer-file-name (concat filename "." ext)))
    (when (string= target "xl")
      (lisp-mode))))

(defun user::elvm-compile-file (srcfile target)
  (interactive (list (read-exist-file-name "ELVM compile file: "
				     :default (get-buffer-file-name (selected-buffer)))
		     (read-target)))
  (let ((eir (concat srcfile ".eir")))
    (with-open-file (is srcfile :direction :input)
      (with-open-file (os eir :direction :output
			  :if-does-not-exist :create
			  :if-exists :supersede)
	(elvm.8cc:main is os)))
    (if (string= target "eir")
	(find-file-other-window eir)
      (user::elvm-assemble-file eir target))))

(defun user::elvm-assemble-file (eirfile target)
  (interactive (list (read-exist-file-name "ELVM compile file: "
				     :default (get-buffer-file-name (selected-buffer)))
		     (read-target)))
  (let ((out (concat eirfile "." (if (string= target "xl") "l" target))))
    (with-open-file (fs eirfile :direction :input)
      (with-open-stream (head (make-string-input-stream (concat target "\n")))
	(with-open-stream (is (make-concatenated-stream head fs))
	  (with-open-file (os out :direction :output
			      :if-does-not-exist :create
			      :if-exists :supersede)
	    (elvm.elc:main is os)))))
    (find-file-other-window out)))

(defun user::elvm-compile-and-run-buffer (buf)
  (interactive "bELVM compile and run: ")
  (let ((eirbuf (create-new-buffer " *8cc-output*"))
	(lbuf (create-new-buffer " *elc-output*")))
    (unwind-protect
	(progn
	  (compile-c-to-eir buf eirbuf)
	  (assemble-eir "xl" eirbuf lbuf)
	  (if (string= (buffer-substring 0 40 lbuf)
		       "(defpackage :elvm-compiled (:use :lisp))")
	      (bytecompile-and-run-buffer lbuf)
	    (let ((errbuf (get-buffer-create "*elvm-error*")))
	      (erase-buffer errbuf)
	      (pop-to-buffer errbuf)
	      (insert "8cc output\n----------\n")
	      (insert-buffer eirbuf)
	      (goto-char (point-max))
	      (insert "----------\n\nelc output\n----------\n")
	      (insert-buffer lbuf)
	      (pop-to-buffer errbuf)
	      (set-buffer-modified-p nil))))
      (delete-buffer eirbuf)
      (delete-buffer lbuf))))

(provide "elvm/command")
