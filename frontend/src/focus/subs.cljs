(ns focus.subs
  (:require [re-frame.core :as rf]))

(rf/reg-sub
 :current-view
 (fn [db _]
   (:current-view db)))

(rf/reg-sub
 :auth
 (fn [db _]
   (:auth db)))

(rf/reg-sub
 :authenticated?
 (fn [db _]
   (get-in db [:auth :authenticated] false)))

(rf/reg-sub
 :app-info
 (fn [db _]
   (:app-info db)))

(rf/reg-sub
 :tickets
 (fn [db _]
   (:tickets db)))

(rf/reg-sub
 :users
 (fn [db _]
   (:users db)))

(rf/reg-sub
 :labels
 (fn [db _]
   (:labels db)))

(rf/reg-sub
 :current-ticket
 (fn [db _]
   (:current-ticket db)))

(rf/reg-sub
 :comments
 (fn [db _]
   (:comments db)))

(rf/reg-sub
 :activity
 (fn [db _]
   (:activity db)))

(rf/reg-sub
 :search-query
 (fn [db _]
   (:search-query db)))

(rf/reg-sub
 :loading
 (fn [db _]
   (:loading db)))

(rf/reg-sub
 :error
 (fn [db _]
   (:error db)))

(rf/reg-sub
 :tickets-by-status
 (fn [db _]
   (let [tickets (:tickets db)]
     (->> tickets
          (group-by :status)
          (into (sorted-map))))))

(rf/reg-sub
 :user-map
 (fn [db _]
   (into {} (map #(vector (:id %) %) (:users db)))))

(rf/reg-sub
 :label-map
 (fn [db _]
   (into {} (map #(vector (:id %) %) (:labels db)))))

(rf/reg-sub
 :comment-count
 (fn [db _]
   (count (:comments db))))

(rf/reg-sub
 :activity-count
 (fn [db _]
   (count (:activity db))))
