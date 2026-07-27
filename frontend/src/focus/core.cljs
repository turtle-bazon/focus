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
  (rdom/render [focus.views/main-panel] (.getElementById js/document "app")))

(defn init []
  (rf/dispatch-sync [:initialize-db])
  (rf/dispatch [:fetch-issues {}])
  (rf/dispatch [:fetch-users])
  (rf/dispatch [:fetch-labels])
  (ws/connect)
  (mount-root))

(goog.object/set js/window "init" init)
