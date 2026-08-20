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

(defn fetch-agents [on-success on-error]
  (get "/agents" nil on-success on-error))

(defn create-agent [data on-success on-error]
  (post "/agents" data on-success on-error))

(defn update-agent [id data on-success on-error]
  (put (str "/agents/" id) data on-success on-error))

(defn delete-agent [id on-success on-error]
  (delete (str "/agents/" id) on-success on-error))

(defn fetch-agent-shapes [id on-success on-error]
  (get (str "/agents/" id "/shapes") nil on-success on-error))

(defn create-agent-shape [id on-success on-error]
  (post (str "/agents/" id "/shapes") {} on-success on-error))

(defn revoke-agent-shape [id shape-id on-success on-error]
  (delete (str "/agents/" id "/shapes/" shape-id) on-success on-error))

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

(defn fetch-board-activity [board-id params on-success on-error]
  (get (str "/boards/" board-id "/activity") params on-success on-error))

(defn fetch-all-activity [params on-success on-error]
  (get "/activity" params on-success on-error))

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

(defn fetch-boards [on-success on-error]
  (get "/boards" nil on-success on-error))

(defn create-board [data on-success on-error]
  (post "/boards" data on-success on-error))

(defn fetch-board [id on-success on-error]
  (get (str "/boards/" id) nil on-success on-error))

(defn update-board [id data on-success on-error]
  (put (str "/boards/" id) data on-success on-error))

(defn delete-board [id on-success on-error]
  (delete (str "/boards/" id) on-success on-error))

(defn fetch-board-members [id on-success on-error]
  (get (str "/boards/" id "/members") nil on-success on-error))

(defn add-board-member [id member-type member-id on-success on-error]
  (post (str "/boards/" id "/members")
        {:member_type member-type :member_id member-id}
        on-success on-error))

(defn remove-board-member [id member-type member-id on-success on-error]
  (delete (str "/boards/" id "/members/" member-type "/" member-id)
          on-success on-error))

(defn create-board-status [id data on-success on-error]
  (post (str "/boards/" id "/statuses") data on-success on-error))

(defn update-board-status [id status-id data on-success on-error]
  (put (str "/boards/" id "/statuses/" status-id) data on-success on-error))

(defn delete-board-status [id status-id on-success on-error]
  (delete (str "/boards/" id "/statuses/" status-id) on-success on-error))

(defn fetch-board-transitions [id on-success on-error]
  (get (str "/boards/" id "/transitions") nil on-success on-error))

(defn add-board-transition [id from-code to-code on-success on-error]
  (post (str "/boards/" id "/transitions")
        {:from_code from-code :to_code to-code}
        on-success on-error))

(defn remove-board-transition [id from-code to-code on-success on-error]
  (delete (str "/boards/" id "/transitions/" from-code "/" to-code)
          on-success on-error))
