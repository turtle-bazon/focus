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
            "A Kanban-style ticket tracker for teams.")]
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

(defn draggable-card [ticket on-card-over card-idx drag-idx set-drag-idx!]
  (let [card-ref (r/atom nil)
        dragging (r/atom false)
        just-dragged (r/atom false)]
    (fn [ticket on-card-over card-idx drag-idx set-drag-idx!]
      (let [show-top (and drag-idx (= drag-idx card-idx) (not @dragging))
            show-bottom (and drag-idx (= drag-idx (inc card-idx)) (not @dragging))]
        [:div.ticket-card
         {:ref #(reset! card-ref %)
          :draggable true
          :class (str (when @dragging " dragging")
                      (when show-top " drop-target-top")
                      (when show-bottom " drop-target-bottom"))
          :on-drag-start (fn [e]
                           (.stopPropagation e)
                           (reset! dragging true)
                           (.setData (.-dataTransfer e) "text/plain" (str (:id ticket)))
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
                         (reset! just-dragged true)
                         (js/setTimeout #(reset! just-dragged false) 200)
                         (set-drag-idx! nil))
          :on-click (fn [e]
                      (when-not @just-dragged
                        (js/navigateTo (str "/tickets/" (:id ticket)))))
          :on-drag-over (fn [e]
                          (.preventDefault e)
                          (.stopPropagation e)
                          (set! (.. e -dataTransfer -dropEffect) "move")
                          (let [rect (.getBoundingClientRect (.-currentTarget e))
                                y (- (.-clientY e) (.-top rect))
                                h (.-height rect)]
                            (on-card-over (if (< y (/ h 2)) card-idx (inc card-idx)))))}
         [:div.ticket-card-header
          [:span.ticket-id (str "#" (:id ticket))]
          [:span.ticket-priority
           {:style {:background-color (get-priority-color (:priority ticket))}}
           (:priority ticket)]]
         [:h3.ticket-title (:title ticket)]
         (when (and (:assignee_id ticket)
                    (not= (:assignee_id ticket) "null")
                    (not (nil? (:assignee_id ticket))))
           [:div.ticket-assignee
            [:span.avatar
             (let [user-map @(rf/subscribe [:user-map])
                   user (get user-map (js/parseInt (:assignee_id ticket)))]
               (or (:username user) (str "User " (:assignee_id ticket))))]])]))))

(defn priority-group [status-id priority tickets]
  (let [drag-idx (r/atom nil)
        set-drag-idx! (fn [idx] (reset! drag-idx idx))
        group-ref (r/atom nil)]
    (fn [status-id priority tickets]
      (let [show-end (and @drag-idx (= @drag-idx (count tickets)))]
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
                                (reset! drag-idx (count tickets))))))
          :on-drag-leave (fn [e]
                           (let [related (.. e -relatedTarget)]
                             (when-not (and related (.contains @group-ref related))
                               (reset! drag-idx nil))))
          :on-drop (fn [e]
                     (.preventDefault e)
                     (.stopPropagation e)
                     (let [ticket-id (js/parseInt (.getData (.-dataTransfer e) "text/plain"))
                           raw-idx (or @drag-idx (count tickets))
                           dragged-pos (first (keep-indexed
                                               (fn [i t] (when (= (:id t) ticket-id) i))
                                               tickets))
                           target-idx (if (and dragged-pos (< dragged-pos raw-idx))
                                        (dec raw-idx)
                                        raw-idx)]
                       (reset! drag-idx nil)
                       (rf/dispatch [:reorder-ticket ticket-id status-id priority target-idx])))}
         [priority-group-header priority]
         (doall
          (map-indexed
           (fn [idx ticket]
             ^{:key (:id ticket)}
             [draggable-card ticket set-drag-idx! idx @drag-idx set-drag-idx!])
           tickets))
         (when show-end
           [:div.drop-line-active])]))))

(def all-priorities ["high" "medium" "low"])

