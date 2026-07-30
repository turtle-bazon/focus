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

(defn render-markdown [md-string]
  (if-not (and md-string (string? md-string) (seq md-string))
    ""
    (let [lines (str/split-lines md-string)]
      (loop [remaining lines
             result []
             in-code false
             in-ul false
             in-ol false]
        (if (empty? remaining)
          (str (apply str result)
               (if in-ul "</ul>" "")
               (if in-ol "</ol>" ""))
          (let [line (first remaining)
                trimmed (str/trim line)]
            (cond
              ;; code block fence
              (and (not in-code) (str/starts-with? trimmed "```"))
              (recur (rest remaining) (conj result "<pre><code>")
                     true in-ul in-ol)

              (and in-code (str/starts-with? trimmed "```"))
              (recur (rest remaining) (conj result "</code></pre>")
                     false in-ul in-ol)

              in-code
              (recur (rest remaining) (conj result (escape-html line) "\n")
                     true in-ul in-ol)

              ;; blank line
              (str/blank? trimmed)
              (recur (rest remaining) (conj result
                                             (if in-ul "</ul>" "")
                                             (if in-ol "</ol>" "")
                                             "<br>")
                     false false false)

              ;; heading
              (re-matches #"^#{1,6} .+$" trimmed)
              (let [level (count (re-find #"^#+" trimmed))
                    text (subs trimmed (inc level))]
                (recur (rest remaining)
                       (conj result
                             (if in-ul "</ul>" "")
                             (if in-ol "</ol>" "")
                             (str "<h" level ">" (render-inline text) "</h" level ">"))
                       false false false))

              ;; hr
              (re-matches #"^[-*_]{3,}$" trimmed)
              (recur (rest remaining)
                     (conj result
                           (if in-ul "</ul>" "")
                           (if in-ol "</ol>" "")
                           "<hr>")
                     false false false)

              ;; blockquote
              (re-matches #"^> .+$" trimmed)
              (recur (rest remaining)
                     (conj result
                           (if in-ul "</ul>" "")
                           (if in-ol "</ol>" "")
                           "<blockquote>" (render-inline (subs trimmed 2)) "</blockquote>")
                     false false false)

              ;; unordered list
              (re-matches #"^[-*] .+$" trimmed)
              (recur (rest remaining)
                     (conj result
                           (if-not in-ul "<ul>" "")
                           "<li>" (render-inline (subs trimmed 2)) "</li>")
                     false true in-ol)

              ;; ordered list
              (re-matches #"^\d+\..+$" trimmed)
              (let [offset (inc (count (re-find #"^\d+\." trimmed)))]
                (recur (rest remaining)
                       (conj result
                             (if-not in-ol "<ol>" "")
                             "<li>" (render-inline (subs trimmed offset)) "</li>")
                       false in-ul true))

              ;; paragraph
              :else
              (recur (rest remaining)
                     (conj result
                           (if in-ul "</ul>" "")
                           (if in-ol "</ol>" "")
                           "<p>" (render-inline trimmed) "</p>")
                     false false false))))))))
