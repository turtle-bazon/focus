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

;;; Landing page

(defn landing-page []
  (let [app-info @(rf/subscribe [:app-info])]
    [:div.landing-page
     [:div.landing-hero
      [:div.landing-content
       [:h1.landing-title (or (:name app-info) "Focus")]
       [:p.landing-description
        (or (:description app-info)
            "A Kanban-style issue tracker for teams.")]
       (if (:oauth2_configured app-info)
         [:a.login-button {:href "/api/auth/login"}
          "Sign in with Mattermost"]
         [:div.landing-no-oauth
          [:p "OAuth2 is not configured yet."]
          [:p "Set :oauth2-client-id and :oauth2-client-secret in focus.conf"]])]]
     [:div.landing-footer
      [:p "Focus v0.0.1.0"]]]))

;;; Board components

(def priority-order
  {"high" 0 "medium" 1 "low" 2})

(defn priority-group-header [priority]
  (let [color (get-priority-color priority)]
    [:div.priority-group-header
     {:style {:border-left-color color}}
     [:span.priority-label
      {:style {:color color}}
      priority]]))

(defn draggable-card [issue on-card-over card-idx drag-idx set-drag-idx!]
  (let [card-ref (r/atom nil)
        dragging (r/atom false)]
    (fn [issue on-card-over card-idx drag-idx set-drag-idx!]
      (let [show-top (and drag-idx (= drag-idx card-idx) (not @dragging))
            show-bottom (and drag-idx (= drag-idx (inc card-idx)) (not @dragging))]
        [:div.issue-card
         {:ref #(reset! card-ref %)
          :draggable true
          :class (str (when @dragging " dragging")
                      (when show-top " drop-target-top")
                      (when show-bottom " drop-target-bottom"))
          :on-drag-start (fn [e]
                           (reset! dragging true)
                           (.setData (.-dataTransfer e) "text/plain" (str (:id issue)))
                           (set! (.. e -dataTransfer -effectAllowed) "move")
                           (when-let [el @card-ref]
                             (let [ghost (.cloneNode el true)]
                               (set! (.. ghost -style -position) "fixed")
                               (set! (.. ghost -style -top) "-9999px")
                               (set! (.. ghost -style -left) "-9999px")
                               (set! (.. ghost -style -width) (str (.-offsetWidth el) "px"))
                               (set! (.. ghost -style -opacity) "0.9")
                               (set! (.. ghost -style -pointerEvents) "none")
                               (set! (.. ghost -style -boxShadow) "0 8px 24px rgba(0,0,0,0.4)")
                               (set! (.. ghost -style -border) "1px solid #3b82f6")
                               (set! (.. ghost -style -zIndex) "9999")
                               (.appendChild js/document.body ghost)
                               (.setDragImage (.-dataTransfer e) ghost 20 20)
                               (js/setTimeout #(.removeChild js/document.body ghost) 0))))
          :on-drag-end (fn [_]
                         (reset! dragging false)
                         (set-drag-idx! nil))
          :on-click #(js/navigateTo (str "/issues/" (:id issue)))
          :on-mouse-down (fn [e]
                           (.preventDefault e))
          :on-drag-over (fn [e]
                          (.preventDefault e)
                          (.stopPropagation e)
                          (set! (.. e -dataTransfer -dropEffect) "move")
                          (let [rect (.getBoundingClientRect (.-currentTarget e))
                                y (- (.-clientY e) (.-top rect))
                                h (.-height rect)]
                            (on-card-over (if (< y (/ h 2)) card-idx (inc card-idx)))))}
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
             (let [user-map @(rf/subscribe [:user-map])
                   user (get user-map (js/parseInt (:assignee_id issue)))]
               (or (:username user) (str "User " (:assignee_id issue))))]])]))))

(defn priority-group [status-id priority issues]
  (let [drag-idx (r/atom nil)
        set-drag-idx! (fn [idx] (reset! drag-idx idx))
        group-ref (r/atom nil)]
    (fn [status-id priority issues]
      (let [show-end (and @drag-idx (= @drag-idx (count issues)))]
        [:div.priority-group
         {:ref #(reset! group-ref %)
          :on-drag-over (fn [e]
                          (.preventDefault e)
                          (set! (.. e -dataTransfer -dropEffect) "move")
                          (let [el @group-ref
                                children (array-seq (.. el -children))
                                cards (rest children)
                                y (- (.-clientY e) (.. el -getBoundingClientRect -top))]
                            (loop [i 0 cs cards]
                              (if (seq cs)
                                (let [card-el (first cs)
                                      rect (.getBoundingClientRect card-el)
                                      card-top (- (.. rect -top) (.. el -getBoundingClientRect -top))
                                      card-h (.-height rect)]
                                  (if (< y (+ card-top (/ card-h 2)))
                                    (reset! drag-idx i)
                                    (recur (inc i) (rest cs))))
                                (reset! drag-idx (count issues))))))
          :on-drag-leave (fn [e]
                           (let [related (.. e -relatedTarget)]
                             (when-not (and related (.contains @group-ref related))
                               (reset! drag-idx nil))))
          :on-drop (fn [e]
                     (.preventDefault e)
                     (.stopPropagation e)
                     (let [issue-id (js/parseInt (.getData (.-dataTransfer e) "text/plain"))
                           raw-idx (or @drag-idx (count issues))
                           dragged-pos (first (keep-indexed
                                               (fn [i iss] (when (= (:id iss) issue-id) i))
                                               issues))
                           target-idx (if (and dragged-pos (< dragged-pos raw-idx))
                                        (dec raw-idx)
                                        raw-idx)]
                       (reset! drag-idx nil)
                       (rf/dispatch [:reorder-issue issue-id status-id priority target-idx])))}
         [priority-group-header priority]
         (doall
          (map-indexed
           (fn [idx issue]
             ^{:key (:id issue)}
             [draggable-card issue set-drag-idx! idx @drag-idx set-drag-idx!])
           issues))
         (when show-end
           [:div.drop-line-active])]))))

(def all-priorities ["high" "medium" "low"])

(defn board-column [status]
  (let [issues-by-status @(rf/subscribe [:issues-by-status])
        issues (get issues-by-status (:id status) [])
        by-priority (into {} (map (fn [[p iss]] [p iss]) (group-by :priority issues)))]
    [:div.board-column
     {:on-drag-over (fn [e]
                      (.preventDefault e)
                      (set! (.. e -dataTransfer -dropEffect) "move"))
      :on-drop (fn [e]
                 (.preventDefault e)
                 (let [issue-id (js/parseInt (.getData (.-dataTransfer e) "text/plain"))
                       dragged (first (filter #(= (:id %) issue-id) issues))
                       priority (or (:priority dragged) "medium")
                       group-issues (get by-priority priority [])
                       target-idx (count group-issues)]
                   (rf/dispatch [:reorder-issue issue-id (:id status) priority target-idx])))}
     [:div.column-header
      {:style {:border-bottom-color (:color status)}}
      [:span.column-title (:name status)]
      [:span.column-count (count issues)]]
     [:div.column-cards
      (doall
       (for [priority (sort-by #(get priority-order % 1) all-priorities)]
         ^{:key priority}
         [priority-group (:id status) priority (get by-priority priority [])]))]]))

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
         {:on-click #(js/navigateTo "/")}
         "← Back to Board"]
        [:h1 (str "#" (:id issue) " " (:title issue))]]
        [:div.issue-meta
         [:span.status-badge
          {:style {:background-color (get-status-color (:status issue))}}
          (:status issue)]
         [:select.priority-select
          {:value (:priority issue)
           :style {:background-color (get-priority-color (:priority issue))}
           :on-change (fn [e]
                        (rf/dispatch [:reorder-issue
                                      (:id issue)
                                      (:status issue)
                                      (-> e .-target .-value)
                                      (:position issue)]))}
          [:option {:value "low"} "low"]
          [:option {:value "medium"} "medium"]
          [:option {:value "high"} "high"]]
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
  (let [debounce-timer (r/atom nil)]
    (fn []
      (let [query @(rf/subscribe [:search-query])]
        [:div.search-bar
         [:input {:type "text"
                 :value query
                 :on-change (fn [e]
                              (let [v (-> e .-target .-value)]
                                (rf/dispatch [:set-search-query v])
                                (when @debounce-timer
                                  (js/clearTimeout @debounce-timer))
                                (reset! debounce-timer
                                        (js/setTimeout
                                         (fn []
                                           (rf/dispatch [:search-issues v])
                                           (reset! debounce-timer nil))
                                         300))))
                 :placeholder "Search issues..."}]]))))

(defn nav-bar []
  (let [current-view @(rf/subscribe [:current-view])
        auth @(rf/subscribe [:auth])]
    [:div.nav-bar
     [:div.nav-brand "Focus"]
     [:div.nav-links
      [:a {:class (when (= current-view :board) "active")
           :on-click #(js/navigateTo "/")}
       "Board"]
      [:a {:class (when (= current-view :list) "active")
           :on-click #(js/navigateTo "/")}
       "List"]
      [create-issue-modal]]
     [:div.nav-auth
      (when-let [user (get auth :user)]
        [:span.user-name (:username user)])
      [:button.logout-button
       {:on-click #(rf/dispatch [:logout])}
       "Logout"]]]))

(defn app-panel []
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

(defn main-panel []
  (let [authenticated? @(rf/subscribe [:authenticated?])
        loading @(rf/subscribe [:loading])]
    (if loading
      [:div.loading-screen "Loading..."]
      (if authenticated?
        [app-panel]
        [landing-page]))))
