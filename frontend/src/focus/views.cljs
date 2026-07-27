(ns focus.views
  (:require [re-frame.core :as rf]
            [reagent.core :as r]))

(def statuses
  [{:id "backlog" :name "Backlog" :color "#6b7280"}
   {:id "open" :name "Open" :color "#3b82f6"}
   {:id "in_progress" :name "In Progress" :color "#f59e0b"}
   {:id "review" :name "Review" :color "#8b5cf6"}
   {:id "done" :name "Done" :color "#10b981"}])

(def priority-colors
  {"low" "#6b7280"
   "medium" "#3b82f6"
   "high" "#ef4444"})

(defn get-status-color [status]
  (or (some #(when (= (:id %) status) (:color %)) statuses) "#6b7280"))

(defn get-priority-color [priority]
  (get priority-colors priority "#6b7280"))

(defn issue-card [issue]
  (let [user-map @(rf/subscribe [:user-map])
        label-map @(rf/subscribe [:label-map])]
    [:div.issue-card
     {:draggable true
      :on-drag-start (fn [e]
                       (.setData (.-dataTransfer e) "text/plain" (str (:id issue)))
                       (set! (.. e -dataTransfer -effectAllowed) "move"))
      :on-click #(rf/dispatch [:set-view :detail])
      :on-mouse-down (fn [e]
                       (when (= (.-button e) 0)
                         (rf/dispatch [:fetch-issue-detail (:id issue)])))}
     [:div.issue-card-header
      [:span.issue-id (str "#" (:id issue))]
      [:span.issue-priority
       {:style {:background-color (get-priority-color (:priority issue))}}
       (:priority issue)]]
     [:h3.issue-title (:title issue)]
     (when (and (:assignee_id issue)
                (not= (:assignee_id issue) "null")
                (not (nil? (:assignee_id issue))))
       [:div.issue-assignee
        [:span.avatar
         (let [user (get user-map (js/parseInt (:assignee_id issue)))]
           (or (:username user) (str "User " (:assignee_id issue))))]])]))

(defn board-column [status]
  (let [issues-by-status @(rf/subscribe [:issues-by-status])
        issues (get issues-by-status (:id status) [])
        drag-over (r/atom false)]
    [:div.board-column
     {:on-drag-over (fn [e]
                      (.preventDefault e)
                      (reset! drag-over true))
      :on-drag-leave (fn [_]
                       (reset! drag-over false))
      :on-drop (fn [e]
                 (.preventDefault e)
                 (reset! drag-over false)
                 (let [issue-id (js/parseInt (.getData (.-dataTransfer e) "text/plain"))]
                   (rf/dispatch [:update-issue-status issue-id (:id status)])))}
     [:div.column-header
      {:style {:border-bottom-color (:color status)}}
      [:span.column-title (:name status)]
      [:span.column-count (count issues)]]
     [:div.column-cards
      (for [issue issues]
        ^{:key (:id issue)}
        [issue-card issue])]]))

(defn board-view []
  [:div.board-view
   (for [status statuses]
     ^{:key (:id status)}
     [board-column status])])

(defn create-issue-modal []
  (let [show-modal (r/atom false)
        title (r/atom "")
        description (r/atom "")
        priority (r/atom "medium")
        users @(rf/subscribe [:users])]
    (fn []
      [:div
       [:button.create-button
        {:on-click #(reset! show-modal true)}
        "New Issue"]
       (when @show-modal
         [:div.modal-overlay
          {:on-click #(reset! show-modal false)}
          [:div.modal
           {:on-click #(.stopPropagation %)}
           [:h2 "Create Issue"]
           [:div.form-group
            [:label "Title"]
            [:input {:type "text"
                     :value @title
                     :on-change #(reset! title (-> % .-target .-value))
                     :placeholder "Issue title"}]]
           [:div.form-group
            [:label "Description"]
            [:textarea {:value @description
                       :on-change #(reset! description (-> % .-target .-value))
                       :placeholder "Describe the issue..."}]]
           [:div.form-group
            [:label "Priority"]
            [:select {:value @priority
                     :on-change #(reset! priority (-> % .-target .-value))}
             [:option {:value "low"} "Low"]
             [:option {:value "medium"} "Medium"]
             [:option {:value "high"} "High"]]]
           [:div.modal-actions
            [:button.cancel-button
             {:on-click #(reset! show-modal false)}
             "Cancel"]
            [:button.submit-button
             {:on-click (fn []
                         (when (seq @title)
                           (rf/dispatch [:create-issue
                                        {:title @title
                                         :description @description
                                         :priority @priority}])
                           (reset! show-modal false)
                           (reset! title "")
                           (reset! description "")
                           (reset! priority "medium")))}
             "Create"]]]])])))

(defn issue-detail []
  (let [issue @(rf/subscribe [:current-issue])
        comments @(rf/subscribe [:comments])
        activity @(rf/subscribe [:activity])
        users @(rf/subscribe [:users])
        new-comment (r/atom "")]
    (if issue
      [:div.issue-detail
       [:div.issue-detail-header
        [:button.back-button
         {:on-click #(rf/dispatch [:set-view :board])}
         "← Back to Board"]
        [:h1 (str "#" (:id issue) " " (:title issue))]]
       [:div.issue-meta
        [:span.status-badge
         {:style {:background-color (get-status-color (:status issue))}}
         (:status issue)]
        [:span.priority-badge
         {:style {:background-color (get-priority-color (:priority issue))}}
         (:priority issue)]
        (when (and (:assignee_id issue)
                   (not= (:assignee_id issue) "null")
                   (not (nil? (:assignee_id issue))))
          [:span.assignee-badge
           (let [user (first (filter #(= (:id %) (js/parseInt (:assignee_id issue))) users))]
             (or (:username user) (str "User " (:assignee_id issue))))])]
       [:div.issue-body
        [:p (:description issue)]]
       [:div.issue-section
        [:h3 "Comments"]
        [:div.comments-list
         (for [comment comments]
           ^{:key (:id comment)}
           [:div.comment
            [:div.comment-header
             [:span.comment-user (str "User " (:user_id comment))]
             [:span.comment-date (:created_at comment)]]
            [:div.comment-body (:body comment)]])]
        [:div.comment-form
         [:textarea {:value @new-comment
                    :on-change #(reset! new-comment (-> % .-target .-value))
                    :placeholder "Add a comment..."}]
         [:button.submit-button
          {:on-click (fn []
                      (when (seq @new-comment)
                        (rf/dispatch [:create-comment
                                     (:id issue)
                                     {:user_id 1
                                      :body @new-comment}])
                        (reset! new-comment "")))}
          "Add Comment"]]]
       [:div.issue-section
        [:h3 "Activity"]
        [:div.activity-list
         (for [item activity]
           ^{:key (:id item)}
           [:div.activity-item
            [:span.activity-action (:action item)]
            [:span.activity-date (:created_at item)]])]]]
      [:div.loading "Loading..."])))

(defn error-banner []
  (let [error @(rf/subscribe [:error])]
    (when error
      [:div.error-banner
       [:span error]
       [:button {:on-click #(rf/dispatch [:clear-error])} "×"]])))

(defn search-bar []
  (let [query @(rf/subscribe [:search-query])]
    [:div.search-bar
     [:input {:type "text"
             :value query
             :on-change #(rf/dispatch [:search-issues (-> % .-target .-value)])
             :placeholder "Search issues..."}]]))

(defn nav-bar []
  (let [current-view @(rf/subscribe [:current-view])]
    [:div.nav-bar
     [:div.nav-brand "Focus"]
     [:div.nav-links
      [:a {:class (when (= current-view :board) "active")
           :on-click #(rf/dispatch [:set-view :board])}
       "Board"]
      [:a {:class (when (= current-view :list) "active")
           :on-click #(do (rf/dispatch [:set-view :list])
                         (rf/dispatch [:fetch-issues {}]))}
       "List"]
      [create-issue-modal]]]))

(defn main-panel []
  (let [current-view @(rf/subscribe [:current-view])]
    [:div.app
     [nav-bar]
     [search-bar]
     [error-banner]
     (case current-view
       :board [board-view]
       :list [board-view]
       :detail [issue-detail]
       [board-view])]))
