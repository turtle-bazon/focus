(ns focus.server
  (:require [ring.middleware.defaults :refer [wrap-defaults site-defaults]]
            [ring.middleware.cors :refer [wrap-cors]]
            [ring.util.response :as response]))

(defn handler [request]
  (let [path (:uri request)]
    (cond
      (= path "/")
      (response/resource-response "public/index.html")

      (.startsWith path "/api")
      nil

      :else
      (response/resource-response (str "public" path)))))

(def app
  (-> handler
      (wrap-defaults (assoc-in site-defaults [:security :anti-forgery] false))
      (wrap-cors :access-control-allow-origin [#".*"]
                 :access-control-allow-methods [:get :post :put :delete :options])))