(defn board-column [status]
  (let [tickets-by-status @(rf/subscribe [:tickets-by-status])
        tickets (get tickets-by-status (:id status) [])
        by-priority (into {} (map (fn [[p t]] [p t]) (group-by :priority tickets)))]
    [:div.board-column
     {:on-drag-over (fn [e]
                      (.preventDefault e)
                      (set! (.. e -dataTransfer -dropEffect) "move"))
      :on-drop (fn [e]
                 (.preventDefault e)
                 (let [ticket-id (js/parseInt (.getData (.-dataTransfer e) "text/plain"))
                       dragged (first (filter #(= (:id %) ticket-id) tickets))
                       priority (or (:priority dragged) "medium")
                       group-tickets (get by-priority priority [])
                       target-idx (count group-tickets)]
                   (rf/dispatch [:reorder-ticket ticket-id (:id status) priority target-idx])))}
     [:div.column-header
      {:style {:border-bottom-color (:color status)}}
      [:span.column-title (:name status)]
      [:span.column-count (count tickets)]]
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

(defn create-ticket-modal []
  (let [show-modal (r/atom false)
        title (r/atom "")
        description (r/atom "")
        priority (r/atom "medium")
        users @(rf/subscribe [:users])]
    (fn []
      [:div
       [:button.create-button
        {:on-click #(reset! show-modal true)}
        "New Ticket"]
       (when @show-modal
         [:div.modal-overlay
          {:on-click #(reset! show-modal false)}
          [:div.modal
           {:on-click #(.stopPropagation %)}
            [:h2 "Create Ticket"]
           [:div.form-group
            [:label "Title"]
            [:input {:type "text"
                     :value @title
                     :on-change #(reset! title (-> % .-target .-value))
                      :placeholder "Ticket title"}]]
           [:div.form-group
            [:label "Description"]
            [:textarea {:value @description
                       :on-change #(reset! description (-> % .-target .-value))
                        :placeholder "Describe the ticket..."}]]
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
                            (rf/dispatch [:create-ticket
                                        {:title @title
                                         :description @description
                                         :priority @priority}])
                           (reset! show-modal false)
                           (reset! title "")
                           (reset! description "")
                           (reset! priority "medium")))}
             "Create"]]]])])))

(defn ticket-detail []
  (let [new-comment (r/atom "")]
    (fn []
      (let [ticket @(rf/subscribe [:current-ticket])
            comments @(rf/subscribe [:comments])
            activity @(rf/subscribe [:activity])
            users @(rf/subscribe [:users])
            auth @(rf/subscribe [:auth])
            user-id (get-in auth [:user :id] 1)]
        (if ticket
          [:div.ticket-detail
           [:div.ticket-detail-header
            [:button.back-button
             {:on-click #(js/navigateTo "/")}
             "← Back to Board"]
            [:h1 (str "#" (:id ticket) " " (:title ticket))]]
             [:div.ticket-meta
              [:span.status-badge
               {:style {:background-color (get-status-color (:status ticket))}}
               (:status ticket)]
              [:select.priority-select
               {:value (:priority ticket)
                :style {:background-color (get-priority-color (:priority ticket))}
                :on-change (fn [e]
                             (rf/dispatch [:reorder-ticket
                                           (:id ticket)
                                           (:status ticket)
                                           (-> e .-target .-value)
                                           (:position ticket)]))}
               [:option {:value "low"} "low"]
               [:option {:value "medium"} "medium"]
               [:option {:value "high"} "high"]]
             (when (and (:assignee_id ticket)
                        (not= (:assignee_id ticket) "null")
                        (not (nil? (:assignee_id ticket))))
               [:span.assignee-badge
                (let [user (first (filter #(= (:id %) (js/parseInt (:assignee_id ticket))) users))]
                  (or (:username user) (str "User " (:assignee_id ticket))))])]
           [:div.ticket-body
            [:p (:description ticket)]]
           [:div.ticket-section
            [:h3 "Comments"]
            [:div.comments-list
             (for [comment comments]
               ^{:key (:id comment)}
               [:div.comment
                [:div.comment-header
                 [:span.comment-user
                  (let [author (first (filter #(= (:id %) (:user_id comment)) users))]
                    (or (:username author) (str "User " (:user_id comment))))]
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
                                         (:id ticket)
                                         {:user_id user-id
                                          :body @new-comment}])
                            (reset! new-comment "")))}
              "Add Comment"]]]
           [:div.ticket-section
            [:h3 "Activity"]
            [:div.activity-list
             (for [item activity]
               ^{:key (:id item)}
               [:div.activity-item
                [:span.activity-action (:action item)]
                [:span.activity-date (:created_at item)]])]]]
          [:div.loading "Loading..."])))))

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
                                           (rf/dispatch [:search-tickets v])
                                           (reset! debounce-timer nil))
                                         300))))
                                   :placeholder "Search tickets..."}]]))))

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
      [create-ticket-modal]]
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
       :detail [ticket-detail]
       [board-view])]))

(defn main-panel []
  (let [authenticated? @(rf/subscribe [:authenticated?])
        loading @(rf/subscribe [:loading])]
    (if loading
      [:div.loading-screen "Loading..."]
      (if authenticated?
        [app-panel]
        [landing-page]))))
