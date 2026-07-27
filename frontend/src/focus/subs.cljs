(ns focus.subs
  (:require [re-frame.core :as rf]))

(rf/reg-sub
 :current-view
 (fn [db _]
   (:current-view db)))

(rf/reg-sub
 :issues
 (fn [db _]
   (:issues db)))

(rf/reg-sub
 :users
 (fn [db _]
   (:users db)))

(rf/reg-sub
 :labels
 (fn [db _]
   (:labels db)))

(rf/reg-sub
 :current-issue
 (fn [db _]
   (:current-issue db)))

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
 :issues-by-status
 (fn [db _]
   (let [issues (:issues db)]
     (->> issues
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
