;; This file is part of Sheeple

;; message-dispatch.lisp
;;
;; Message execution and dispatch
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

(defun primary-message-p (message)
  (null (message-qualifiers message)))

(defun before-message-p (message)
  (when (member :before (message-qualifiers message))
    t))

(defun after-message-p (message)
  (when (member :after (message-qualifiers message))
    t))

(defun around-message-p (message)
  (when (member :around (message-qualifiers message))
    t))

(defun apply-buzzword (buzzword args)
  (let ((messages (find-applicable-messages buzzword
					    (sheepify-list args))))
    (apply-messages messages args)))

(defun apply-messages (messages args)
  (let ((around (find-if #'around-message-p messages))
	(primaries (remove-if-not #'primary-message-p messages)))
	  (when (null primaries)
	    (let ((name (message-name (car messages))))
	      (error 'no-primary-messages
		     :format-control 
		     "There are no primary messages for buzzword ~A When called with args:~%~S"
		     :format-args (list name args))))
    (if around
	(apply-message around args (remove around messages))
    	(let ((befores (remove-if-not #'before-message-p messages))
	      (afters (remove-if-not #'after-message-p messages)))
	  (dolist (before befores)
	    (apply-message before args nil))
	  (multiple-value-prog1
	      (apply-message (car primaries) args (cdr primaries))
	    (dolist (after (reverse afters))
	      (apply-message after args nil)))))))

(defun apply-message (message args next-messages)
  (let ((function (message-function message)))
    (funcall function args next-messages)))

(defun find-applicable-messages  (buzzword args &key (errorp t))
  "Returns the most specific message using SELECTOR and ARGS."
  (let ((selector (buzzword-name buzzword))
	(n (length args))
	(discovered-messages nil)
	(contained-applicable-messages nil))
    (loop 
       for arg in args
       for index upto (1- n)
       do (let ((curr-sheep-list (sheep-hierarchy-list arg)))
	    (loop
	       for curr-sheep in curr-sheep-list
	       for hierarchy-position upto (1- (length curr-sheep-list))
	       do (dolist (role (sheep-direct-roles curr-sheep))
		    (when (and (equal selector (role-name role)) ;(eql buzzword (role-buzzword role))
			       (= index (role-position role)))
			  (let ((curr-message (role-message-pointer role)))
			    (when (= n (length (message-lambda-list curr-message)))
			      (when (not (member curr-message
						 discovered-messages
						 :key #'message-container-message))
				(pushnew (contain-message curr-message) discovered-messages))
			      (let ((contained-message (find curr-message
							     discovered-messages
							     :key #'message-container-message)))
				(setf (elt (message-container-rank contained-message) index) 
				      hierarchy-position)
				(when (fully-specified-p (message-container-rank contained-message))
				  (pushnew contained-message contained-applicable-messages :test #'equalp))))))))))
    (if contained-applicable-messages
	(unbox-messages (sort-applicable-messages contained-applicable-messages))
	(when errorp
	  (error 'no-applicable-messages
		 :format-control
		 "There are no applicable messages for buzzword ~A when called with args:~%~S"
		 :format-args (list selector args))))))

(defun unbox-messages (messages)
  (mapcar #'message-container-message messages))

(defun sort-applicable-messages (message-list &key (rank-key #'<))
  (sort message-list rank-key
	:key (lambda (contained-message)
	       (calculate-rank-score (message-container-rank contained-message)))))

(defun contain-message (message)
  (make-message-container
   :message message
   :rank (make-array (length (message-lambda-list message))
		     :initial-element nil)))

(defstruct message-container
  message
  rank)

(defun fully-specified-p (rank)
  (loop for item across rank
     do (when (eql item nil)
	  (return-from fully-specified-p nil)))
  t)

(defun calculate-rank-score (rank)
  (let ((total 0))
    (loop for item across rank
       do (when (numberp item)
	    (incf total item)))
    total))
