;;; focus-cli — remote command-line client for Focus.
;;; Copyright (C) 2026 Azamat S. Kalimoulline <turtle@bazon.ru>
;;;
;;; This program is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by
;;; the Free Software Foundation, either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with this program.  If not, see <https://www.gnu.org/licenses/>.
;;;

(defsystem :focus-cli
  :name "focus-cli"
  :license "GPL-3.0-or-later"
  :version "0.0.2.1"
  :description "Remote command-line ticket client for Focus"
  :depends-on (#:focus)
  :build-operation "program-op"
  :build-pathname "build/focus-cli"
  :entry-point "focus:remote-main")