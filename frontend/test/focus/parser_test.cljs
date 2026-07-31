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
                  items (remove #(re-matches #"^(?:<li[^>]*>\s*</li>|<li[^>]*>\s*)$" %) (extract-li-items content))
              before (subs html 0 start-pos)
              after (subs html end-pos)
              before (if (and (seq before)
                              (not (re-find #"\n$" before))
                              (not (re-find #"(?:</(?:div|p|blockquote)>|<br\s*/?>|>\s+)$" before)))
                       (str before "\n")
                       before)
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

(defn- blockquote-content-lines [html]
  "Split blockquote content into segments, separating inner blockquotes from surrounding text."
  (loop [h html segs []]
    (let [m (re-find #"<blockquote[^>]*>" h)]
      (if-not m
        (if (seq h) (conj segs h) segs)
        (let [start (.indexOf h m)
              before-part (subs h 0 start)
              close-pos (find-tag-end h (+ start (count m)) #"<blockquote[^>]*>" #"</blockquote>")]
          (if-not close-pos
            (conj segs h)
            (let [open-end (+ start (count m))
                  inner-end (- close-pos (count "</blockquote>"))
                  inner (subs h open-end inner-end)
                  after-part (subs h close-pos)
                  converted-inner (convert-blockquotes inner)
                  segs (if (seq before-part) (conj segs before-part) segs)
                  segs (conj segs converted-inner)]
              (recur after-part segs))))))))

(defn- convert-blockquotes [html]
  (let [m (re-find #"<blockquote[^>]*>" html)]
    (if-not m
      html
      (let [start (.indexOf html m)
            close-pos (find-tag-end html (+ start (count m)) #"<blockquote[^>]*>" #"</blockquote>")]
        (if-not close-pos
          html
          (let [open-end (+ start (count m))
                inner-end (- close-pos (count "</blockquote>"))
                inner (subs html open-end inner-end)
                before (subs html 0 start)
                after (subs html close-pos)
                segments (blockquote-content-lines inner)
                lines (map (fn [seg]
                             (if (re-find #"^> " seg)
                               seg
                               (str "> " seg)))
                           segments)
                converted (str/join "\n" lines)]
            (recur (str before converted after))))))))

(defn editor-html->markdown [html]
  (if-not (string? html)
    ""
    (-> html
        ;; Empty formatting tags first
        (str/replace #"<(?:strong|b|em|i|s|del)(?:[^>]*)>\s*</(?:strong|b|em|i|s|del)>" "")
        ;; Pre/code blocks
        (str/replace #"<pre[^>]*>\s*<code[^>]*>([\s\S]*?)</code>\s*</pre>" "```\n$1\n```\n")
        (str/replace #"<pre[^>]*>([\s\S]*?)</pre>" "```\n$1\n```\n")
        ;; Headings
        (str/replace #"<h1[^>]*>(.*?)</h1>" "# $1")
        (str/replace #"<h2[^>]*>(.*?)</h2>" "## $1")
        (str/replace #"<h3[^>]*>(.*?)</h3>" "### $1")
        (str/replace #"<h4[^>]*>(.*?)</h4>" "#### $1")
        (str/replace #"<h5[^>]*>(.*?)</h5>" "##### $1")
        (str/replace #"<h6[^>]*>(.*?)</h6>" "###### $1")
        ;; Inline formatting
        (str/replace #"<strong[^>]*>(.*?)</strong>" "**$1**")
        (str/replace #"<b[^>]*>(.*?)</b>" "**$1**")
        (str/replace #"<em[^>]*>(.*?)</em>" "*$1*")
        (str/replace #"<i[^>]*>(.*?)</i>" "*$1*")
        (str/replace #"<s[^>]*>(.*?)</s>" "~~$1~~")
        (str/replace #"<del[^>]*>(.*?)</del>" "~~$1~~")
        (str/replace #"<code[^>]*>(.*?)</code>" "`$1`")
        (str/replace #"<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>" "[$2]($1)")
        (str/replace #"<img[^>]*src=\"([^\"]+)\"[^>]*/?>" "![]($1)")
        (str/replace #"<hr\s*/?\s*>" "---\n")
        convert-blockquotes
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
          (recur (rest remaining) (conj result "<pre><code>") true list-types open-li?)
          (and in-code (str/starts-with? trimmed "```"))
          (let [trimmed-result (if (and (seq result) (str/ends-with? (last result) "\n"))
                                 (update result (dec (count result)) #(subs % 0 (dec (count %))))
                                 result)]
            (recur (rest remaining) (conj trimmed-result "</code></pre>") false list-types open-li?))
          in-code
          (recur (rest remaining) (conj result (escape-html line) "\n") true list-types open-li?)
          (str/blank? trimmed)
          (recur (rest remaining) (conj result (close-lists list-types) "<br>") false [] false)
          (re-matches #"^#{1,6} .+$" trimmed)
          (let [level (count (re-find #"^#+" trimmed))
                text (subs trimmed (inc level))]
            (recur (rest remaining) (conj result (close-lists list-types)
                                           (str "<h" level ">" (render-inline text) "</h" level ">"))
                   false [] false))
          (re-matches #"^[-*_]{3,}$" trimmed)
          (recur (rest remaining) (conj result (close-lists list-types) "<hr>") false [] false)
          (re-matches #"^> .+$" trimmed)
          (recur (rest remaining) (conj result (close-lists list-types)
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
            (recur (rest remaining) (conj result close-li open-tags
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
            (recur (rest remaining) (conj result close-li open-tags
                                           "<li>" (render-inline (subs trimmed offset)))
                   false new-list-types true))
          :else
          (recur (rest remaining) (conj result (close-lists list-types)
                                         "<p>" (render-inline trimmed) "</p>")
                 false [] false))))))

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
        ;; Strip outer <p> wrapper for comparison
        strip-p (fn [s] (-> s
                            (str/replace #"^<p>" "")
                            (str/replace #"</p>$" "")))
        pass (= (strip-p back) (strip-p html))]
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

(test-case "simple ordered list"
  "<ol><li>first</li><li>second</li><li>third</li></ol>"
  "1. first\n2. second\n3. third")

(test-case "nested ordered list"
  "<ol><li>one<ol><li>two</li></ol></li><li>three</li></ol>"
  "1. one\n  1. two\n2. three")

(test-case "mixed list unordered in ordered"
  "<ol><li>one<ul><li>two</li></ul></li><li>three</li></ol>"
  "1. one\n  - two\n2. three")

(test-case "mixed list ordered in unordered"
  "<ul><li>one<ol><li>two</li></ol></li><li>three</li></ul>"
  "- one\n  1. two\n- three")

(test-case "ol wrapping ul (browser artifact)"
  "<ol><ul><li>a</li><li>b</li></ul></ol>"
  "1. a\n2. b")

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

(test-case "text before unordered list"
  "test@123<ul><li>1</li><li>2</li></ul>"
  "test@123\n- 1\n- 2")

(test-case "text before ordered list"
  "hello<ol><li>a</li><li>b</li></ol>"
  "hello\n1. a\n2. b")

(test-case "div-wrapped text before list"
  "<div>test@123</div><ul><li>1</li><li>2</li></ul>"
  "test@123\n- 1\n- 2")

(test-case "text inside li before nested list"
  "<ul><li>test@123<ul><li>1</li></ul></li></ul>"
  "- test@123\n  - 1")

(test-case "text after list"
  "<ul><li>1</li></ul>trailing"
  "- 1\ntrailing")

(test-case "list between text"
  "before<ul><li>1</li></ul>after"
  "before\n- 1\nafter")

(test-case "u tag stripped"
  "<u>underlined</u>" "underlined")

(test-case "span tag stripped"
  "<span class=\"x\">text</span>" "text")

(test-case "nested bold and italic"
  "<strong><em>both</em></strong>" "***both***")

(test-case "bold containing inline code"
  "<strong>x: <code>y</code></strong>" "**x: `y`**")

(test-case "inline code decodes html entities"
  "<code>&amp;</code>" "`&`")

(test-case "empty list items ignored"
  "<ul><li></li><li>second</li></ul>" "- second")

(test-case "br inside list item"
  "<ul><li>line1<br>line2</li></ul>" "- line1\nline2")

(test-case "multiple paragraphs"
  "<p>one</p><p>two</p>" "one\ntwo")

(test-case "hr tag"
  "<hr>" "---")

(test-case "blockquote with bold"
  "<blockquote><strong>bold</strong> text</blockquote>" "> **bold** text")

(test-case "nested blockquotes"
  "<blockquote>outer<blockquote>inner</blockquote></blockquote>"
  "> outer\n> inner")

(test-case "link inside bold"
  "<strong><a href=\"http://x.com\">link</a></strong>" "**[link](http://x.com)**")

(test-case "img with alt"
  "<img src=\"pic.png\" alt=\"Pic\">" "![](pic.png)")

(test-case "mixed inline formatting"
  "hello <strong>world</strong> <em>!</em>"
  "hello **world** *!*")

(test-case "bold at start no space after"
  "<strong>bold</strong>text" "**bold**text")

(test-case "italic adjacent to bold"
  "<em>a</em><strong>b</strong>" "*a***b**")

(test-case "text after heading before list"
  "<h2>Title</h2><ul><li>item</li></ul>" "## Title\n- item")

(test-case "code block with multiline"
  "<pre><code>line1\nline2\nline3</code></pre>" "```\nline1\nline2\nline3\n```")

(test-case "paragraph with br"
  "<p>line1<br>line2</p>" "line1\nline2")

(test-case "stripped tags leave content"
  "<div><span>text</span></div>" "text")

(test-case "empty strong removed"
  "<strong></strong>text" "text")

(test-case "bold then plain"
  "<strong>a</strong>b" "**a**b")

(test-case "italic with spaces"
  "<em> a </em>" "* a *")

;; --- Edge case batch: real-world editor scenarios ---

(test-case "empty div with br"
  "<div><br></div>" "")

(test-case "empty p"
  "<p></p>" "")

(test-case "p with only br"
  "<p><br></p>" "")

(test-case "multiple brs collapse"
  "<p>a<br><br>b</p>" "a\n\nb")

(test-case "table tags stripped"
  "<table><tr><td>cell</td></tr></table>" "cell")

(test-case "sup tag stripped"
  "<p>x<sup>2</sup></p>" "x2")

(test-case "sub tag stripped"
  "<p>H<sub>2</sub>O</p>" "H2O")

(test-case "u tag stripped"
  "<p><u>underline</u></p>" "underline")

(test-case "mark tag stripped"
  "<p><mark>highlighted</mark></p>" "highlighted")

(test-case "img with alt text"
  "<img src=\"pic.png\" alt=\"Photo\">" "![](pic.png)")

(test-case "img without alt"
  "<img src=\"pic.png\">" "![](pic.png)")

(test-case "a tag with empty href"
  "<a href=\"\">link</a>" "link")

(test-case "link with special chars"
  "<a href=\"http://x.com/path?q=1&b=2\">click</a>" "[click](http://x.com/path?q=1&b=2)")

(test-case "heading h3"
  "<h3>Sub</h3>" "### Sub")

(test-case "heading h6"
  "<h6>Tiny</h6>" "###### Tiny")

(test-case "heading with bold inside"
  "<h1><strong>Title</strong></h1>" "# **Title**")

(test-case "blockquote with nested bold"
  "<blockquote>text <strong>bold</strong></blockquote>" "> text **bold**")

(test-case "blockquote with list inside"
  "<blockquote><ul><li>item</li></ul></blockquote>" "> - item")

(test-case "blockquote with code"
  "<blockquote><code>x</code></blockquote>" "> `x`")

(test-case "nested bold and italic mixed"
  "<strong>bold <em>italic</em></strong>" "**bold *italic***")

(test-case "italic containing bold"
  "<em>text <strong>bold</strong></em>" "*text **bold***")

(test-case "bold containing italic containing code"
  "<strong><em><code>x</code></em></strong>" "***`x`***")

(test-case "three inline elements"
  "<em>a</em><strong>b</strong><code>c</code>" "*a***b**`c`")

(test-case "bold with no content"
  "<strong></strong>" "")

(test-case "em with no content"
  "<em></em>" "")

(test-case "s with no content"
  "<s></s>" "")

(test-case "code with no content"
  "<code></code>" "``")

(test-case "link with no text"
  "<a href=\"http://x.com\"></a>" "[](http://x.com)")

(test-case "p containing only strong"
  "<p><strong>text</strong></p>" "**text**")

(test-case "p containing only code"
  "<p><code>x</code></p>" "`x`")

(test-case "div with br between paragraphs"
  "<p>one</p><div><br></div><p>two</p>" "one\n\ntwo")

(test-case "heading immediately before list no gap"
  "<h2>Title</h2><ul><li>a</li><li>b</li></ul>" "## Title\n- a\n- b")

(test-case "hr between paragraphs"
  "<p>above</p><hr><p>below</p>" "above\n---\nbelow")

(test-case "list then heading"
  "<ul><li>item</li></ul><h3>Next</h3>" "- item\n### Next")

(test-case "code block then heading"
  "<pre><code>code</code></pre><h2>Title</h2>" "```\ncode\n```\n## Title")

(test-case "bold text adjacent to code"
  "<strong>bold</strong><code>code</code>" "**bold**`code`")

(test-case "text with ampersand"
  "<p>A &amp; B</p>" "A & B")

(test-case "text with less than"
  "<p>x &lt; y</p>" "x < y")

(test-case "text with greater than"
  "<p>x &gt; y</p>" "x > y")

(test-case "nbsp in text"
  "<p>a&nbsp;b</p>" "a b")

(test-case "zero width space removed"
  "<p>a\u200Bb</p>" "ab")

(test-case "complex nested structure"
  "<div><p>text <strong>bold</strong></p><ul><li>item</li></ul></div>"
  "text **bold**\n- item")

(test-case "whitespace only text"
  "   " "")

(test-case "just newlines"
  "\n\n\n" "")

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

(test-render "ordered list"
  "1. first\n2. second\n3. third"
  "<ol><li>first</li><li>second</li><li>third</li></ol>")

(test-render "nested ordered list"
  "1. one\n  1. two\n2. three"
  "<ol><li>one<ol><li>two</li></ol></li><li>three</li></ol>")

(test-render "code block"
  "```\ncode\n```" "<pre><code>code</code></pre>")

(test-render "link"
  "[text](http://x.com)" "<p><a href=\"http://x.com\">text</a></p>")

(test-render "image"
  "![alt](pic.png)" "<p><img src=\"pic.png\" alt=\"alt\"></p>")

(test-render "heading with bold"
  "# **Title**" "<h1><strong>Title</strong></h1>")

(test-render "heading with code"
  "# `Title`" "<h1><code>Title</code></h1>")

(test-render "blockquote with bold"
  "> **bold** text" "<blockquote><strong>bold</strong> text</blockquote>")

(test-render "blockquote with code"
  "> `x` = 1" "<blockquote><code>x</code> = 1</blockquote>")

(test-render "list with bold items"
  "- **a**\n- b" "<ul><li><strong>a</strong></li><li>b</li></ul>")

(test-render "ordered list with italic"
  "1. *a*\n2. b" "<ol><li><em>a</em></li><li>b</li></ol>")

(test-render "code block preserves content"
  "```\n<>&\"\\\n```" "<pre><code>&lt;&gt;&amp;\"\\</code></pre>")

(test-render "inline code preserves special"
  "`<script>`" "<p><code>&lt;script&gt;</code></p>")

(test-render "hr with underscores"
  "___" "<hr>")

(test-render "hr with stars"
  "***" "<hr>")

(test-render "h4 heading"
  "#### Deep" "<h4>Deep</h4>")

(test-render "h5 heading"
  "##### Deeper" "<h5>Deeper</h5>")

(test-render "h6 heading"
  "###### Deepest" "<h6>Deepest</h6>")

(test-render "paragraph with bold and italic"
  "a **b** *c*" "<p>a <strong>b</strong> <em>c</em></p>")

(test-render "strikethrough in paragraph"
  "~~old~~ new" "<p><del>old</del> new</p>")

(test-render "link with parens in url"
  "[click](http://x.com/a(b))" "<p><a href=\"http://x.com/a(b\">click</a>)</p>")

(test-render "unordered list with asterisk"
  "* one\n* two" "<ul><li>one</li><li>two</li></ul>")

(test-render "blockquote after paragraph"
  "text\n> quote" "<p>text</p><blockquote>quote</blockquote>")

(test-render "code block then list"
  "```\ncode\n```\n- item" "<pre><code>code</code></pre><ul><li>item</li></ul>")

(test-render "heading then code block"
  "# Title\n```\ncode\n```" "<h1>Title</h1><pre><code>code</code></pre>")

(test-case "code block followed by list"
  "<pre><code>test1\ntest2</code></pre><ul><li>1</li><li>2</li></ul>"
  "```\ntest1\ntest2\n```\n- 1\n- 2")

(test-case "code block followed by list no blank line"
  "<pre><code>code</code></pre><ul><li>item</li></ul>"
  "```\ncode\n```\n- item")

(test-case "code block followed by list with intermediate paragraph"
  "<pre><code>code</code></pre><p>text</p><ul><li>item</li></ul>"
  "```\ncode\n```\ntext\n- item")

(println)
(println "=== ROUNDTRIP ===")
(println)

(test-roundtrip "simple list"
  "<ul><li>1</li><li>2</li></ul>")

(test-roundtrip "nested list"
  "<ul><li>1<ul><li>2</li></ul></li><li>3</li></ul>")

(test-roundtrip "deep nested"
  "<ul><li>a<ul><li>b<ul><li>c</li></ul></li></ul></li></ul>")

(test-roundtrip "code block followed by list"
  "<pre><code>test1\ntest2</code></pre><ul><li>1</li><li>2</li></ul>")

(test-roundtrip "simple ordered list"
  "<ol><li>first</li><li>second</li><li>third</li></ol>")

(test-roundtrip "nested ordered list"
  "<ol><li>one<ol><li>two</li></ol></li><li>three</li></ol>")

(test-render "h2 heading"
  "## Title" "<h2>Title</h2>")

(test-render "h3 heading"
  "### Sub" "<h3>Sub</h3>")

(test-render "bold and italic combined"
  "***both***" "<p><strong><em>both</strong></em></p>")

(test-render "unordered list with dash"
  "- one\n- two" "<ul><li>one</li><li>two</li></ul>")

(test-render "single paragraph"
  "just text" "<p>just text</p>")

(test-render "two lines one paragraph"
  "line1\nline2" "<p>line1</p><p>line2</p>")

(test-render "heading then paragraph"
  "# Title\n\nbody" "<h1>Title</h1><br><p>body</p>")

(test-roundtrip "bold"
  "<strong>text</strong>")

(test-roundtrip "italic"
  "<em>text</em>")

(test-roundtrip "inline code"
  "<code>x</code>")

(test-roundtrip "heading"
  "<h1>Title</h1>")

(test-roundtrip "hr"
  "<hr>")

(test-roundtrip "blockquote"
  "<blockquote>quote</blockquote>")

(test-roundtrip "text before list"
  "<p>text</p><ul><li>1</li><li>2</li></ul>")

(test-roundtrip "div-wrapped text before list"
  "<p>text</p><ul><li>1</li></ul>")

(test-roundtrip "list then text"
  "<ul><li>1</li></ul><p>trailing</p>")

(test-roundtrip "bold in paragraph"
  "<p><strong>text</strong></p>")

(test-roundtrip "italic in paragraph"
  "<p><em>text</em></p>")

(test-roundtrip "code in paragraph"
  "<p><code>x</code></p>")

(test-roundtrip "link in paragraph"
  "<p><a href=\"http://x.com\">text</a></p>")

(test-roundtrip "heading with bold"
  "<h1><strong>Title</strong></h1>")

(test-roundtrip "h2 heading"
  "<h2>Title</h2>")

(test-roundtrip "hr alone"
  "<hr>")

(test-roundtrip "blockquote with bold"
  "<blockquote><strong>bold</strong> text</blockquote>")

(test-roundtrip "list with bold items"
  "<ul><li><strong>a</strong></li><li>b</li></ul>")

(test-roundtrip "ordered list"
  "<ol><li>first</li><li>second</li></ol>")

(test-roundtrip "mixed list unordered in ordered"
  "<ol><li>one<ul><li>two</li></ul></li><li>three</li></ol>")

(test-roundtrip "code block with multiline"
  "<pre><code>line1\nline2</code></pre>")

(test-roundtrip "hr between paragraphs"
  "<p>above</p><hr><p>below</p>")

(test-roundtrip "heading then list"
  "<h2>Title</h2><ul><li>item</li></ul>")

(test-roundtrip "list then heading"
  "<ul><li>item</li></ul><h3>Next</h3>")

(test-roundtrip "blockquote with code"
  "<blockquote><code>x</code></blockquote>")

(test-roundtrip "bold adjacent to code"
  "<p><strong>a</strong><code>b</code></p>")

(println)
(println (str "RESULTS: " @pass-count " passed, " @fail-count " failed"))
(.exit js/process (if (zero? @fail-count) 0 1))
