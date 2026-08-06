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
   (:comments-total db)))

(rf/reg-sub
 :activity-count
 (fn [db _]
   (:activity-total db)))

(rf/reg-sub
 :comments-loading
 (fn [db _]
   (:comments-loading db)))

(rf/reg-sub
 :activity-loading
 (fn [db _]
   (:activity-loading db)))

(rf/reg-sub
 :has-more-comments
 (fn [db _]
   (< (count (:comments db)) (:comments-total db))))

(rf/reg-sub
 :has-more-activity
 (fn [db _]
   (< (count (:activity db)) (:activity-total db))))

(rf/reg-sub
 :board-activity
 (fn [db _]
   (:board-activity db)))

(rf/reg-sub
 :board-activity-total
 (fn [db _]
   (:board-activity-total db)))

(rf/reg-sub
 :board-activity-loading
 (fn [db _]
   (:board-activity-loading db)))

(rf/reg-sub
 :all-activity
 (fn [db _]
   (:all-activity db)))

(rf/reg-sub
 :all-activity-loading
 (fn [db _]
   (:all-activity-loading db)))

(rf/reg-sub
 :has-more-all-activity
 (fn [db _]
   (< (count (:all-activity db)) (:all-activity-total db))))

(rf/reg-sub
 :has-more-board-activity
 (fn [db _]
   (< (count (:board-activity db)) (:board-activity-total db))))

(rf/reg-sub
 :active-tab
 (fn [db _]
   (:active-tab db)))

(rf/reg-sub
 :comment-form-version
 (fn [db _]
   (:comment-form-version db)))

(rf/reg-sub
 :groups
 (fn [db _]
   (:groups db)))

(rf/reg-sub
 :group-map
 (fn [db _]
   (into {} (map #(vector (:id %) %) (:groups db)))))

(rf/reg-sub
 :group-members
 (fn [db _]
   (:group-members db)))

(rf/reg-sub
 :group-members-modal
 (fn [db _]
   (:group-members-modal db)))

(rf/reg-sub
 :create-group-modal
 (fn [db _]
   (:create-group-modal db)))

(rf/reg-sub
  :ticket-observers
  (fn [db _]
    (:ticket-observers db)))

(rf/reg-sub
 :boards
 (fn [db _]
   (:boards db)))

(rf/reg-sub
 :current-board
 (fn [db _]
   (:current-board db)))

(rf/reg-sub
 :current-board-id
 (fn [db _]
   (:current-board-id db)))

(rf/reg-sub
 :board-statuses
 (fn [db _]
   (:statuses (:current-board db))))

(rf/reg-sub
 :board-transitions
 (fn [db _]
   (:transitions (:current-board db))))

(rf/reg-sub
 :can-manage-boards
 (fn [db _]
   (let [role (get-in db [:auth :user :role])]
     (or (= "admin" role) (= "group_manager" role)))))

(rf/reg-sub
 :transition-allowed
 (fn [db _]
   (let [transitions (vec (:transitions (:current-board db)))]
     (fn [from-code to-code]
       (or (= from-code to-code)
           (boolean (some #(and (= (:from_code %) from-code)
                                (= (:to_code %) to-code))
                          transitions)))))))

(rf/reg-sub
 :is-admin
 (fn [db _]
   (let [user (get-in db [:auth :user])]
     (= "admin" (:role user)))))

(rf/reg-sub
 :can-manage-users
 (fn [db _]
   (let [role (get-in db [:auth :user :role])]
     (or (= "admin" role) (= "group_manager" role)))))

(rf/reg-sub
 :settings-tab
 (fn [db _]
   (:settings-tab db)))

(rf/reg-sub
 :confirm-modal
 (fn [db _]
   (:confirm-modal db)))
