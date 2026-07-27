(ns focus.ws
  (:require [re-frame.core :as rf]))

(def ws-url (str (if (= (.-protocol js/location) "https:") "wss:" "ws:")
                  "//" (.-host js/location)))
(defonce ws-connection (atom nil))

(defn on-message [event]
  (let [data (-> event .-data js/JSON.parse (js->clj :keywordize-keys true))
        msg-type (keyword (:type data))]
    (case msg-type
      :issue-update (rf/dispatch [:ws-update-issue (:data data)])
      :issue-created (rf/dispatch [:add-issue (:data data)])
      :issue-deleted (rf/dispatch [:remove-issue (:id data)])
      :comment-created (rf/dispatch [:add-comment (:data data) (:issue-id data)])
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
