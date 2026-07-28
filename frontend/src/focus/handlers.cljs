(ns focus.handlers
  (:require [re-frame.core :as rf]
            [focus.api :as api]))

(rf/reg-event-db
 :initialize-db
 (fn [_ _]
   {:current-view :landing
    :auth nil
    :app-info nil
    :issues []
    :users []
    :labels []
    :current-issue nil
    :comments []
    :activity []
    :search-query ""
    :loading false
    :error nil}))

(rf/reg-event-db
 :set-view
 (fn [db [_ view]]
   (assoc db :current-view view)))

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
   (let [authenticated (:authenticated response)]
     (when authenticated
       (js/initBoard))
     (assoc db
            :auth response
            :loading false
            :current-view (if authenticated :board :landing)))))

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
 :fetch-issues
 (fn [{:keys [db]} [_ params]]
   (assoc db :loading true)
   (api/fetch-issues params
    (fn [response]
      (rf/dispatch [:set-issues (:issues response)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch issues: " error)])))
   {:db (assoc db :loading true)}))

(rf/reg-event-db
 :set-issues
 (fn [db [_ issues]]
   (assoc db :issues issues :loading false :error nil)))

(rf/reg-event-fx
 :create-issue
 (fn [{:keys [db]} [_ data]]
   (api/create-issue data
    (fn [response]
      (rf/dispatch [:fetch-issues {}]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to create issue: " error)])))
   {:db (assoc db :loading true)}))

(rf/reg-event-fx
 :update-issue
 (fn [{:keys [db]} [_ id data]]
   (api/update-issue id data
    (fn [response]
      (rf/dispatch [:fetch-issues {}]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to update issue: " error)])))
   {:db (assoc db :loading true)}))

(rf/reg-event-fx
 :update-issue-status
 (fn [{:keys [db]} [_ id status]]
   (api/update-issue id {:status status}
    (fn [response]
      (rf/dispatch [:fetch-issues {}]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to update issue: " error)])))
   {:db (assoc db :loading true)}))

(rf/reg-event-fx
 :delete-issue
 (fn [{:keys [db]} [_ id]]
   (api/delete-issue id
    (fn [response]
      (rf/dispatch [:fetch-issues {}]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to delete issue: " error)])))
   {:db (assoc db :loading true)}))

(rf/reg-event-fx
 :search-issues
 (fn [{:keys [db]} [_ query]]
   (if (empty? query)
     {:db (assoc db :search-query "" :issues [])}
     (do
       (api/search-issues query
        (fn [response]
          (rf/dispatch [:set-issues (:issues response)]))
        (fn [error]
          (rf/dispatch [:set-error (str "Failed to search: " error)])))
       {:db (assoc db :search-query query :loading true)}))))

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
 :fetch-issue-detail
 (fn [{:keys [db]} [_ id]]
   (api/fetch-issue id
    (fn [response]
      (rf/dispatch [:set-current-issue response]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch issue: " error)])))
   (api/fetch-comments id
    (fn [response]
      (rf/dispatch [:set-comments (:comments response)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch comments: " error)])))
   (api/fetch-activity id
    (fn [response]
      (rf/dispatch [:set-activity (:activity response)]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to fetch activity: " error)])))
   {:db (assoc db :current-issue nil :comments [] :activity [])}))

(rf/reg-event-db
 :set-current-issue
 (fn [db [_ issue]]
   (assoc db :current-issue issue)))

(rf/reg-event-db
 :set-comments
 (fn [db [_ comments]]
   (assoc db :comments comments)))

(rf/reg-event-db
 :set-activity
 (fn [db [_ activity]]
   (assoc db :activity activity)))

(rf/reg-event-fx
 :create-comment
 (fn [{:keys [db]} [_ issue-id data]]
   (api/create-comment issue-id data
    (fn [response]
      (rf/dispatch [:fetch-issue-detail issue-id]))
    (fn [error]
      (rf/dispatch [:set-error (str "Failed to create comment: " error)])))
   {:db db}))

(rf/reg-event-db
 :ws-update-issue
 (fn [db [_ issue]]
   (let [issues (:issues db)
         updated-issues (map (fn [i]
                               (if (= (:id i) (:id issue))
                                   issue
                                   i))
                             issues)]
     (assoc db :issues (vec updated-issues)))))

(rf/reg-event-db
 :add-issue
 (fn [db [_ issue]]
   (update db :issues conj issue)))

(rf/reg-event-db
 :remove-issue
 (fn [db [_ issue-id]]
   (update db :issues (fn [issues]
                        (vec (remove #(= (:id %) issue-id) issues))))))

(rf/reg-event-db
 :add-comment
 (fn [db [_ comment issue-id]]
   (if (and (= (:current-view db) :detail)
            (= (:id (:current-issue db)) issue-id))
     (update db :comments conj comment)
     db)))
