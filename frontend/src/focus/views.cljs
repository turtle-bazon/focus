(ns focus.views
  (:require [re-frame.core :as rf]
            [reagent.core :as r]
            [clojure.string :as str]
            [focus.i18n :as i18n]
            [focus.markdown :as md]))

(defn t [key]
  (let [locale @(rf/subscribe [:locale])]
    (i18n/t locale key)))

(defn- find-tag-end [html start-pos open-re close-re]
  (loop [pos start-pos
         depth 1]
    (let [rest-html (subs html pos)
          next-open (re-find open-re rest-html)
          next-close (re-find close-re rest-html)
          open-idx (when next-open (.indexOf rest-html next-open))
          close-idx (when next-close (.indexOf rest-html next-close))]
      (cond
        (nil? next-close) nil
        (or (nil? open-idx) (< close-idx open-idx))
        (if (= depth 1)
          (+ pos close-idx (count next-close))
          (recur (+ pos close-idx (count next-close)) (dec depth)))
        :else
        (recur (+ pos open-idx (count next-open)) (inc depth))))))
(defn- extract-li-items [content]
  (loop [in content
         items []
         li-depth 0
         current ""]
    (if (empty? in)
      items
      (let [li-start-m (re-find #"^<li[^>]*>" in)
            li-end-m (re-find #"^</li>" in)
            ul-start-m (re-find #"^<(?:ul|ol)[^>]*>" in)
            ul-end-m (re-find #"^</(?:ul|ol)>" in)]
        (cond
          li-start-m
          (recur (subs in (count li-start-m))
                 items (inc li-depth)
                 (if (zero? li-depth) (str li-start-m) (str current li-start-m)))
          li-end-m
          (let [new-current (str current li-end-m)]
            (if (= li-depth 1)
              (recur (subs in (count li-end-m)) (conj items new-current) 0 "")
              (recur (subs in (count li-end-m)) items (dec li-depth) new-current)))
          ul-start-m
          (if (zero? li-depth)
            (recur (subs in (count ul-start-m)) items li-depth current)
            (recur (subs in (count ul-start-m)) items li-depth (str current ul-start-m)))
          ul-end-m
          (if (zero? li-depth)
            (recur (subs in (count ul-end-m)) items li-depth current)
            (recur (subs in (count ul-end-m)) items li-depth (str current ul-end-m)))
          :else
          (let [text-end (loop [i 0]
                           (if (>= i (count in)) i
                               (if (= (.charAt in i) \<) i (recur (inc i)))))]
            (if (and (< text-end (count in))
                     (re-find #"^</?(?:li|ul|ol)" (subs in text-end)))
              (recur (subs in text-end) items li-depth (str current (subs in 0 text-end)))
              (let [scan-end (if (< text-end (count in))
                               (let [e (.indexOf in ">" text-end)]
                                 (if (>= e 0) (+ e 1) (count in)))
                               (count in))]
                (recur (subs in scan-end) items li-depth
                        (str current (subs in 0 scan-end)))))))))))

(defn- item-text [item-html]
  (-> item-html
      (str/replace #"^<li[^>]*>" "")
      (str/replace #"</li>$" "")
      (str/replace #"<(?:ul|ol)[^>]*>[\s\S]*</(?:ul|ol)>" "")
      str/trim))

(defn- item-nested [item-html]
  (let [inner (-> item-html
                  (str/replace #"^<li[^>]*>" "")
                  (str/replace #"</li>$" ""))]
    (re-find #"<(?:ul|ol)[^>]*>[\s\S]*</(?:ul|ol)>" inner)))

(defn- html-lists->markdown
  ([html] (html-lists->markdown html 0))
  ([html depth]
   (let [ul-m (re-find #"<ul[^>]*>" html)
         ol-m (re-find #"<ol[^>]*>" html)
         ul-pos (when ul-m (.indexOf html ul-m))
         ol-pos (when ol-m (.indexOf html ol-m))
         start (cond
                 (and ul-m ol-m) (if (< ul-pos ol-pos) ul-m ol-m)
                 ul-m ul-m
                 :else ol-m)]
     (if (nil? start)
       html
       (let [tag-type (if (and ul-m (or (nil? ol-m) (< ul-pos ol-pos))) "ul" "ol")
             start-pos (.indexOf html start)
             open-re (re-pattern (str "<" tag-type "[^>]*>"))
             close-re (re-pattern (str "</" tag-type ">"))
             end-pos (find-tag-end html (+ start-pos (count start)) open-re close-re)]
         (if (nil? end-pos)
           html
           (let [block (subs html start-pos end-pos)
                 open-tag (re-find open-re block)
                 close-tag (re-find close-re block)
                 content (subs block (count open-tag) (- (count block) (count close-tag)))
                 items (extract-li-items content)
                 before (subs html 0 start-pos)
                 after (subs html end-pos)
                 indent (apply str (repeat (* 2 depth) " "))
                 converted (apply str
                                  (map-indexed (fn [idx item]
                                                 (let [text (item-text item)
                                                       nested (item-nested item)
                                                       prefix (if (= tag-type "ol")
                                                                (str (inc idx) ". ")
                                                                "- ")]
                                                   (str indent prefix text "\n"
                                                        (when nested (html-lists->markdown nested (inc depth))))))
                                               items))]
             (recur (str before converted after) depth))))))))

(defn- process-list-blocks [html]
  (html-lists->markdown html))

(defn editor-html->markdown [html]
  (if-not (string? html)
    ""
    (-> html
        (str/replace #"<pre[^>]*>\s*<code[^>]*>([\s\S]*?)</code>\s*</pre>" "```\n$1\n```\n")
        (str/replace #"<pre[^>]*>([\s\S]*?)</pre>" "```\n$1\n```\n")
        (str/replace #"<strong[^>]*>(.*?)</strong>" "**$1**")
        (str/replace #"<b[^>]*>(.*?)</b>" "**$1**")
        (str/replace #"<em[^>]*>(.*?)</em>" "*$1*")
        (str/replace #"<i[^>]*>(.*?)</i>" "*$1*")
        (str/replace #"<s[^>]*>(.*?)</s>" "~~$1~~")
        (str/replace #"<del[^>]*>(.*?)</del>" "~~$1~~")
        (str/replace #"<code[^>]*>(.*?)</code>" "`$1`")
        (str/replace #"<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>" "[$2]($1)")
        (str/replace #"<img[^>]*src=\"([^\"]+)\"[^>]*/?>" "![]($1)")
        (str/replace #"<blockquote[^>]*>(.*?)</blockquote>" "> $1")
        process-list-blocks
        (str/replace #"<br\s*/?>" "\n")
        (str/replace #"</div>|</p>" "\n")
        (str/replace #"<[^>]+>" "")
        (str/replace #"&amp;" "&")
        (str/replace #"&lt;" "<")
        (str/replace #"&gt;" ">")
        (str/replace #"\u200B" "")
        (str/replace #"&nbsp;" " ")
        (str/replace #"\n\s*\n\s*\n" "\n\n")
        str/trim)))

(def ^:private editor-content-cb (atom nil))
(def ^:private editor-ref-atom (atom nil))

(defn editor-sync-content []
  (when-let [cb @editor-content-cb]
    (let [sel (.getSelection js/window)]
      (when (and sel (pos? (.-rangeCount sel)))
        (let [range (.getRangeAt sel 0)
              container (.-startContainer range)
              el (if (= 3 (.-nodeType container))
                   (.-parentElement container)
                   container)
              ce (.closest el "[contenteditable=true]")]
          (when ce
            (let [md (editor-html->markdown (.-innerHTML ce))]
              (cb md))))))))

(defn- cursor-in-code-block? []
  (let [sel (.getSelection js/window)]
    (when (and sel (pos? (.-rangeCount sel)))
      (let [range (.getRangeAt sel 0)
            container (.-startContainer range)
            node (if (= 3 (.-nodeType container)) (.-parentElement container) container)]
        (when node
          (boolean (.closest node "code, pre")))))))

(defn editor-exec-command [command & args]
  (.execCommand js/document command false (first args)))

(defn editor-wrap-tag [tag]
  (case tag
    "strong" (editor-exec-command "bold")
    "em" (editor-exec-command "italic")
    "s" (editor-exec-command "strikeThrough")
    "del" (editor-exec-command "strikeThrough")
    nil)
  (editor-sync-content))

(defn editor-insert-block-tag [tag]
  (let [sel (.getSelection js/window)]
    (when (and sel (pos? (.-rangeCount sel)))
      (let [range (.getRangeAt sel 0)]
        (if (not (.-collapsed range))
          (let [fragment (.cloneContents range)
                wrapper (.createElement js/document tag)]
            (.appendChild wrapper fragment)
            (.deleteContents range)
            (.insertNode range wrapper))
          (let [wrapper (.createElement js/document tag)]
            (.appendChild wrapper (.createTextNode js/document "\u200B"))
            (.insertNode range wrapper)
            (.setStart range wrapper 0)
            (.collapse range true)))
        (editor-sync-content)))))

(defn editor-insert-link-tag []
  (let [sel (.getSelection js/window)]
    (when (and sel (pos? (.-rangeCount sel)))
      (let [range (.getRangeAt sel 0)
            url (js/prompt "URL:")]
        (when (seq url)
          (if (not (.-collapsed range))
            (let [fragment (.cloneContents range)
                  a (.createElement js/document "a")]
              (set! (.-href a) url)
              (set! (.-target a) "_blank")
              (.appendChild a fragment)
              (.deleteContents range)
              (.insertNode range a))
            (let [a (.createElement js/document "a")]
              (set! (.-href a) url)
              (set! (.-target a) "_blank")
              (set! (.-textContent a) url)
              (.insertNode range a)
              (.setStart range a (.-textContent.length a))
              (.collapse range true)))
          (editor-sync-content))))))

(defn editor-insert-img-tag []
  (let [sel (.getSelection js/window)]
    (when (and sel (pos? (.-rangeCount sel)))
      (let [range (.getRangeAt sel 0)
            url (js/prompt "Image URL:")]
        (when (seq url)
          (let [img (.createElement js/document "img")]
            (set! (.-src img) url)
            (set! (.-style img) "max-width:100%;border-radius:6px")
            (.insertNode range img)
            (.setStartAfter range img)
            (.collapse range true)
            (editor-sync-content)))))))

(defn editor-insert-list-tag [tag]
  (when-let [ce @editor-ref-atom]
    (let [sel (.getSelection js/window)
          range (when (and sel (pos? (.-rangeCount sel)))
                  (.getRangeAt sel 0))
          ce-range (when range
                     (let [sc (.-startContainer range)]
                       (when (.contains ce (if (= 3 (.-nodeType sc)) sc sc))
                         range)))]
      (let [li (.createElement js/document "li")
            list-el (.createElement js/document tag)]
        (if (and ce-range (not (.-collapsed ce-range)))
          (let [fragment (.cloneContents ce-range)]
            (.appendChild li fragment)
            (.deleteContents ce-range))
          (.appendChild li (.createTextNode js/document "\u200B")))
        (.appendChild list-el li)
        (if ce-range
          (.insertNode ce-range list-el)
          (let [fallback-range (.createRange js/document)]
            (.selectNodeContents fallback-range ce)
            (.collapse fallback-range false)
            (.insertNode fallback-range list-el)))
        (.focus ce)
        (let [new-range (.createRange js/document)]
          (.selectNodeContents new-range li)
          (.collapse new-range false)
          (.removeAllRanges sel)
          (.addRange sel new-range))
        (editor-sync-content)))))

(defn editor-toolbar-button [label title on-click]
  (let [saved-range (r/atom nil)]
    (fn [label title on-click]
      [:button.editor-toolbar-btn
       {:type "button"
        :title title
        :on-mouse-down (fn [e]
                         (.preventDefault e)
                         (let [sel (.getSelection js/window)]
                           (when (and sel (pos? (.-rangeCount sel)))
                             (reset! saved-range (.cloneRange (.getRangeAt sel 0))))))
        :on-click (fn [e]
                    (.preventDefault e)
                    (let [range @saved-range
                          ce (when range
                               (let [sc (.-startContainer range)
                                     el (if (= 3 (.-nodeType sc)) (.-parentElement sc) sc)]
                                 (when (and el (.-closest el))
                                   (.closest el "[contenteditable=true]"))))]
                      (if ce
                        (let [sel (.getSelection js/window)]
                          (.removeAllRanges sel)
                          (.addRange sel range)
                          (.focus ce)
                          (when-not (cursor-in-code-block?)
                            (on-click)))
                        (when-let [ce @editor-ref-atom]
                          (let [sel (.getSelection js/window)]
                            (.focus ce)
                            (let [range (.createRange js/document)]
                              (if (pos? (.-length (.-childNodes ce)))
                                (let [last-child (.-lastChild ce)]
                                  (if (= 3 (.-nodeType last-child))
                                    (.setStart range last-child (.-length last-child))
                                    (.selectNodeContents range last-child))
                                  (.collapse range false))
                                (.selectNodeContents range ce))
                              (.removeAllRanges sel)
                              (.addRange sel range))
                            (when-not (cursor-in-code-block?)
                              (on-click)))))))}
       label])))

(defn editor-toolbar []
  [:div.editor-toolbar
   [editor-toolbar-button [:strong "B"] (t :editor/bold) #(editor-wrap-tag "strong")]
   [editor-toolbar-button [:em "I"] (t :editor/italic) #(editor-wrap-tag "em")]
   [editor-toolbar-button [:s "S"] (t :editor/strike) #(editor-wrap-tag "s")]
   [:div.editor-toolbar-separator]
   [editor-toolbar-button "\u2022" (t :editor/bullet-list) #(editor-insert-list-tag "ul")]
   [editor-toolbar-button "1." (t :editor/ordered-list) #(editor-insert-list-tag "ol")]
   [:div.editor-toolbar-separator]
   [editor-toolbar-button "\u201C" (t :editor/quote) #(editor-insert-block-tag "blockquote")]
   [editor-toolbar-button [:code "</>"] (t :editor/code) #(editor-insert-block-tag "pre")]
   [:div.editor-toolbar-separator]
   [editor-toolbar-button "\uD83D\uDD17" (t :editor/link) editor-insert-link-tag]
   [editor-toolbar-button "\uD83D\uDDBC" (t :editor/image) editor-insert-img-tag]])

(defn wysiwyg-editor [opts]
  (let [mounted (r/atom false)]
    (r/create-class
     {:should-component-update (fn [_ _ _] false)
      :reagent-render
      (fn [opts]
        [:div.markdown-editor
         [editor-toolbar]
         [:div.markdown-editor-container
          [:div.markdown-editor-content
           {:ref (fn [el]
                    (reset! editor-ref-atom el)
                    (when (and el (not @mounted) (:on-change opts))
                      (reset! mounted true)
                      (reset! editor-content-cb (:on-change opts))
                      (set! (.-innerHTML el) (or (:initial-content opts) ""))
                      (.addEventListener el "input"
                                         (fn [_]
                                           (let [md (editor-html->markdown (.-innerHTML el))]
                                             ((:on-change opts) md))))
                      (.addEventListener el "keydown"
                                         (fn [e]
                                            (when (and (= (.-key e) "Enter")
                                                       (.-shiftKey e))
                                             (let [sel (.getSelection js/window)]
                                               (when (and sel (pos? (.-rangeCount sel)))
                                                 (let [range (.getRangeAt sel 0)
                                                       container (.-startContainer range)
                                                       node (if (= 3 (.-nodeType container)) (.-parentElement container) container)]
                                                   (when-let [pre-node (when node (.closest node "pre"))]
                                                     (.preventDefault e)
                                                     (let [p (.createElement js/document "p")]
                                                       (.appendChild p (.createTextNode js/document "\u200B"))
                                                       (.insertAdjacentElement pre-node "afterend" p)
                                                       (let [new-range (.createRange js/document)]
                                                         (.setStart new-range p 0)
                                                         (.collapse new-range true)
                                                         (.removeAllRanges sel)
                                                         (.addRange sel new-range))
                                                       (when-let [cb @editor-content-cb]
                                                         (let [md (editor-html->markdown (.-innerHTML el))]
                                                            (cb md)))))))))))))
            :contentEditable true
            :data-placeholder (:placeholder opts "Write a comment...")}]]])})))

(defn format-date [iso-str]
  (when iso-str
    (let [d (js/Date. iso-str)
          now (js/Date.)
          diff-s (js/Math.floor (/ (- now d) 1000))
          locale @(rf/subscribe [:locale])]
      (if (< diff-s 43200)
        (cond
          (< diff-s 60)   (str diff-s (i18n/t locale :time/secs-ago))
          (< diff-s 3600) (let [m (js/Math.floor (/ diff-s 60))]
                            (str m (if (= m 1) (i18n/t locale :time/min-ago) (i18n/t locale :time/mins-ago))))
          :else            (let [h (js/Math.floor (/ diff-s 3600))]
                            (str h (if (= h 1) (i18n/t locale :time/hour-ago) (i18n/t locale :time/hours-ago)))))
        (.format (js/Intl.DateTimeFormat. js/undefined
                  #js {:year "numeric" :month "2-digit" :day "2-digit"
                       :hour "2-digit" :minute "2-digit" :hour12 false}) d)))))

(def statuses
  [{:id "backlog" :name-key :status/backlog :color "#6b7280"}
   {:id "open" :name-key :status/open :color "#3b82f6"}
   {:id "in_progress" :name-key :status/in-progress :color "#f59e0b"}
   {:id "review" :name-key :status/review :color "#8b5cf6"}
   {:id "done" :name-key :status/done :color "#10b981"}])

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
       [:h1.landing-title (or (:name app-info) (t :app/title))]
       [:p.landing-description
        (or (:description app-info)
            (t :app/description))]
       (if (:oauth2_configured app-info)
         [:a.login-button {:href "/api/auth/login"}
          (t :auth/sign-in)]
         [:div.landing-no-oauth
          [:p (t :auth/not-configured)]
          [:p (t :auth/config-hint)]])]]
     [:div.landing-footer
      [:p (t :app/version)]]]))

;;; Board components

(def priority-order
  {"high" 0 "medium" 1 "low" 2})

(defn priority-group-header [priority]
  (let [color (get-priority-color priority)]
    [:div.priority-group-header
     {:style {:border-left-color color}}
     [:span.priority-label
      {:style {:color color}}
      (case priority
        "low" (t :priority/low)
        "medium" (t :priority/medium)
        "high" (t :priority/high)
        priority)]]))

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
           {:style {:background-color (or (:color ticket) (get-priority-color (:priority ticket)))}}
           (case (:priority ticket)
             "low" (t :priority/low)
             "medium" (t :priority/medium)
             "high" (t :priority/high)
             (:priority ticket))]]
         [:h3.ticket-title (:title ticket)]
         (when (and (:assignee_id ticket)
                    (not= (:assignee_id ticket) "null")
                    (not (nil? (:assignee_id ticket))))
           [:div.ticket-assignee
            [:span.avatar
             (let [user-map @(rf/subscribe [:user-map])
                   user (get user-map (js/parseInt (:assignee_id ticket)))]
               (or (:username user) (str (t :ticket/user-prefix) (:assignee_id ticket))))]])]))))

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
      [:span.column-title (t (:name-key status))]
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
        (t :ticket/new)]
       (when @show-modal
         [:div.modal-overlay
          {:on-click #(reset! show-modal false)}
          [:div.modal
           {:on-click #(.stopPropagation %)}
           [:h2 (t :ticket/create)]
           [:div.form-group
            [:label (t :ticket/title)]
            [:input {:type "text"
                     :value @title
                     :on-change #(reset! title (-> % .-target .-value))
                     :placeholder (t :ticket/title-placeholder)}]]
           [:div.form-group
            [:label (t :ticket/description)]
            [:textarea {:value @description
                        :on-change #(reset! description (-> % .-target .-value))
                        :placeholder (t :ticket/description-placeholder)}]]
           [:div.form-group
            [:label (t :ticket/priority)]
            [:select {:value @priority
                      :on-change #(reset! priority (-> % .-target .-value))}
             [:option {:value "low"} (t :priority/low-label)]
             [:option {:value "medium"} (t :priority/medium-label)]
             [:option {:value "high"} (t :priority/high-label)]]]
           [:div.modal-actions
            [:button.cancel-button
             {:on-click #(reset! show-modal false)}
             (t :ticket/cancel)]
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
             (t :ticket/create-btn)]]]])])))



(defn ticket-detail-header [ticket users]
  [:div.ticket-detail-header
   [:button.back-button
    {:on-click #(js/navigateTo "/")}
    (t :ticket/back)]
   [:h1 (str "#" (:id ticket) " " (:title ticket))]
   [:div.ticket-meta
    [:select.status-select
     {:value (:status ticket)
      :style {:background-color (get-status-color (:status ticket))}
      :on-change (fn [e]
                   (rf/dispatch [:update-ticket-field
                                 (:id ticket)
                                 :status
                                 (-> e .-target .-value)]))}
     [:option {:value "backlog"} (t :status/backlog)]
     [:option {:value "open"} (t :status/open)]
     [:option {:value "in_progress"} (t :status/in-progress)]
     [:option {:value "review"} (t :status/review)]
     [:option {:value "done"} (t :status/done)]]
    [:select.priority-select
     {:value (:priority ticket)
      :style {:background-color (get-priority-color (:priority ticket))}
      :on-change (fn [e]
                   (rf/dispatch [:update-ticket-field
                                 (:id ticket)
                                 :priority
                                 (-> e .-target .-value)]))}
     [:option {:value "low"} (t :priority/low)]
     [:option {:value "medium"} (t :priority/medium)]
     [:option {:value "high"} (t :priority/high)]]
    (when (and (:assignee_id ticket)
               (not= (:assignee_id ticket) "null")
               (not (nil? (:assignee_id ticket))))
      [:span.assignee-badge
       (let [user (first (filter #(= (:id %) (js/parseInt (:assignee_id ticket))) users))]
         (or (:username user) (str (t :ticket/user-prefix) (:assignee_id ticket))))])]])

(defn comment-form [ticket-id new-comment user-id]
  (let [last-version (r/atom 0)]
    (fn [ticket-id new-comment user-id]
      (let [version @(rf/subscribe [:comment-form-version])]
        (when (and (> version @last-version) @editor-ref-atom)
          (reset! last-version version)
          (reset! new-comment "")
          (set! (.-innerHTML @editor-ref-atom) "")))
      [:div.comment-form
       [wysiwyg-editor {:on-change #(reset! new-comment %)
                         :placeholder (t :comment/add-placeholder)}]
       [:button.submit-button
        {:type "button"
         :on-click (fn []
                     (when (seq @new-comment)
                       (rf/dispatch [:create-comment
                                     ticket-id
                                     {:user_id user-id
                                      :body @new-comment}])))}
        (t :comment/add-btn)]])))

(defn comment-item [comment users]
  ^{:key (:id comment)}
  [:div.comment
   [:div.comment-header
    [:span.comment-user
     (let [author (first (filter #(= (:id %) (:user_id comment)) users))]
       (or (:username author) (str (t :ticket/user-prefix) (:user_id comment))))]
    [:span.comment-date (format-date (:created_at comment))]]
   [:div.comment-body
    {:dangerouslySetInnerHTML
     {:__html (or (md/render-markdown (:body comment)) "")}}]])

(defn comments-tab [ticket new-comment user-id users]
  (let [container (r/atom nil)
        observer (r/atom nil)]
    (r/create-class
     {:component-did-mount
      (fn [_this]
        (when-let [el @container]
          (let [sentinel (.querySelector el ".scroll-sentinel")
                obs (js/IntersectionObserver.
                     (fn [entries]
                       (when (.-isIntersecting (first entries))
                         (rf/dispatch [:load-more-comments (:id ticket)])))
                     #js {:rootMargin "100px"})]
            (when sentinel (.observe obs sentinel))
            (reset! observer obs))))
      :component-will-unmount
      (fn [_this]
        (when-let [o @observer] (.disconnect o)))
      :reagent-render
      (fn [ticket new-comment user-id users]
        (let [comments @(rf/subscribe [:comments])
              loading @(rf/subscribe [:comments-loading])
              has-more @(rf/subscribe [:has-more-comments])]
          [:div.ticket-section {:ref #(reset! container %)}
           [comment-form (:id ticket) new-comment user-id]
           [:div.comments-list
            (for [comment comments]
              ^{:key (:id comment)}
              [comment-item comment users])]
           (when loading
             [:div.loading-indicator (t :loading)])
           (when (and has-more (not loading))
             [:div.scroll-sentinel])]))})))

(defn parse-activity-details [item]
  (let [raw (cond
              (string? (:details item))
              (js->clj (js/JSON.parse (:details item)) :keywordize-keys true)
              (map? (:details item))
              (:details item)
              :else nil)]
    (if (vector? raw)
      (into {} (map (fn [[k v]] [(if (keyword? k) k (keyword k)) v]) raw))
      raw)))

(defn activity-action-content [item details actor-name]
  (let [locale @(rf/subscribe [:locale])
        status-span (fn [s]
                      (let [localized (case s
                                       "backlog" (i18n/t locale :status/backlog)
                                       "open" (i18n/t locale :status/open)
                                       "in_progress" (i18n/t locale :status/in-progress)
                                       "review" (i18n/t locale :status/review)
                                       "done" (i18n/t locale :status/done)
                                       s)]
                        [:span.activity-value
                         {:style {:color (get-status-color s)}}
                         localized]))
        priority-span (fn [p]
                        (let [localized (case p
                                          "low" (i18n/t locale :priority/low)
                                          "medium" (i18n/t locale :priority/medium)
                                          "high" (i18n/t locale :priority/high)
                                          p)]
                          [:span.activity-value
                           {:style {:color (get-priority-color p)}}
                           localized]))]
    (case (:action item)
      "created" [actor-name (i18n/t locale :activity/created)]
      "status_changed" [actor-name (i18n/t locale :activity/changed-status-from) [status-span (:from details)] (i18n/t locale :activity/to) [status-span (:to details)]]
      "priority_changed" [actor-name (i18n/t locale :activity/changed-priority-from) [priority-span (:from details)] (i18n/t locale :activity/to) [priority-span (:to details)]]
      "status_priority_changed" [actor-name (i18n/t locale :activity/changed-status-from) [status-span (:old-status details)] (i18n/t locale :activity/to) [status-span (:new-status details)] (i18n/t locale :activity/and-priority) [priority-span (:old-priority details)] (i18n/t locale :activity/to) [priority-span (:new-priority details)]]
      "title_changed" [actor-name (i18n/t locale :activity/changed-title)]
      "comment_added" (let [preview (when-let [body (:body details)]
                                      (when (string? body)
                                        (let [truncated (subs body 0 (min (count body) 50))]
                                          (if (> (count body) 50)
                                            (str truncated "...")
                                            truncated))))]
                        (if preview
                          [actor-name (i18n/t locale :activity/comment-preview) [:span.activity-value preview] (i18n/t locale :activity/comment-quote)]
                          [actor-name (i18n/t locale :activity/comment-added)]))
      [actor-name " " (:action item)])))

(defn activity-item [item user-map]
  (let [details (parse-activity-details item)
        actor (get user-map (:user_id item))
        actor-name (or (:username actor) (str (t :ticket/user-prefix) (:user_id item)))
        action-content (activity-action-content item details actor-name)]
    ^{:key (:id item)}
    [:div.activity-item
     (into [:span.activity-action] action-content)
     [:span.activity-date (format-date (:created_at item))]]))

(defn activity-tab []
  (let [container (r/atom nil)
        observer (r/atom nil)
        ticket-id (r/atom nil)]
    (r/create-class
     {:component-did-mount
      (fn [_this]
        (when-let [el @container]
          (let [sentinel (.querySelector el ".scroll-sentinel")
                obs (js/IntersectionObserver.
                     (fn [entries]
                       (when (and (.-isIntersecting (first entries)) @ticket-id)
                         (rf/dispatch [:load-more-activity @ticket-id])))
                     #js {:rootMargin "100px"})]
            (when sentinel (.observe obs sentinel))
            (reset! observer obs))))
      :component-will-unmount
      (fn [_this]
        (when-let [o @observer] (.disconnect o)))
      :reagent-render
      (fn []
        (let [activity @(rf/subscribe [:activity])
              user-map @(rf/subscribe [:user-map])
              loading @(rf/subscribe [:activity-loading])
              has-more @(rf/subscribe [:has-more-activity])
              ticket @(rf/subscribe [:current-ticket])]
          (reset! ticket-id (:id ticket))
          [:div.ticket-section {:ref #(reset! container %)}
           [:div.activity-list
            (for [item activity]
              ^{:key (:id item)}
              [activity-item item user-map])]
           (when loading
             [:div.loading-indicator (t :loading)])
           (when (and has-more (not loading))
             [:div.scroll-sentinel])]))})))

(defn ticket-detail []
  (let [new-comment (r/atom "")]
    (fn []
      (let [ticket @(rf/subscribe [:current-ticket])
            active-tab @(rf/subscribe [:active-tab])
            users @(rf/subscribe [:users])
            auth @(rf/subscribe [:auth])
            user-id (get-in auth [:user :id] 1)]
        (if ticket
          [:div.ticket-detail
           [ticket-detail-header ticket users]
           [:div.ticket-body
            [:p (:description ticket)]]
           [:div.ticket-tabs
             [:button.tab-button
              {:class (when (= active-tab :comments) "active")
               :on-click #(do (rf/dispatch [:set-active-tab :comments])
                              (js/setUrl (str "/tickets/" (:id ticket))))}
              (str (t :tab/comments) " (" @(rf/subscribe [:comment-count]) ")")]
             [:button.tab-button
              {:class (when (= active-tab :activity) "active")
               :on-click #(do (rf/dispatch [:set-active-tab :activity])
                              (js/setUrl (str "/tickets/" (:id ticket) "/activity")))}
              (str (t :tab/activity) " (" @(rf/subscribe [:activity-count]) ")")]]
           (if (= active-tab :comments)
             [comments-tab ticket new-comment user-id users]
             [activity-tab])]
          [:div.loading (t :loading)])))))



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
                                   :placeholder (t :nav/search)}]]))))

(defn language-switcher []
  (let [locale @(rf/subscribe [:locale])
        open? (r/atom false)
        ref (r/atom nil)
        on-click-outside
        (fn [e]
          (when (and @open? @ref)
            (when-not (.contains @ref (.-target e))
              (reset! open? false))))]
    (r/create-class
     {:component-did-mount
      (fn [] (.addEventListener js/document "mousedown" on-click-outside))
      :component-will-unmount
      (fn [] (.removeEventListener js/document "mousedown" on-click-outside))
      :reagent-render
      (fn []
        [:div.language-switcher {:ref #(reset! ref %)
                                 :class (when @open? "open")}
         [:button.language-button
          {:on-click #(swap! open? not)}
          [:span.language-icon "\u2328"]
          [:span.language-current (name locale)]]
         (when @open?
           [:div.language-dropdown
            (for [l i18n/supported-locales]
              ^{:key l}
              [:button.language-option
               {:class (when (= l locale) "active")
                :on-click (fn []
                            (rf/dispatch [:set-locale l])
                            (reset! open? false))}
               [:span.language-code (name l)]
               [:span.language-name (i18n/locale-display-name l)]])])])})))

(defn nav-bar []
  (let [current-view @(rf/subscribe [:current-view])
        auth @(rf/subscribe [:auth])]
    [:div.nav-bar
     [:div.nav-brand (t :app/title)]
     [:div.nav-links
      [:a {:class (when (= current-view :board) "active")
           :on-click #(js/navigateTo "/")}
       (t :nav/board)]
      [:a {:class (when (= current-view :list) "active")
           :on-click #(js/navigateTo "/")}
       (t :nav/list)]
      [create-ticket-modal]]
     [:div.nav-auth
      [language-switcher]
      (when-let [user (get auth :user)]
        [:span.user-name (:username user)])
      [:button.logout-button
       {:on-click #(rf/dispatch [:logout])}
       (t :nav/logout)]]]))

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
      [:div.loading-screen (t :loading)]
      (if authenticated?
        [app-panel]
        [landing-page]))))
