(ns focus.api
  (:require [ajax.core :as ajax]))

(def base-url "/api")

(defn get [path params on-success on-error]
  (ajax/GET (str base-url path)
            {:params params
             :response-format (ajax/json-response-format {:keywords? true})
             :handler on-success
             :error-handler on-error}))

(defn post [path params on-success on-error]
  (ajax/POST (str base-url path)
             {:params params
              :format (ajax/json-request-format)
              :response-format (ajax/json-response-format {:keywords? true})
              :handler on-success
              :error-handler on-error}))

(defn put [path params on-success on-error]
  (ajax/PUT (str base-url path)
            {:params params
             :format (ajax/json-request-format)
             :response-format (ajax/json-response-format {:keywords? true})
             :handler on-success
             :error-handler on-error}))

(defn delete [path on-success on-error]
  (ajax/DELETE (str base-url path)
               {:response-format (ajax/json-response-format {:keywords? true})
                :handler on-success
                :error-handler on-error}))

(defn fetch-app-info [on-success on-error]
  (get "/app/info" nil on-success on-error))

(defn fetch-auth-me [on-success on-error]
  (get "/auth/me" nil on-success on-error))

(defn auth-logout [on-success on-error]
  (post "/auth/logout" nil on-success on-error))

(defn fetch-issues [params on-success on-error]
  (get "/issues" params on-success on-error))

(defn fetch-issue [id on-success on-error]
  (get (str "/issues/" id) nil on-success on-error))

(defn create-issue [data on-success on-error]
  (post "/issues" data on-success on-error))

(defn update-issue [id data on-success on-error]
  (put (str "/issues/" id) data on-success on-error))

(defn delete-issue [id on-success on-error]
  (delete (str "/issues/" id) on-success on-error))

(defn search-issues [query on-success on-error]
  (get "/issues/search" {:q query} on-success on-error))

(defn fetch-users [on-success on-error]
  (get "/users" nil on-success on-error))

(defn create-user [data on-success on-error]
  (post "/users" data on-success on-error))

(defn fetch-labels [on-success on-error]
  (get "/labels" nil on-success on-error))

(defn create-label [data on-success on-error]
  (post "/labels" data on-success on-error))

(defn fetch-comments [issue-id on-success on-error]
  (get (str "/issues/" issue-id "/comments") nil on-success on-error))

(defn create-comment [issue-id data on-success on-error]
  (post (str "/issues/" issue-id "/comments") data on-success on-error))

(defn fetch-activity [issue-id on-success on-error]
  (get (str "/issues/" issue-id "/activity") nil on-success on-error))

(defn fetch-webhooks [on-success on-error]
  (get "/webhooks" nil on-success on-error))

(defn create-webhook [data on-success on-error]
  (post "/webhooks" data on-success on-error))
