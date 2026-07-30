(ns focus.parser-test
  (:require [clojure.string :as str]))

;; --- Copied parser functions (no re-frame dependency) ---

(defn- find-tag-end [html start-pos open-re close-re]
  (loop [pos start-pos depth 1]
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
          (recur (subs in (count ul-start-m)) items li-depth (str current ul-start-m))
          ul-end-m
          (recur (subs in (count ul-end-m)) items li-depth (str current ul-end-m))
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
       (let [tag-type (if ul-m "ul" "ol")
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
                                  (map (fn [item]
                                         (let [text (item-text item)
                                               nested (item-nested item)]
                                           (str indent "- " text "\n"
                                                (when nested (html-lists->markdown nested (inc depth))))))
                                       items))]
             (recur (str before converted after) depth))))))))

(defn- process-list-blocks [html]
  (html-lists->markdown html))

(defn editor-html->markdown [html]
  (if-not (string? html)
    ""
    (-> html
        (str/replace #"<pre[^>]*>\s*<code[^>]*>([\s\S]*?)</code>\s*</pre>" "```\n$1\n```")
        (str/replace #"<pre[^>]*>([\s\S]*?)</pre>" "```\n$1\n```")
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

;; --- Markdown renderer (copied) ---

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
  (loop [remaining lines result [] in-code false list-depth 0 open-li? false]
    (if (empty? remaining)
      (let [close-all (apply str (repeat list-depth "</li></ul>"))]
        (str (apply str result) close-all))
      (let [line (first remaining)
            trimmed (str/trim line)
            leading (count (re-find #"^\s*" line))
            depth (max 1 (inc (quot leading 2)))]
        (cond
          (and (not in-code) (str/starts-with? trimmed "```"))
          (recur (rest remaining) (conj result "<pre><code>") true list-depth open-li?)
          (and in-code (str/starts-with? trimmed "```"))
          (let [trimmed-result (if (and (seq result) (str/ends-with? (last result) "\n"))
                                 (update result (dec (count result)) #(subs % 0 (dec (count %))))
                                 result)]
            (recur (rest remaining) (conj trimmed-result "</code></pre>") false list-depth open-li?))
          in-code
          (recur (rest remaining) (conj result (escape-html line) "\n") true list-depth open-li?)
          (str/blank? trimmed)
          (recur (rest remaining) (conj result (close-lists list-depth) "<br>") false 0 false)
          (re-matches #"^#{1,6} .+$" trimmed)
          (let [level (count (re-find #"^#+" trimmed))
                text (subs trimmed (inc level))]
            (recur (rest remaining) (conj result (close-lists list-depth)
                                           (str "<h" level ">" (render-inline text) "</h" level ">"))
                   false 0 false))
          (re-matches #"^[-*_]{3,}$" trimmed)
          (recur (rest remaining) (conj result (close-lists list-depth) "<hr>") false 0 false)
          (re-matches #"^> .+$" trimmed)
          (recur (rest remaining) (conj result (close-lists list-depth)
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
            (recur (rest remaining) (conj result close-li open-ul
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
            (recur (rest remaining) (conj result close-li open-ul
                                           "<li>" (render-inline (subs trimmed offset)))
                   false (max new-list-depth 1) true))
          :else
          (recur (rest remaining) (conj result (close-lists list-depth)
                                         "<p>" (render-inline trimmed) "</p>")
                 false 0 false))))))

(defn render-markdown [md-string]
  (if-not (and md-string (string? md-string) (seq md-string))
    ""
    (render-markdown-inner (str/split-lines md-string))))

;; --- Test framework ---

(def pass-count (atom 0))
(def fail-count (atom 0))

(defn test-case [name input expected]
  (let [actual (editor-html->markdown input)
        pass (= actual expected)]
    (if pass
      (do (swap! pass-count inc) (println "PASS:" name))
      (do (swap! fail-count inc)
          (println "FAIL:" name)
          (println "  input:" (pr-str input))
          (println "  expected:" (pr-str expected))
          (println "  actual:" (pr-str actual))))
    pass))

(defn test-render [name input expected]
  (let [actual (render-markdown input)
        pass (= actual expected)]
    (if pass
      (do (swap! pass-count inc) (println "PASS:" name))
      (do (swap! fail-count inc)
          (println "FAIL:" name)
          (println "  input:" (pr-str input))
          (println "  expected:" (pr-str expected))
          (println "  actual:" (pr-str actual))))
    pass))

(defn test-roundtrip [name html]
  (let [md (editor-html->markdown html)
        back (render-markdown md)
        pass (= back html)]
    (if pass
      (do (swap! pass-count inc) (println "PASS roundtrip:" name))
      (do (swap! fail-count inc)
          (println "FAIL roundtrip:" name)
          (println "  html:" (pr-str html))
          (println "  markdown:" (pr-str md))
          (println "  back to html:" (pr-str back))))
    pass))

;; --- Run tests ---

(println "=== HTML -> MARKDOWN ===")
(println)

(test-case "simple bold"
  "<strong>hello</strong>" "**hello**")

(test-case "simple italic"
  "<em>hello</em>" "*hello*")

(test-case "simple code"
  "<code>foo</code>" "`foo`")

(test-case "link"
  "<a href=\"http://x.com\">click</a>" "[click](http://x.com)")

(test-case "blockquote"
  "<blockquote>quoted</blockquote>" "> quoted")

(test-case "simple bullet list"
  "<ul><li>1</li><li>2</li></ul>"
  "- 1\n- 2")

(test-case "nested bullet list"
  "<ul><li>1<ul><li>2</li></ul></li><li>3</li></ul>"
  "- 1\n  - 2\n- 3")

(test-case "deeply nested list"
  "<ul><li>a<ul><li>b<ul><li>c</li></ul></li></ul></li></ul>"
  "- a\n  - b\n    - c")

(test-case "code block pre"
  "<pre><code>line1</code></pre>"
  "```\nline1\n```")

(test-case "code block pre only"
  "<pre>raw text</pre>"
  "```\nraw text\n```")

(test-case "paragraph with bold"
  "<p>hello <strong>world</strong></p>"
  "hello **world**")

(test-case "empty"
  "" "")

(test-case "plain text"
  "just text" "just text")

(test-case "strip unknown tags"
  "<div><span>text</span></div>" "text")

(test-case "bullet list with nested"
  "<ul><li>A<ul><li>B<ul><li>C</li></ul></li></ul></li><li>D</li></ul>"
  "- A\n  - B\n    - C\n- D")

(test-case "two sequential lists"
  "<ul><li>1</li></ul><ul><li>2</li></ul>"
  "- 1\n- 2")

(println)
(println "=== MARKDOWN -> HTML ===")
(println)

(test-render "plain text"
  "hello world" "<p>hello world</p>")

(test-render "bold"
  "**bold**" "<p><strong>bold</strong></p>")

(test-render "italic"
  "*italic*" "<p><em>italic</em></p>")

(test-render "strikethrough"
  "~~deleted~~" "<p><del>deleted</del></p>")

(test-render "inline code"
  "`code`" "<p><code>code</code></p>")

(test-render "heading"
  "# Title" "<h1>Title</h1>")

(test-render "hr"
  "---" "<hr>")

(test-render "blockquote"
  "> quote" "<blockquote>quote</blockquote>")

(test-render "bullet list"
  "- one\n- two" "<ul><li>one</li><li>two</li></ul>")

(test-render "nested bullet list"
  "- one\n  - two\n- three"
  "<ul><li>one<ul><li>two</li></ul></li><li>three</li></ul>")

(test-render "code block"
  "```\ncode\n```" "<pre><code>code</code></pre>")

(test-render "link"
  "[text](http://x.com)" "<p><a href=\"http://x.com\">text</a></p>")

(println)
(println "=== ROUNDTRIP ===")
(println)

(test-roundtrip "simple list"
  "<ul><li>1</li><li>2</li></ul>")

(test-roundtrip "nested list"
  "<ul><li>1<ul><li>2</li></ul></li><li>3</li></ul>")

(test-roundtrip "deep nested"
  "<ul><li>a<ul><li>b<ul><li>c</li></ul></li></ul></li></ul>")

(println)
(println (str "RESULTS: " @pass-count " passed, " @fail-count " failed"))
(.exit js/process (if (zero? @fail-count) 0 1))
