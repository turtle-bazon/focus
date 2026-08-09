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

(ns focus.handlers
  (:require [re-frame.core :as rf]
            [focus.api :as api]
            [focus.i18n :as i18n]))

(defn- total-key [status priority]
  (str status "|" (or priority "medium")))

(def ^:private in-flight-pages (atom #{}))

(defn- page-request [key status priority page limit params]
  (when-not (contains? @in-flight-pages key)
    (swap! in-flight-pages conj key)
    (api/fetch-tickets params
     (fn [response]
       (swap! in-flight-pages disj key)
       (rf/dispatch [:set-priority-load key status priority page limit
                     (:tickets response) (:total response)]))
     (fn [error]
       (swap! in-flight-pages disj key)
       (rf/dispatch [:set-error (str "Failed to load column: " error)])))))

(defn- adjust-ticket-total [db status priority delta]
  (let [key (total-key status priority)]
    (update-in db [:ticket-total key]
               (fn [n] (max 0 (+ (or n 0) delta))))))

(defn- move-ticket-total [db old-status old-priority new-status new-priority]
  (let [old-key (total-key old-status old-priority)
        new-key (total-key new-status new-priority)]
    (if (= old-key new-key)
      db
      (-> db
          (adjust-ticket-total old-status old-priority -1)
          (adjust-ticket-total new-status new-priority +1)))))

(rf/reg-event-db
 :initialize-db
 (fn [_ _]
   {:current-view :landing
    :auth nil
    :app-info nil
    :tickets []
    :users []
    :labels []
    :groups []
    :group-members {}
    :ticket-observers {}
    :boards []
    :current-board-id nil
    :current-board nil
    :current-ticket nil
    :comments []
    :comments-total 0
    :comments-loading false
    :activity []
    :activity-total 0
    :activity-loading false
    :board-activity []
    :board-activity-total 0
    :board-activity-loading false
    :all-activity []
    :all-activity-total 0
    :all-activity-loading false
    :ticket-page {}
    :ticket-total {}
    :search-query ""
    :loading true
    :error nil
     :active-tab :comments
     :comment-form-version 0
     :confirm-modal nil
     :locale (i18n/get-saved-locale)}))

(rf/reg-event-db
 :set-view
 (fn [db [_ view]]
   (assoc db :current-view view)))

(rf/reg-event-db
 :set-active-tab
 (fn [db [_ tab]]
   (assoc db :active-tab tab)))

;;; Auth events

(rf/reg-event-fx
 :fetch-app-info
 (fn [{:keys [db]} _]
   (api/fetch-app-info
    (fn [response]
      (rf/dispatch [:set-app-info response]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch app info: " error)])))
   {:db db}))

(rf/reg-event-db
 :set-app-info
 (fn [db [_ info]]
   (assoc db :app-info info)))

(rf/reg-event-fx
 :check-auth
 (fn [{:keys [db]} _]
   (api/fetch-auth-me
    (fn [response]
      (rf/dispatch [:set-auth response]))
    (fn [error]
      (rf/dispatch [:set-auth {:authenticated false}])))
   {:db (assoc db :loading true)}))

(rf/reg-event-db
 :set-auth
 (fn [db [_ response]]
   (let [authenticated (:authenticated response)
         path (.-pathname js/window.location)]
     (when authenticated
       (js/initBoard))
      (assoc db
             :auth response
             :loading false
              :current-view (if authenticated
                              (cond
                                 (re-matches #"/tickets/\d+(/.*)?" path) :detail
                                 (re-matches #"/activity" path) :all-activity
                                 (re-matches #"/boards/\d+/activity" path) :board-activity
                                (= path "/settings") :settings
                                :else :board)
                              :landing)))))

(rf/reg-event-fx
 :logout
 (fn [{:keys [db]} _]
   (api/auth-logout
    (fn [_]
      (rf/dispatch [:set-auth {:authenticated false}]))
    (fn [error]
      (rf/dispatch [:set-error (str "Logout failed: " error)])))
   {:db db}))

(rf/reg-event-db
 :set-error
 (fn [db [_ error]]
   (js/console.log "focus error:", error)
   (assoc db :error error :loading false)))

(rf/reg-event-db
 :clear-error
 (fn [db _]
   (assoc db :error nil)))

(rf/reg-event-fx
 :load-priority
 (fn [{:keys [db]} [_ status priority limit]]
   (let [key (str status "|" priority)
         limit-val (or limit 20)
         loaded (count (filter #(and (= (:status %) status)
                                     (= (:priority %) priority))
                               (:tickets db)))
         page (max 1 (+ (quot loaded limit-val) 1))
         params {:board_id (:current-board-id db)
                 :status status
                 :priority priority
                 :limit limit-val
                 :page page}]
     (page-request key status priority page limit-val params)
     {:db db})))

(rf/reg-event-fx
 :load-initial-columns
 (fn [{:keys [db]} [_ statuses]]
   (let [priorities ["high" "medium" "low"]]
     (doseq [status statuses]
       (doseq [priority priorities]
         (let [key (str (:code status) "|" priority)]
           (when-not (contains? @in-flight-pages key)
             (page-request key (:code status) priority 1
                           (:load_count status)
                           {:board_id (:current-board-id db)
                            :status (:code status)
                            :priority priority
                            :limit (:load_count status)
                            :page 1}))))))
   {:db (assoc db :ticket-page {} :ticket-total {})}))

(rf/reg-event-db
 :set-priority-load
 (fn [db [_ key status priority page limit tickets total]]
   (let [existing (:tickets db)
         other (remove #(and (= (:status %) status)
                             (= (:priority %) priority))
                       existing)
         same (filter #(and (= (:status %) status)
                            (= (:priority %) priority))
                      existing)
         new-ids (set (map :id tickets))
         same-keep (remove #(contains? new-ids (:id %)) same)
         merged (vec (concat other same-keep tickets))
         group-loaded (count (filter #(and (= (:status %) status)
                                           (= (:priority %) priority))
                                     merged))
         final-total (if (or (empty? tickets)
                             (< (count tickets) limit))
                       group-loaded
                       total)]
     (assoc db
            :tickets merged
            :ticket-page (assoc (:ticket-page db) key page)
            :ticket-total (assoc (:ticket-total db) key final-total)
            :loading false :error nil))))

(rf/reg-event-fx
 :load-all-columns
 (fn [{:keys [db]} [_ statuses]]
   (rf/dispatch [:load-initial-columns statuses])
   {:db db}))

(rf/reg-event-fx
 :fetch-tickets
 (fn [{:keys [db]} [_ params]]
   (let [params (cond-> (or params {})
                  (:current-board-id db) (assoc :board_id (:current-board-id db)))]
     (api/fetch-tickets params
      (fn [response]
        (rf/dispatch [:set-tickets (:tickets response)]))
      (fn [error]
        (rf/dispatch [:set-error (str "Failed to fetch tickets: " error)]))))
    {:db db}))

(rf/reg-event-db
 :set-tickets
 (fn [db [_ tickets]]
   (assoc db :tickets tickets :loading false :error nil)))

(rf/reg-event-fx
 :create-ticket
 (fn [{:keys [db]} [_ data]]
 (api/create-ticket (assoc data :board_id (:current-board-id db))
     (fn [response]
(rf/dispatch [:add-ticket {:id (:id response)
                                  :title (:title data)
                                  :description (:description data)
                                  :priority (:priority data)
                                  :assignee_id (:assignee_id data)
                                  :assignee_type (:assignee_type data)
                                  :board_id (:current-board-id db)
                                  :status "open"}
                     (:current-board-id db)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to create ticket: " error)])))
   {:db db}))

(rf/reg-event-fx
 :update-ticket
 (fn [{:keys [db]} [_ id data]]
   (api/update-ticket id data
    (fn [response]
      (rf/dispatch [:fetch-tickets {}]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to update ticket: " error)])))
   {:db (assoc db :loading true)}))

(rf/reg-event-fx
:update-ticket-status
  (fn [{:keys [db]} [_ id status]]
    (let [tickets (:tickets db)
          target (first (filter #(= (:id %) id) tickets))
          old-status (:status target)
          old-priority (:priority target)
          updated (mapv (fn [i]
                          (if (= (:id i) id)
                              (assoc i :status status)
                              i))
                        tickets)]
     (api/update-ticket id {:status status}
      (fn [_]
        (api/fetch-activity id {:limit 20 :offset 0}
         (fn [resp] (rf/dispatch [:set-activity-initial (:activity resp) (:total resp)]))
         (fn [_])))
      (fn [error]
        (rf/dispatch [:set-error (str "Failed to update ticket: " error)])
        (rf/dispatch [:fetch-tickets {}])))
     {:db (-> db
              (move-ticket-total old-status old-priority status old-priority)
              (assoc :tickets updated))})))

(rf/reg-event-fx
:reorder-ticket
  (fn [{:keys [db]} [_ id status priority position]]
    (let [tickets (:tickets db)
          moved (first (filter #(= (:id %) id) tickets))
          old-status (:status moved)
          old-priority (:priority moved)
          moved-with-status (assoc moved :status status :priority priority)
         without (vec (remove #(= (:id %) id) tickets))
         same-group (filter #(and (= (:status %) status) (= (:priority %) priority)) without)
         other (vec (remove #(and (= (:status %) status) (= (:priority %) priority)) without))
         before (vec (take position same-group))
         after (vec (drop position same-group))
         reindexed-group (vec (map-indexed (fn [idx ticket]
                                             (assoc ticket :position idx))
                                           (concat before [moved-with-status] after)))
         all-tickets (concat other reindexed-group)
         current-ticket (:current-ticket db)
         new-current (when (and current-ticket (= (:id current-ticket) id))
                       (assoc current-ticket :status status :priority priority))]
       (api/update-ticket id (cond-> {:status status :priority priority}
                              position (assoc :position position))
        (fn [_]
          (api/fetch-activity id {:limit 20 :offset 0}
           (fn [resp] (rf/dispatch [:set-activity-initial (:activity resp) (:total resp)]))
           (fn [_])))
      (fn [error]
        (rf/dispatch [:set-error (str "Failed to reorder ticket: " error)])
        (rf/dispatch [:fetch-tickets {}])))
{:db (-> db
               (move-ticket-total old-status old-priority status priority)
               (assoc :tickets (vec all-tickets)
                      :current-ticket (or new-current current-ticket)))})))

(rf/reg-event-fx
:update-ticket-field
  (fn [{:keys [db]} [_ id field value]]
    (let [tickets (:tickets db)
          target (first (filter #(= (:id %) id) tickets))
          old-status (:status target)
          old-priority (:priority target)
          new-status (if (= field :status) value old-status)
          new-priority (if (= field :priority) value old-priority)
          updated-tickets (mapv (fn [t] (if (= (:id t) id) (assoc t field value) t)) tickets)
          current-ticket (:current-ticket db)
          new-current (when (and current-ticket (= (:id current-ticket) id))
                        (assoc current-ticket field value))]
        (api/update-ticket id {field value}
         (fn [_]
           (api/fetch-activity id {:limit 20 :offset 0}
            (fn [resp] (rf/dispatch [:set-activity-initial (:activity resp) (:total resp)]))
            (fn [_])))
        (fn [error]
          (rf/dispatch [:set-error (str "Failed to update ticket: " error)])
          (rf/dispatch [:fetch-tickets {}])))
     {:db (-> db
              (move-ticket-total old-status old-priority new-status new-priority)
              (assoc :tickets updated-tickets
                     :current-ticket (or new-current current-ticket)))})))

(rf/reg-event-fx
 :delete-ticket
 (fn [{:keys [db]} [_ id]]
   (api/delete-ticket id
    (fn [response]
      (rf/dispatch [:fetch-tickets {}]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to delete ticket: " error)])))
   {:db (assoc db :loading true)}))

(rf/reg-event-fx
 :search-tickets
 (fn [{:keys [db]} [_ query]]
   (if (empty? query)
     (do
       (rf/dispatch [:fetch-tickets {}])
       {:db (assoc db :search-query "")})
     (do
       (api/search-tickets query
        (fn [response]
          (rf/dispatch [:set-tickets (:tickets response)]))
        (fn [error]
          (rf/dispatch [:set-error (str "Failed to search: " error)])))
       {:db (assoc db :search-query query)}))))

(rf/reg-event-db
 :set-search-query
 (fn [db [_ query]]
   (assoc db :search-query query)))

(rf/reg-event-fx
 :fetch-users
 (fn [{:keys [db]} _]
   (api/fetch-users
    (fn [response]
      (rf/dispatch [:set-users (:users response)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch users: " error)])))
   {:db db}))

(rf/reg-event-db
 :set-users
 (fn [db [_ users]]
   (assoc db :users users)))

(rf/reg-event-fx
 :fetch-labels
 (fn [{:keys [db]} _]
   (api/fetch-labels
    (fn [response]
      (rf/dispatch [:set-labels (:labels response)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch labels: " error)])))
   {:db db}))

(rf/reg-event-db
 :set-labels
 (fn [db [_ labels]]
   (assoc db :labels labels)))

(rf/reg-event-fx
 :fetch-ticket-detail
 (fn [{:keys [db]} [_ id]]
   (api/fetch-ticket id
    (fn [response]
      (rf/dispatch [:set-current-ticket response]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch ticket: " error)])))
   (api/fetch-comments id {:limit 20 :offset 0}
    (fn [response]
      (rf/dispatch [:set-comments-initial (:comments response) (:total response)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch comments: " error)])))
   (api/fetch-activity id {:limit 20 :offset 0}
    (fn [response]
      (rf/dispatch [:set-activity-initial (:activity response) (:total response)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch activity: " error)])))
   (api/fetch-ticket-observers id
    (fn [response]
      (rf/dispatch [:set-ticket-observers id (:observers response)]))
    (fn [_]))
   {:db (assoc db :current-ticket nil :comments [] :activity []
               :comments-total 0 :comments-loading false
               :activity-total 0 :activity-loading false)}))

(rf/reg-event-db
 :set-current-ticket
 (fn [db [_ ticket]]
   (assoc db :current-ticket ticket)))

(rf/reg-event-db
 :set-comments-initial
 (fn [db [_ comments total]]
   (assoc db :comments (vec comments) :comments-total total :comments-loading false)))

(rf/reg-event-db
 :set-activity-initial
 (fn [db [_ activity total]]
   (assoc db :activity (vec activity) :activity-total total :activity-loading false)))

(rf/reg-event-db
 :set-comments-more
 (fn [db [_ comments]]
   (update db :comments #(into (vec %) comments))))

(rf/reg-event-db
 :set-activity-more
 (fn [db [_ activity]]
   (update db :activity #(into (vec %) activity))))

(rf/reg-event-db
 :set-comments-loading
 (fn [db [_ loading]]
   (assoc db :comments-loading loading)))

(rf/reg-event-db
 :set-activity-loading
 (fn [db [_ loading]]
   (assoc db :activity-loading loading)))

(rf/reg-event-fx
 :create-comment
 (fn [{:keys [db]} [_ ticket-id data]]
   (api/create-comment ticket-id data
    (fn [response]
      (let [comment {:id (:id response)
                     :user_id (:user_id data)
                     :body (:body data)
                     :created_at (.toISOString (js/Date.))}]
        (rf/dispatch [:add-comment comment ticket-id])
        (rf/dispatch [:clear-comment-form])
        (api/fetch-activity ticket-id {:limit 20 :offset 0}
         (fn [resp] (rf/dispatch [:set-activity-initial (:activity resp) (:total resp)]))
         (fn [_]))))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to create comment: " error)])))
    {:db db}))

(rf/reg-event-db
 :clear-comment-form
 (fn [db _]
   (update db :comment-form-version inc)))

(rf/reg-event-fx
 :load-more-comments
 (fn [{:keys [db]} [_ ticket-id]]
   (when-not (:comments-loading db)
     (let [offset (count (:comments db))]
       (rf/dispatch [:set-comments-loading true])
       (api/fetch-comments ticket-id {:limit 20 :offset offset}
        (fn [response]
          (rf/dispatch [:set-comments-more (:comments response)])
          (rf/dispatch [:set-comments-loading false]))
        (fn [_error]
          (rf/dispatch [:set-comments-loading false])))))
   {:db db}))

(rf/reg-event-fx
 :load-more-activity
 (fn [{:keys [db]} [_ ticket-id]]
   (when-not (:activity-loading db)
     (let [offset (count (:activity db))]
       (rf/dispatch [:set-activity-loading true])
       (api/fetch-activity ticket-id {:limit 20 :offset offset}
        (fn [response]
          (rf/dispatch [:set-activity-more (:activity response)])
          (rf/dispatch [:set-activity-loading false]))
        (fn [_error]
          (rf/dispatch [:set-activity-loading false])))))
   {:db db}))

(rf/reg-event-fx
 :fetch-board-activity
 (fn [{:keys [db]} [_ board-id]]
   (let [id (or board-id (:current-board-id db))]
     (rf/dispatch [:set-board-activity-loading true])
     (api/fetch-board-activity id {:limit 20 :offset 0}
      (fn [response]
        (rf/dispatch [:set-board-activity-initial (:activity response) (:total response)]))
      (fn [error]
        (rf/dispatch [:set-board-activity-loading false])
        (rf/dispatch [:set-error (str "Failed to fetch board activity: " error)])))
     {:db db})))

(rf/reg-event-db
 :set-board-activity-initial
 (fn [db [_ activity total]]
   (assoc db :board-activity (vec activity) :board-activity-total total
          :board-activity-loading false)))

(rf/reg-event-db
 :set-board-activity-more
 (fn [db [_ activity]]
   (update db :board-activity #(into (vec %) activity))))

(rf/reg-event-db
 :set-board-activity-loading
 (fn [db [_ loading]]
   (assoc db :board-activity-loading loading)))

(rf/reg-event-db
 :clear-board-activity
 (fn [db _]
   (assoc db :board-activity [] :board-activity-total 0 :board-activity-loading false)))

(rf/reg-event-fx
 :load-more-board-activity
 (fn [{:keys [db]} [_ board-id]]
   (when-not (:board-activity-loading db)
     (let [id (or board-id (:current-board-id db))
           offset (count (:board-activity db))]
       (rf/dispatch [:set-board-activity-loading true])
       (api/fetch-board-activity id {:limit 20 :offset offset}
        (fn [response]
          (rf/dispatch [:set-board-activity-more (:activity response)])
          (rf/dispatch [:set-board-activity-loading false]))
         (fn [_error]
           (rf/dispatch [:set-board-activity-loading false])))))
   {:db db}))

(rf/reg-event-fx
 :fetch-all-activity
 (fn [{:keys [db]} _]
   (rf/dispatch [:set-all-activity-loading true])
   (api/fetch-all-activity {:limit 20 :offset 0}
    (fn [response]
      (rf/dispatch [:set-all-activity-initial (:activity response) (:total response)]))
    (fn [error]
      (rf/dispatch [:set-all-activity-loading false])
      (rf/dispatch [:set-error (str "Failed to fetch activity: " error)])))
   {:db db}))

(rf/reg-event-db
 :set-all-activity-initial
 (fn [db [_ activity total]]
   (assoc db :all-activity (vec activity) :all-activity-total total
          :all-activity-loading false)))

(rf/reg-event-db
 :set-all-activity-more
 (fn [db [_ activity]]
   (update db :all-activity #(into (vec %) activity))))

(rf/reg-event-db
 :set-all-activity-loading
 (fn [db [_ loading]]
   (assoc db :all-activity-loading loading)))

(rf/reg-event-fx
 :load-more-all-activity
 (fn [{:keys [db]} _]
   (when-not (:all-activity-loading db)
     (let [offset (count (:all-activity db))]
       (rf/dispatch [:set-all-activity-loading true])
       (api/fetch-all-activity {:limit 20 :offset offset}
        (fn [response]
          (rf/dispatch [:set-all-activity-more (:activity response)])
          (rf/dispatch [:set-all-activity-loading false]))
        (fn [_error]
          (rf/dispatch [:set-all-activity-loading false])))))
   {:db db}))

(rf/reg-event-db
 :ws-update-ticket
 (fn [db [_ ticket board-id]]
   (if (and board-id (not= board-id (:current-board-id db)))
     db
     (let [existing (:tickets db)
           old (first (filter #(= (:id %) (:id ticket)) existing))
           old-status (:status old)
           old-priority (:priority old)
           new-status (:status ticket)
           new-priority (:priority ticket)
           updated-tickets (map (fn [i]
                                  (if (= (:id i) (:id ticket))
                                      ticket
                                      i))
                                existing)]
       (-> db
           (move-ticket-total old-status old-priority new-status new-priority)
           (assoc :tickets (vec updated-tickets)))))))

(rf/reg-event-db
 :ws-add-activity
 (fn [db [_ activity]]
   (let [board-id (:board_id activity)
         ticket-id (:ticket_id activity)
         current-board (:current-board-id db)
         add-dedup (fn [items item]
                     (if (some #(= (:id %) (:id item)) items)
                       items
                       (vec (cons item items))))]
     (cond-> db
       (and (seq (:board-activity db)) (= board-id current-board))
       (-> (update :board-activity add-dedup activity)
           (update :board-activity-total inc))
       (seq (:all-activity db))
       (-> (update :all-activity add-dedup activity)
           (update :all-activity-total inc))
       (and (seq (:activity db)) (= ticket-id (:id (:current-ticket db))))
       (-> (update :activity add-dedup activity)
           (update :activity-total inc))))))

(rf/reg-event-db
 :add-ticket
 (fn [db [_ ticket board-id]]
   (if (or (and board-id (not= board-id (:current-board-id db)))
           (some #(= (:id %) (:id ticket)) (:tickets db)))
     db
     (let [tickets (:tickets db)
           without (vec (remove #(= (:id %) (:id ticket)) tickets))]
       (-> db
           (adjust-ticket-total (:status ticket) (:priority ticket) 1)
           (assoc :tickets (vec (cons ticket without))))))))

(rf/reg-event-db
 :remove-ticket
 (fn [db [_ ticket-id board-id]]
   (if (or (and board-id (not= board-id (:current-board-id db)))
           (not (some #(= (:id %) ticket-id) (:tickets db))))
     db
     (let [target (first (filter #(= (:id %) ticket-id) (:tickets db)))]
       (-> db
           (adjust-ticket-total (:status target) (:priority target) -1)
           (update :tickets (fn [tickets]
                              (vec (remove #(= (:id %) ticket-id) tickets)))))))))

(rf/reg-event-db
 :add-comment
 (fn [db [_ comment ticket-id]]
   (if (and (= (:current-view db) :detail)
            (= (:id (:current-ticket db)) ticket-id))
      (-> db
          (update :comments #(vec (cons comment %)))
          (update :comments-total inc))
     db)))

;;; Group events

(rf/reg-event-fx
 :fetch-groups
 (fn [{:keys [db]} _]
   (api/fetch-groups
    (fn [response]
      (let [groups (:groups response)]
        (doseq [group groups]
          (rf/dispatch [:fetch-group-members (:id group)]))
        (rf/dispatch [:set-groups groups])))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch groups: " error)])))
   {:db db}))

(rf/reg-event-db
 :set-groups
 (fn [db [_ groups]]
   (assoc db :groups groups)))

(rf/reg-event-fx
 :create-group
 (fn [{:keys [db]} [_ data]]
   (api/create-group data
    (fn [_]
      (rf/dispatch [:fetch-groups]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to create group: " error)])))
   {:db db}))

(rf/reg-event-fx
 :update-group
 (fn [{:keys [db]} [_ id data]]
   (api/update-group id data
    (fn [_]
      (rf/dispatch [:fetch-groups]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to update group: " error)])))
   {:db db}))

(rf/reg-event-fx
 :delete-group
 (fn [{:keys [db]} [_ id]]
   (api/delete-group id
    (fn [_]
      (rf/dispatch [:fetch-groups]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to delete group: " error)])))
   {:db db}))

(rf/reg-event-fx
 :fetch-group-members
 (fn [{:keys [db]} [_ group-id]]
   (api/fetch-group-members group-id
    (fn [response]
      (rf/dispatch [:set-group-members group-id (:members response)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch group members: " error)])))
   {:db db}))

(rf/reg-event-db
 :set-group-members
 (fn [db [_ group-id members]]
   (assoc-in db [:group-members group-id] members)))

(rf/reg-event-fx
 :add-group-member
 (fn [{:keys [db]} [_ group-id user-id]]
   (api/add-group-member group-id user-id
    (fn [_]
      (rf/dispatch [:fetch-group-members group-id]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to add member: " error)])))
   {:db db}))

(rf/reg-event-fx
 :remove-group-member
  (fn [{:keys [db]} [_ group-id user-id]]
    (api/remove-group-member group-id user-id
     (fn [_]
       (rf/dispatch [:fetch-group-members group-id]))
     (fn [error]
       (rf/dispatch [:set-error (str "Failed to remove member: " error)])))
    {:db db}))

(rf/reg-event-fx
 :manage-group-members
 (fn [{:keys [db]} [_ group-id group-name]]
   (rf/dispatch [:fetch-group-members group-id])
   {:db (assoc db :group-members-modal {:group-id group-id :group-name group-name})}))

(rf/reg-event-db
 :close-group-members-modal
 (fn [db _]
   (assoc db :group-members-modal nil)))

(rf/reg-event-db
 :open-create-group-modal
 (fn [db _]
   (assoc db :create-group-modal {:open? true :name "" :member-ids #{}})))

(rf/reg-event-db
 :close-create-group-modal
 (fn [db _]
   (assoc db :create-group-modal nil)))

(rf/reg-event-db
 :set-create-group-name
 (fn [db [_ name]]
   (assoc-in db [:create-group-modal :name] name)))

(rf/reg-event-db
 :add-create-group-member
 (fn [db [_ user-id]]
   (assoc-in db [:create-group-modal :member-ids] (conj (get-in db [:create-group-modal :member-ids] #{}) user-id))))

(rf/reg-event-db
 :remove-create-group-member
 (fn [db [_ user-id]]
   (assoc-in db [:create-group-modal :member-ids] (disj (get-in db [:create-group-modal :member-ids] #{}) user-id))))

(rf/reg-event-fx
 :create-group-from-modal
 (fn [{:keys [db]} _]
   (let [name (get-in db [:create-group-modal :name])
         member-ids (get-in db [:create-group-modal :member-ids] #{})]
     (when-not (clojure.string/blank? name)
       (api/post "/groups" {:name name}
        (fn [response]
          (doseq [uid member-ids]
            (api/add-group-member (:id response) uid
              (fn [_] (rf/dispatch [:fetch-group-members (:id response)]))
              (fn [_])))
          (rf/dispatch [:fetch-groups])
          (rf/dispatch [:close-create-group-modal]))
        (fn [error]
          (rf/dispatch [:set-error (str "Failed to create group: " error)]))))
     {:db db})))

;;; Ticket observer events

(rf/reg-event-fx
 :fetch-ticket-observers
 (fn [{:keys [db]} [_ ticket-id]]
   (api/fetch-ticket-observers ticket-id
    (fn [response]
      (rf/dispatch [:set-ticket-observers ticket-id (:observers response)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch observers: " error)])))
   {:db db}))

(rf/reg-event-db
 :set-ticket-observers
 (fn [db [_ ticket-id observers]]
   (assoc-in db [:ticket-observers ticket-id] observers)))

(rf/reg-event-fx
 :add-ticket-observer
 (fn [{:keys [db]} [_ ticket-id observer-type observer-id]]
   (api/add-ticket-observer ticket-id observer-type observer-id
    (fn [_]
      (rf/dispatch [:fetch-ticket-observers ticket-id]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to add observer: " error)])))
   {:db db}))

(rf/reg-event-fx
 :remove-ticket-observer
 (fn [{:keys [db]} [_ ticket-id observer-type observer-id]]
    (api/remove-ticket-observer ticket-id observer-type observer-id
     (fn [_]
       (rf/dispatch [:fetch-ticket-observers ticket-id]))
     (fn [error]
       (rf/dispatch [:set-error (str "Failed to remove observer: " error)])))
    {:db db}))

;;; Settings handlers

(rf/reg-event-fx
 :fetch-settings-data
 (fn [{:keys [db]} _]
   (rf/dispatch [:fetch-users])
   (rf/dispatch [:fetch-groups])
   {:db (assoc db :settings-tab "users")}))

(rf/reg-event-db
 :set-settings-tab
 (fn [db [_ tab]]
   (assoc db :settings-tab tab)))

(rf/reg-event-fx
 :update-user-role
 (fn [{:keys [db]} [_ user-id role]]
   (api/put (str "/users/" user-id) {:role role}
     (fn [_]
       (rf/dispatch [:fetch-users]))
     (fn [error]
       (rf/dispatch [:set-error (str "Failed to update user: " error)])))
   {:db db}))

(rf/reg-event-fx
 :delete-group-settings
 (fn [{:keys [db]} [_ group-id]]
   (api/delete (str "/groups/" group-id)
     (fn [_]
       (rf/dispatch [:fetch-groups]))
     (fn [error]
       (rf/dispatch [:set-error (str "Failed to delete group: " error)])))
   {:db db}))

(rf/reg-event-fx
 :delete-user
 (fn [{:keys [db]} [_ user-id]]
   (api/delete (str "/users/" user-id)
     (fn [_]
       (rf/dispatch [:fetch-users]))
      (fn [error]
        (rf/dispatch [:set-error (str "Failed to delete user: " error)])))
    {:db db}))

(rf/reg-event-fx
 :undelete-user
 (fn [{:keys [db]} [_ user-id]]
   (api/post (str "/users/" user-id "/undelete") {}
     (fn [_]
       (rf/dispatch [:fetch-users]))
      (fn [error]
        (rf/dispatch [:set-error (str "Failed to restore user: " error)])))
    {:db db}))

(rf/reg-event-db
 :show-confirm-modal
 (fn [db [_ modal]]
   (assoc db :confirm-modal modal)))

(rf/reg-event-db
 :close-confirm-modal
 (fn [db _]
   (assoc db :confirm-modal nil)))

;;; Board events

(rf/reg-event-fx
 :fetch-boards
 (fn [{:keys [db]} _]
   (api/fetch-boards
    (fn [response]
      (rf/dispatch [:set-boards (:boards response)])
      (rf/dispatch [:fetch-current-board (:current-board-id db)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch boards: " error)])))
   {:db db}))

(rf/reg-event-db
 :set-boards
 (fn [db [_ boards]]
   (assoc db :boards boards)))

(rf/reg-event-fx
 :select-board
 (fn [{:keys [db]} [_ board]]
   (let [board (or board (first (:boards db)))
         view (:current-view db)]
     (when board
       (js/navigateTo (if (= view :board-activity)
                        (str "/boards/" (:id board) "/activity")
                        (str "/boards/" (:id board)))))
     {:db (assoc db :current-board-id (:id board)
                    :current-board (assoc (:current-board db) :id (:id board)))})))

(rf/reg-event-fx
 :fetch-current-board
 (fn [{:keys [db]} [_ board-id]]
   (let [id (or board-id (:current-board-id db)
                (:id (first (:boards db))))]
     (if id
(api/fetch-board id
        (fn [response]
          (rf/dispatch [:set-current-board response])
          (rf/dispatch [:load-all-columns (:statuses response)]))
         (fn [error]
           (rf/dispatch [:set-error (str "Failed to fetch board: " error)])))
        (rf/dispatch [:fetch-tickets {}]))
     {:db (assoc db :current-board-id id)})))

(rf/reg-event-fx
 :set-current-board
 (fn [{:keys [db]} [_ response]]
   (let [path (.-pathname js/window.location)]
     (when (= path "/")
       (js/setUrl (str "/boards/" (:id response))))
     {:db (assoc db
                 :current-board-id (:id response)
                 :current-board (select-keys response [:id :name :type :is_default :owner_id
                                                        :statuses :transitions]))})))

(rf/reg-event-fx
 :create-board
 (fn [{:keys [db]} [_ name type group-ids user-ids]]
   (api/create-board (cond-> {:name name :type (or type "personal")}
                       (seq group-ids) (assoc :group_ids group-ids)
                       (seq user-ids) (assoc :user_ids user-ids))
    (fn [response]
      (rf/dispatch [:fetch-boards])
      (let [id (:id response)]
        (rf/dispatch [:select-board {:id id}])
        (rf/dispatch [:fetch-current-board id])))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to create board: " error)])))
   {:db db}))

(rf/reg-event-fx
 :delete-board
 (fn [{:keys [db]} [_ id]]
   (api/delete (str "/boards/" id)
    (fn []
      (if (= (:current-board-id db) id)
        (rf/dispatch [:select-board nil])
        (rf/dispatch [:fetch-boards])))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to delete board: " error)])))
   {:db db}))

(rf/reg-event-fx
 :update-board
 (fn [{:keys [db]} [_ id data]]
    (api/update-board (or id (:current-board-id db)) data
     (fn [_response]
      (rf/dispatch [:fetch-boards])
      (rf/dispatch [:fetch-current-board (:current-board-id db)]))
     (fn [error]
      (rf/dispatch [:set-error (str "Failed to update board: " error)])))
   {:db db}))

(rf/reg-event-fx
 :add-board-status
 (fn [{:keys [db]} [_ data]]
   (api/create-board-status (:current-board-id db) data
    (fn []
      (rf/dispatch [:fetch-current-board (:current-board-id db)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to add status: " error)])))
   {:db db}))

(rf/reg-event-fx
 :update-board-status
 (fn [{:keys [db]} [_ status-id data]]
   (api/update-board-status (:current-board-id db) status-id data
    (fn []
      (rf/dispatch [:fetch-current-board (:current-board-id db)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to update status: " error)])))
   {:db db}))

(rf/reg-event-fx
 :remove-board-status
 (fn [{:keys [db]} [_ status-id]]
   (api/delete-board-status (:current-board-id db) status-id
    (fn []
      (rf/dispatch [:fetch-current-board (:current-board-id db)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to remove status: " error)])))
   {:db db}))

(rf/reg-event-fx
 :toggle-board-transition
 (fn [{:keys [db]} [h413 from-code to-code]]
   (let [lost (first (filter (fn [tr]
                               (and (= (:from_code tr) from-code)
                                    (= (:to_code tr) to-code)))
                             (:transitions (:current-board db))))]
     (if lost
       (api/remove-board-transition (:current-board-id db) from-code to-code
        (fn [] (rf/dispatch [:fetch-current-board (:current-board-id db)]))
        (fn [error] (rf/dispatch [:set-error (str "Failed to remove transition: " error)])))
       (api/add-board-transition (:current-board-id db) from-code to-code
        (fn [] (rf/dispatch [:fetch-current-board (:current-board-id db)]))
        (fn [error] (rf/dispatch [:set-error (str "Failed to add transition: " error)]))))
     {:db db})))

(rf/reg-event-fx
 :add-board-member
 (fn [{:keys [db]} [_ member-type member-id]]
   (api/add-board-member (:current-board-id db) member-type member-id
    (fn []
      (rf/dispatch [:fetch-current-board (:current-board-id db)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to add member: " error)])))
   {:db db}))

(rf/reg-event-fx
 :remove-board-member
 (fn [{:keys [db]} [_ member-type member-id]]
   (api/remove-board-member (:current-board-id db) member-type member-id
    (fn []
      (rf/dispatch [:fetch-current-board (:current-board-id db)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to remove member: " error)])))
   {:db db}))
