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

(defn fetch-tickets [params on-success on-error]
  (get "/tickets" params on-success on-error))

(defn fetch-ticket [id on-success on-error]
  (get (str "/tickets/" id) nil on-success on-error))

(defn create-ticket [data on-success on-error]
  (post "/tickets" data on-success on-error))

(defn update-ticket [id data on-success on-error]
  (put (str "/tickets/" id) data on-success on-error))

(defn delete-ticket [id on-success on-error]
  (delete (str "/tickets/" id) on-success on-error))

(defn search-tickets [query on-success on-error]
  (get "/tickets/search" {:q query} on-success on-error))

(defn fetch-users [on-success on-error]
  (get "/users" nil on-success on-error))

(defn create-user [data on-success on-error]
  (post "/users" data on-success on-error))

(defn fetch-labels [on-success on-error]
  (get "/labels" nil on-success on-error))

(defn create-label [data on-success on-error]
  (post "/labels" data on-success on-error))

(defn fetch-comments [ticket-id params on-success on-error]
  (get (str "/tickets/" ticket-id "/comments") params on-success on-error))

(defn create-comment [ticket-id data on-success on-error]
  (post (str "/tickets/" ticket-id "/comments") data on-success on-error))

(defn fetch-activity [ticket-id params on-success on-error]
  (get (str "/tickets/" ticket-id "/activity") params on-success on-error))

(defn fetch-webhooks [on-success on-error]
  (get "/webhooks" nil on-success on-error))

(defn create-webhook [data on-success on-error]
  (post "/webhooks" data on-success on-error))

(defn fetch-groups [on-success on-error]
  (get "/groups" nil on-success on-error))

(defn create-group [data on-success on-error]
  (post "/groups" data on-success on-error))

(defn update-group [id data on-success on-error]
  (put (str "/groups/" id) data on-success on-error))

(defn delete-group [id on-success on-error]
  (delete (str "/groups/" id) on-success on-error))

(defn fetch-group-members [id on-success on-error]
  (get (str "/groups/" id "/members") nil on-success on-error))

(defn add-group-member [group-id user-id on-success on-error]
  (post (str "/groups/" group-id "/members") {:user_id user-id} on-success on-error))

(defn remove-group-member [group-id user-id on-success on-error]
  (delete (str "/groups/" group-id "/members/" user-id) on-success on-error))

(defn fetch-ticket-observers [ticket-id on-success on-error]
  (get (str "/tickets/" ticket-id "/observers") nil on-success on-error))

(defn add-ticket-observer [ticket-id observer-type observer-id on-success on-error]
  (post (str "/tickets/" ticket-id "/observers")
        {:observer_type observer-type :observer_id observer-id}
        on-success on-error))

(defn remove-ticket-observer [ticket-id observer-type observer-id on-success on-error]
  (delete (str "/tickets/" ticket-id "/observers/" observer-type "/" observer-id)
          on-success on-error))
