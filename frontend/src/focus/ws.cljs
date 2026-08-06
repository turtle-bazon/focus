;; focus — ticket tracker
;; Copyright (C) 2026 Azamat S. Kalimoulline <turtle@bazon.ru>
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.
;;

(ns focus.ws
  (:require [re-frame.core :as rf]))

(def ws-url (str (if (= (.-protocol js/location) "https:") "wss:" "ws:")
                  "//" (.-host js/location)))
(defonce ws-connection (atom nil))

(defn on-message [event]
  (let [data (-> event .-data js/JSON.parse (js->clj :keywordize-keys true))
        msg-type (keyword (:type data))]
    (case msg-type
      :ticket-update (rf/dispatch [:ws-update-ticket (:data data)])
      :ticket-created (rf/dispatch [:add-ticket (:data data)])
      :ticket-deleted (rf/dispatch [:remove-ticket (:id data)])
      :comment-created (rf/dispatch [:add-comment (:data data) (:ticket-id data)])
      (println "Unknown message type:" msg-type))))

(defn on-open [_]
  (println "WebSocket connected"))

(declare connect)

(defn on-close [_]
  (println "WebSocket disconnected")
  (reset! ws-connection nil)
  (js/setTimeout connect 3000))

(defn on-error [error]
  (println "WebSocket error:" error))

(defn connect []
  (when-not @ws-connection
    (let [ws (js/WebSocket. ws-url)]
      (set! (.-onopen ws) on-open)
      (set! (.-onmessage ws) on-message)
      (set! (.-onclose ws) on-close)
      (set! (.-onerror ws) on-error)
      (reset! ws-connection ws))))

(defn disconnect []
  (when @ws-connection
    (.close @ws-connection)
    (reset! ws-connection nil)))
