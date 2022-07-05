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

(asdf:defsystem #:simple-scaler
  :description "A simple OpenShift worker-node scaler for stretching into Azure"
  :author "Anthony Green <green@redhat.com>"
  :version "0"
  :serial t
  :components ((:file "package")
	       (:file "simple-scaler"))
  :depends-on (:cl-fad
               :easy-routes
               :cl-etcd
               :hunchentoot
               :cl-toml
               :inferior-shell
               :log4cl
               :str))
