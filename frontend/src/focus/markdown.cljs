(ns focus.markdown
  (:require [clojure.string :as str]))

(defn- escape-html [s]
  (-> s
      (str/replace "&" "&amp;")
      (str/replace "<" "&lt;")
      (str/replace ">" "&gt;")))

(defn- render-inline [text]
  (-> text
      escape-html
      (str/replace #"\*\*(.+?)\*\*" "<strong>$1</strong>")
      (str/replace #"\*(.+?)\*" "<em>$1</em>")
      (str/replace #"~~(.+?)~~" "<del>$1</del>")
      (str/replace #"`(.+?)`" "<code>$1</code>")
      (str/replace #"\[(.+?)\]\((.+?)\)" "<a href=\"$2\">$1</a>")))

(defn- close-lists [depth]
  (apply str (repeat depth "</ul>")))

(defn- render-markdown-inner [lines]
  (loop [remaining lines
         result []
         in-code false
         list-depth 0
         open-li? false]
    (if (empty? remaining)
      (let [close-all (apply str (repeat list-depth "</li></ul>"))]
        (str (apply str result) close-all))
      (let [line (first remaining)
            trimmed (str/trim line)
            leading (count (re-find #"^\s*" line))
            depth (max 1 (inc (quot leading 2)))]
        (cond
          (and (not in-code) (str/starts-with? trimmed "```"))
          (recur (rest remaining) (conj result "<pre><code>")
                 true list-depth open-li?)

          (and in-code (str/starts-with? trimmed "```"))
          (let [trimmed-result (if (and (seq result) (str/ends-with? (last result) "\n"))
                                 (update result (dec (count result)) #(subs % 0 (dec (count %))))
                                 result)]
            (recur (rest remaining) (conj trimmed-result "</code></pre>")
                   false list-depth open-li?))

          in-code
          (recur (rest remaining) (conj result (escape-html line) "\n")
                 true list-depth open-li?)

          (str/blank? trimmed)
          (recur (rest remaining)
                 (conj result (close-lists list-depth) "<br>")
                 false 0 false)

          (re-matches #"^#{1,6} .+$" trimmed)
          (let [level (count (re-find #"^#+" trimmed))
                text (subs trimmed (inc level))]
            (recur (rest remaining)
                   (conj result (close-lists list-depth)
                         (str "<h" level ">" (render-inline text) "</h" level ">"))
                   false 0 false))

          (re-matches #"^[-*_]{3,}$" trimmed)
          (recur (rest remaining)
                 (conj result (close-lists list-depth) "<hr>")
                 false 0 false)

          (re-matches #"^> .+$" trimmed)
          (recur (rest remaining)
                 (conj result (close-lists list-depth)
                       "<blockquote>" (render-inline (subs trimmed 2)) "</blockquote>")
                 false 0 false)

          (re-matches #"^[-*] .+$" trimmed)
          (let [close-li (if open-li?
                           (cond
                             (< depth list-depth)
                             (str (apply str (repeat (- list-depth depth) "</li></ul>")) "</li>")
                             (= depth list-depth)
                             "</li>"
                             :else "")
                           "")
                open-ul (if (> depth list-depth)
                          (apply str (repeat (- depth list-depth) "<ul>"))
                          "")
                new-list-depth depth]
            (recur (rest remaining)
                   (conj result close-li open-ul
                         "<li>" (render-inline (subs trimmed 2)))
                   false (max new-list-depth 1) true))

          (re-matches #"^\d+\..+$" trimmed)
          (let [offset (inc (count (re-find #"^\d+\." trimmed)))
                close-li (if open-li?
                           (cond
                             (< depth list-depth)
                             (str (apply str (repeat (- list-depth depth) "</li></ul>")) "</li>")
                             (= depth list-depth)
                             "</li>"
                             :else "")
                           "")
                open-ul (if (> depth list-depth)
                          (apply str (repeat (- depth list-depth) "<ul>"))
                          "")
                new-list-depth depth]
            (recur (rest remaining)
                   (conj result close-li open-ul
                         "<li>" (render-inline (subs trimmed offset)))
                   false (max new-list-depth 1) true))

          :else
          (recur (rest remaining)
                 (conj result (close-lists list-depth)
                       "<p>" (render-inline trimmed) "</p>")
                 false 0 false))))))

(defn render-markdown [md-string]
  (if-not (and md-string (string? md-string) (seq md-string))
    ""
    (render-markdown-inner (str/split-lines md-string))))
