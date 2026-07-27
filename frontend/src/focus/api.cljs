(ns focus.api
  (:require [ajax.core :as ajax]))

(def base-url "/api")

(defn request [method path & [{:keys [params on-success on-error]}]]
  (ajax/ajax-request
   {:method method
    :uri (str base-url path)
    :format (ajax/json-request-format)
    :response-format (ajax/json-response-format {:keywords? true})
    :params params
    :handler on-success
    :error-handler on-error}))

(defn fetch-issues [params on-success on-error]
  (request :get "/issues" {:params params
                           :on-success on-success
                           :on-error on-error}))

(defn fetch-issue [id on-success on-error]
  (request :get (str "/issues/" id)
           {:on-success on-success
            :on-error on-error}))

(defn create-issue [data on-success on-error]
  (request :post "/issues" {:params data
                            :on-success on-success
                            :on-error on-error}))

(defn update-issue [id data on-success on-error]
  (request :put (str "/issues/" id)
           {:params data
            :on-success on-success
            :on-error on-error}))

(defn delete-issue [id on-success on-error]
  (request :delete (str "/issues/" id)
           {:on-success on-success
            :on-error on-error}))

(defn search-issues [query on-success on-error]
  (request :get "/issues/search" {:params {:q query}
                                  :on-success on-success
                                  :on-error on-error}))

(defn fetch-users [on-success on-error]
  (request :get "/users" {:on-success on-success
                          :on-error on-error}))

(defn create-user [data on-success on-error]
  (request :post "/users" {:params data
                           :on-success on-success
                           :on-error on-error}))

(defn fetch-labels [on-success on-error]
  (request :get "/labels" {:on-success on-success
                           :on-error on-error}))

(defn create-label [data on-success on-error]
  (request :post "/labels" {:params data
                            :on-success on-success
                            :on-error on-error}))

(defn fetch-comments [issue-id on-success on-error]
  (request :get (str "/issues/" issue-id "/comments")
           {:on-success on-success
            :on-error on-error}))

(defn create-comment [issue-id data on-success on-error]
  (request :post (str "/issues/" issue-id "/comments")
           {:params data
            :on-success on-success
            :on-error on-error}))

(defn fetch-activity [issue-id on-success on-error]
  (request :get (str "/issues/" issue-id "/activity")
           {:on-success on-success
            :on-error on-error}))

(defn fetch-webhooks [on-success on-error]
  (request :get "/webhooks" {:on-success on-success
                             :on-error on-error}))

(defn create-webhook [data on-success on-error]
  (request :post "/webhooks" {:params data
                              :on-success on-success
                              :on-error on-error}))
