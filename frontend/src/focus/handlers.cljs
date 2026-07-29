(ns focus.handlers
  (:require [re-frame.core :as rf]
            [focus.api :as api]
            [focus.i18n :as i18n]))

(rf/reg-event-db
 :initialize-db
 (fn [_ _]
   {:current-view :landing
    :auth nil
    :app-info nil
    :tickets []
    :users []
    :labels []
    :current-ticket nil
    :comments []
    :comments-total 0
    :comments-loading false
    :activity []
    :activity-total 0
    :activity-loading false
    :search-query ""
    :loading true
    :error nil
    :active-tab :comments
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
                             (if (re-matches #"/tickets/\d+(/.*)?" path) :detail :board)
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
   (assoc db :error error :loading false)))

(rf/reg-event-db
 :clear-error
 (fn [db _]
   (assoc db :error nil)))

(rf/reg-event-fx
 :fetch-tickets
 (fn [{:keys [db]} [_ params]]
   (api/fetch-tickets params
    (fn [response]
      (rf/dispatch [:set-tickets (:tickets response)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch tickets: " error)])))
   {:db db}))

(rf/reg-event-db
 :set-tickets
 (fn [db [_ tickets]]
   (assoc db :tickets tickets :loading false :error nil)))

(rf/reg-event-fx
 :create-ticket
 (fn [{:keys [db]} [_ data]]
   (api/create-ticket data
    (fn [response]
      (rf/dispatch [:add-ticket {:id (:id response)
                                :title (:title data)
                                :description (:description data)
                                :priority (:priority data)
                                :status "open"}]))
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
     {:db (assoc db :tickets updated)})))

(rf/reg-event-fx
 :reorder-ticket
 (fn [{:keys [db]} [_ id status priority position]]
   (let [tickets (:tickets db)
         moved (first (filter #(= (:id %) id) tickets))
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
     {:db (assoc db
                 :tickets (vec all-tickets)
                 :current-ticket (or new-current current-ticket))})))

(rf/reg-event-fx
 :update-ticket-field
 (fn [{:keys [db]} [_ id field value]]
   (let [tickets (:tickets db)
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
     {:db (assoc db
                 :tickets updated-tickets
                 :current-ticket (or new-current current-ticket))})))

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
        (api/fetch-activity ticket-id {:limit 20 :offset 0}
         (fn [resp] (rf/dispatch [:set-activity-initial (:activity resp) (:total resp)]))
         (fn [_]))))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to create comment: " error)])))
   {:db db}))

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

(rf/reg-event-db
 :ws-update-ticket
 (fn [db [_ ticket]]
   (let [tickets (:tickets db)
         updated-tickets (map (fn [i]
                                (if (= (:id i) (:id ticket))
                                    ticket
                                    i))
                              tickets)]
     (assoc db :tickets (vec updated-tickets)))))

(rf/reg-event-db
 :add-ticket
 (fn [db [_ ticket]]
   (let [tickets (:tickets db)
         without (vec (remove #(= (:id %) (:id ticket)) tickets))]
     (assoc db :tickets (vec (cons ticket without))))))

(rf/reg-event-db
 :remove-ticket
 (fn [db [_ ticket-id]]
   (update db :tickets (fn [tickets]
                         (vec (remove #(= (:id %) ticket-id) tickets))))))

(rf/reg-event-db
 :add-comment
 (fn [db [_ comment ticket-id]]
   (if (and (= (:current-view db) :detail)
            (= (:id (:current-ticket db)) ticket-id))
      (-> db
          (update :comments #(vec (cons comment %)))
          (update :comments-total inc))
     db)))
