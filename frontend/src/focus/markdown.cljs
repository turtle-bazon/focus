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
      (str/replace #"!\[(.+?)\]\((.+?)\)" "<img src=\"$2\" alt=\"$1\">")
      (str/replace #"\*\*(.+?)\*\*" "<strong>$1</strong>")
      (str/replace #"\*(.+?)\*" "<em>$1</em>")
      (str/replace #"~~(.+?)~~" "<del>$1</del>")
      (str/replace #"`(.+?)`" "<code>$1</code>")
      (str/replace #"\[(.+?)\]\((.+?)\)" "<a href=\"$2\">$1</a>")))

(defn- close-lists [list-types]
  (apply str (map #(str "</li></" % ">") (reverse list-types))))

(defn- render-markdown-inner [lines]
  (loop [remaining lines result [] in-code false list-types [] open-li? false]
    (if (empty? remaining)
      (let [close-all (close-lists list-types)]
        (str (apply str result) close-all))
      (let [line (first remaining)
            trimmed (str/trim line)
            leading (count (re-find #"^\s*" line))
            depth (max 1 (inc (quot leading 2)))]
        (cond
          (and (not in-code) (str/starts-with? trimmed "```"))
          (recur (rest remaining) (conj result "<pre><code>")
                 true list-types open-li?)

          (and in-code (str/starts-with? trimmed "```"))
          (let [trimmed-result (if (and (seq result) (str/ends-with? (last result) "\n"))
                                 (update result (dec (count result)) #(subs % 0 (dec (count %))))
                                 result)]
            (recur (rest remaining) (conj trimmed-result "</code></pre>")
                   false list-types open-li?))

          in-code
          (recur (rest remaining) (conj result (escape-html line) "\n")
                 true list-types open-li?)

          (str/blank? trimmed)
          (recur (rest remaining)
                 (conj result (close-lists list-types) "<br>")
                 false [] false)

          (re-matches #"^#{1,6} .+$" trimmed)
          (let [level (count (re-find #"^#+" trimmed))
                text (subs trimmed (inc level))]
            (recur (rest remaining)
                   (conj result (close-lists list-types)
                         (str "<h" level ">" (render-inline text) "</h" level ">"))
                   false [] false))

          (re-matches #"^[-*_]{3,}$" trimmed)
          (recur (rest remaining)
                 (conj result (close-lists list-types) "<hr>")
                 false [] false)

          (re-matches #"^> .+$" trimmed)
          (recur (rest remaining)
                 (conj result (close-lists list-types)
                       "<blockquote>" (render-inline (subs trimmed 2)) "</blockquote>")
                 false [] false)

          (re-matches #"^[-*] .+$" trimmed)
          (let [close-li (if open-li?
                           (cond
                             (< depth (count list-types))
                             (str (apply str (map #(str "</li></" % ">")
                                                 (reverse (subvec list-types depth))))
                                  "</li>")
                             (= depth (count list-types))
                             "</li>"
                             :else "")
                           "")
                num-new (- depth (count list-types))
                open-tags (if (> num-new 0)
                            (apply str (repeat num-new "<ul>"))
                            "")
                new-list-types (if (> num-new 0)
                                (vec (concat list-types (repeat num-new "ul")))
                                (if (< depth (count list-types))
                                  (subvec list-types 0 depth)
                                  list-types))]
            (recur (rest remaining)
                   (conj result close-li open-tags
                         "<li>" (render-inline (subs trimmed 2)))
                   false new-list-types true))

          (re-matches #"^\d+\..+$" trimmed)
          (let [offset (inc (count (re-find #"^\d+\." trimmed)))
                close-li (if open-li?
                           (cond
                             (< depth (count list-types))
                             (str (apply str (map #(str "</li></" % ">")
                                                 (reverse (subvec list-types depth))))
                                  "</li>")
                             (= depth (count list-types))
                             "</li>"
                             :else "")
                           "")
                num-new (- depth (count list-types))
                open-tags (if (> num-new 0)
                            (apply str (cons "<ol>" (repeat (dec num-new) "<ul>")))
                            "")
                new-list-types (if (> num-new 0)
                                (vec (concat list-types
                                             (cons "ol" (repeat (dec num-new) "ul"))))
                                (if (< depth (count list-types))
                                  (subvec list-types 0 depth)
                                  list-types))]
            (recur (rest remaining)
                   (conj result close-li open-tags
                         "<li>" (render-inline (subs trimmed offset)))
                   false new-list-types true))

          :else
          (recur (rest remaining)
                 (conj result (close-lists list-types)
                       "<p>" (render-inline trimmed) "</p>")
                 false [] false))))))

(defn render-markdown [md-string]
  (if-not (and md-string (string? md-string) (seq md-string))
    ""
    (render-markdown-inner (str/split-lines md-string))))
