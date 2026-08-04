(ns focus.core
  (:require [reagent.dom :as rdom]
            [re-frame.core :as rf]
            [goog.object]
            [secretary.core :as secretary]
            [focus.handlers]
            [focus.subs]
            [focus.views]
            [focus.api :as api]
            [focus.ws :as ws]))

(defn navigate-to [path]
  (when-not (= (.-pathname js/window.location) path)
    (.pushState js/window.history nil "" path))
  (secretary/dispatch! path))

(defn set-url [path]
  (when-not (= (.-pathname js/window.location) path)
    (.pushState js/window.history nil "" path)))

(secretary/defroute "/" []
  (rf/dispatch [:set-view :board]))

(secretary/defroute "/boards/:id" [id]
  (rf/dispatch [:set-view :board])
  (rf/dispatch [:fetch-current-board (js/parseInt id)]))

(secretary/defroute "/boards/:id/activity" [id]
  (rf/dispatch [:set-view :board-activity])
  (rf/dispatch [:fetch-current-board (js/parseInt id)])
  (rf/dispatch [:fetch-board-activity (js/parseInt id)]))

(secretary/defroute "/tickets/:id" [id]
  (rf/dispatch [:set-active-tab :comments])
  (rf/dispatch [:fetch-ticket-detail (js/parseInt id)])
  (rf/dispatch [:set-view :detail]))

(secretary/defroute "/tickets/:id/activity" [id]
  (rf/dispatch [:set-active-tab :activity])
  (rf/dispatch [:fetch-ticket-detail (js/parseInt id)])
  (rf/dispatch [:set-view :detail]))

(secretary/defroute "/settings" []
  (rf/dispatch [:set-view :settings])
  (rf/dispatch [:fetch-settings-data]))

(defn mount-root []
  (let [app-el (.getElementById js/document "app")]
    (set! (.. app-el -style -display) "block")
    (rdom/render [focus.views/main-panel] app-el)))

(defn on-popstate [_]
  (secretary/dispatch! (.-pathname js/window.location)))

(defn init []
  (rf/dispatch-sync [:initialize-db])
  (rf/dispatch [:fetch-app-info])
  (rf/dispatch [:check-auth])
  (.addEventListener js/window "popstate" on-popstate)
  (secretary/dispatch! (.-pathname js/window.location))
  (mount-root))

(defn init-board []
  (rf/dispatch [:fetch-boards])
  (rf/dispatch [:fetch-users])
  (rf/dispatch [:fetch-labels])
  (rf/dispatch [:fetch-groups])
  (ws/connect))

(goog.object/set js/window "init" init)
(goog.object/set js/window "initBoard" init-board)
(goog.object/set js/window "navigateTo" navigate-to)
(goog.object/set js/window "setUrl" set-url)
