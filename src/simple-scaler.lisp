;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: SIMPLE-SCALER; Base: 10 -*-
;;;
;;; Copyright (C) 2022  Anthony Green <green@redhat.com>
;;;
;;; This program is free software: you can redistribute it and/or
;;; modify it under the terms of the GNU Affero General Public License
;;; as published by the Free Software Foundation, either version 3 of
;;; the License, or (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Affero General Public License for more details.
;;;
;;; You should have received a copy of the GNU Affero General Public
;;; License along with this program.  If not, see
;;; <http://www.gnu.org/licenses/>.

;; Top level for simple-scaler

(in-package :simple-scaler)

;; ----------------------------------------------------------------------------
;; Machinery for managing the execution of the server.

(defvar *shutdown-cv* (bt:make-condition-variable))
(defvar *server-lock* (bt:make-lock))

;; ----------------------------------------------------------------------------

(defvar *config* nil)
(defvar *max-nodes* 0)
(defvar *name-template* "EMPTY-")
(defvar *resource-group* nil)

;; ----------------------------------------------------------------------------
;; The port of the server.  Define this in your config.ini files.

(defvar *server-port* nil)

;; ----------------------------------------------------------------------------
;; API routes

;; Readiness probe.
(easy-routes:defroute health ("/health") ()
  "ready")

(defvar *etcd* nil)

(defun get-active-change-time ()
  (parse-integer (or (cl-etcd:get-etcd "active-change-time" *etcd*) "0")))

(defun get-last-change-time ()
  (parse-integer (cl-etcd:get-etcd "last-change-time" *etcd*)))

(defun get-ready-count ()
  (parse-integer
   (inferior-shell:run/s
    (format nil "bash -c 'KUBECONFIG=/etc/simple-scaler/kubeconfig oc get nodes | grep \" Ready\" | grep ~A | wc -l'" *name-template*))))

(defun get-target-count ()
  (parse-integer (or (cl-etcd:get-etcd "target-count" *etcd*)
                     (inferior-shell:run/s
                      (format nil "bash -c 'KUBECONFIG=/etc/simple-scaler/kubeconfig oc get nodes | grep \" Ready\" | grep ~A | wc -l'" *name-template*)))))

(defun get-vm-count ()
  (parse-integer
   (inferior-shell:run/s
    (format nil "bash -c 'az vm list -g ~A | grep diskSize | grep [0-9] | wc -l'" *resource-group*))))

(defun get-status ()
  (let ((ready-count (get-ready-count))
        (target-count (get-target-count))
        (vm-count (get-vm-count)))
    (if *test-without-azure*
        (format nil "{ \"target\": 0, \"ready\": 0, \"vms\": 0, \"max\": 0, \"active-change-timer\": 0, \"last-change-timer\": 0 }~%")
        (format nil "{ \"target\": ~A, \"ready\": ~A, \"vms\": ~A, \"max\": ~A, \"active-change-timer\": ~A, \"last-change-timer\": ~A }~%"
                target-count
                ready-count
                vm-count
                *max-nodes*
                (if (not (and (eq target-count vm-count) (eq target-count ready-count))) (- (get-universal-time) (get-active-change-time)) 0)
                (if (and (eq target-count vm-count) (eq ready-count vm-count)) (- (get-universal-time) (get-last-change-time)) 0)))))

(easy-routes:defroute index ("/") ()
  (get-status))

(easy-routes:defroute set-target ("/set-target") (target)
  (log:info target)
  (let ((proposed-target (parse-integer target :junk-allowed t))
        (current-target (get-target-count)))
    (if (and (>= proposed-target 0) (<= proposed-target *max-nodes*))
        (if (not (eq proposed-target current-target))
            (progn
              (setf (cl-etcd:get-etcd "active-change-time" *etcd*) (format nil "~A" (get-universal-time)))
              (setf (cl-etcd:get-etcd "target-count" *etcd*) (format nil "~A" proposed-target)))))
    (get-status)))

;; ----------------------------------------------------------------------------

(defvar *sp-appid*)
(defvar *sp-password*)
(defvar *tenant*)

(defun az-login ()
  (run-with-retry
   (format nil "az login --service-principal --username ~A --password ~A --tenant ~A"
           *sp-appid* *sp-password* *tenant*)))

(defun make-vm-id-base ()
  (unless *test-without-azure*
    (let ((id (cdr (assoc :ID (json:decode-json-from-string (inferior-shell:run/s (format nil "az vm show -g ~A --name ~A1" *resource-group* *name-template*)))))))
      (subseq id 0 (- (length id) 1)))))

;; ----------------------------------------------------------------------------
;; HTTP server control

(defparameter *handler* nil)

(defmacro stop-server (&key (handler '*handler*))
  "Shutdown the HTTP handler"
  `(hunchentoot:stop ,handler))

(defvar *leader?* nil)
(defvar *test-without-azure* nil)

(defun run-with-retry (cmd)
  "Try running CMD up to 5 times, waiting longer between each retry,
to account for intermittent network problems."
  (log:info cmd)
  (flet ((%run-with-retry (cmd)
           (handler-case
               (inferior-shell:run cmd)
             (error (c)
               (progn
                 (log:info "error> ~A" c)
                 t)))))
    (loop for i from 1 upto 5
          until (not (%run-with-retry cmd))
          do (progn (log:info "retry #~A" i) (sleep (* i 2)))
          finally (when (eq i 6) (log:error "failed cmd: ~A" cmd)))))

;; This method is called when I become leader.
(defun become-leader (etcd)
  (log:info t "**** I AM THE LEADER ***********")
  (setf *leader?* t)

  (let ((last-change-time (cl-etcd:get-etcd "last-change-time" etcd)))
    (unless last-change-time
      (setf (cl-etcd:get-etcd "last-change-time" etcd) (format nil "~A" (get-universal-time)))))

  (let ((vm-id-base (make-vm-id-base)))
    (loop
      while *leader?*
      do (progn
           (unless *test-without-azure*
             (let ((ready-count (get-ready-count))
                   (target-count (get-target-count))
                   (vm-count (get-vm-count))
                   (ids ""))

               (when (eq ready-count vm-count)

                 (when (> target-count ready-count)
                   (log:info "GROWING to ~A" target-count)
                   (loop for i from (+ ready-count 1) upto target-count
                         do (setf ids (format nil "~A ~A~A" ids vm-id-base i)))
	           (run-with-retry (format nil "az vm start --ids ~A" ids))
                   (setf (cl-etcd:get-etcd "last-change-time" etcd) (format nil "~A" (get-universal-time))))

                 (when (< target-count ready-count)
                   (log:info "SHRINKING to ~A" target-count)
                   (loop for i from (+ target-count 1) upto ready-count
                         do (run-with-retry (format nil "KUBECONFIG=/etc/simple-scaler/kubeconfig oc adm cordon ~A~A" *name-template* i)))
                   (loop for i from (+ target-count 1) upto ready-count
                         do (progn
                              (run-with-retry (format nil "KUBECONFIG=/etc/simple-scaler/kubeconfig oc adm drain ~A~A --ignore-daemonsets --delete-emptydir-data --force" *name-template* i))
                              (run-with-retry (format nil "KUBECONFIG=/etc/simple-scaler/kubeconfig oc delete node ~A~A" *name-template* i))))
                   (loop for i from (+ target-count 1) upto ready-count
                         do (setf ids (format nil "~A ~A~A" ids vm-id-base i)))
	           (run-with-retry (format nil "az vm stop --ids ~A" ids))
	           (run-with-retry (format nil "az vm deallocate --ids ~A" ids))
                   (setf (cl-etcd:get-etcd "last-change-time" etcd) (format nil "~A" (get-universal-time))))))

             (sleep 10))))))

;; This method is called when I become a follower.
(defun become-follower (etcd)
  (log:info "**** I AM A FOLLOWER ***********")
  (setf *leader?* nil))

(defun start-server (&optional (config-ini "/etc/simple-scaler/config.ini"))

  (bt:with-lock-held (*server-lock*)

    (setf hunchentoot:*catch-errors-p* t)
    (setf hunchentoot:*show-lisp-errors-p* t)
    (setf hunchentoot:*show-lisp-backtraces-p* t)

    (log:info "Starting simple-scaler.")

    ;; Read the user configuration settings.
    (setf *config*
  	  (if (fad:file-exists-p config-ini)
	      (cl-toml:parse
	       (alexandria:read-file-into-string config-ini
					         :external-format :latin-1))
	      (make-hash-table)))

    (flet ((get-config-value (key)
	     (let ((value (or (gethash key *config*)
			      (error "config does not contain key '~A'" key))))
	       ;; Some of the users of these values are very strict
	       ;; when it comes to string types... I'm looking at you,
	       ;; SB-BSD-SOCKETS:GET-HOST-BY-NAME.
	       (if (subtypep (type-of value) 'vector)
		   (coerce value 'simple-string)
		   value))))

      ;; Extract any config.ini settings here.
      (setf *server-port* (get-config-value "server-port"))

      (let ((az-config (gethash "azure" *config*)))
        (if az-config
            (progn
              (setf *max-nodes* (gethash "max-nodes" az-config))
              (setf *sp-appid* (gethash "sp-appid" az-config))
              (setf *sp-password* (gethash "sp-password" az-config))
              (setf *tenant* (gethash "tenant" az-config))
              (setf *name-template* (gethash "name-template" az-config))
              (setf *resource-group* (gethash "resource-group" az-config))
              (az-login))
            (setf *test-without-azure* t)))

      (log:info "Starting server")

      (setf *print-pretty* nil)
      (setf *handler* (hunchentoot:start (make-instance 'easy-routes:routes-acceptor :port *server-port*)))

      (cl-etcd:with-etcd (etcd (gethash "etcd" *config*)
                               :on-leader #'become-leader
                               :on-follower #'become-follower)
        (setf *etcd* etcd)
        (bt:condition-wait *shutdown-cv* *server-lock*)))))
