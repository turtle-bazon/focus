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
    :groups []
    :group-members {}
    :ticket-observers {}
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
                                 :assignee_id (:assignee_id data)
                                 :assignee_type (:assignee_type data)
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

(rf/reg-event-db
 :show-confirm-modal
 (fn [db [_ modal]]
   (assoc db :confirm-modal modal)))

(rf/reg-event-db
 :close-confirm-modal
 (fn [db _]
   (assoc db :confirm-modal nil)))
