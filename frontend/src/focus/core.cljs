(ns focus.core
  (:require [reagent.dom :as rdom]
            [re-frame.core :as rf]
            [goog.object]
            [focus.handlers]
            [focus.subs]
            [focus.views]
            [focus.api :as api]
            [focus.ws :as ws]))

(defn mount-root []
  (let [app-el (.getElementById js/document "app")]
    (set! (.. app-el -style -display) "block")
    (rdom/render [focus.views/main-panel] app-el)))

(defn init []
  (rf/dispatch-sync [:initialize-db])
  (rf/dispatch [:fetch-app-info])
  (rf/dispatch [:check-auth])
  (mount-root))

(defn init-board []
  (rf/dispatch [:fetch-issues {}])
  (rf/dispatch [:fetch-users])
  (rf/dispatch [:fetch-labels])
  (ws/connect))

(goog.object/set js/window "init" init)
(goog.object/set js/window "initBoard" init-board)
