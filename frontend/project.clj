(defproject focus-frontend "0.0.1.3"
  :description "Focus issue tracker frontend"
  :license {:name "GPL-3.0-or-later"}
  :dependencies [[org.clojure/clojure "1.11.1"]
                 [org.clojure/clojurescript "1.11.60"]
                 [reagent "1.1.0"]
                 [re-frame "1.3.0"]
                 [day8.re-frame/http-fx "0.2.4"]
                 [cljs-ajax "0.8.4"]
                 [clj-commons/secretary "1.2.4"]
                 [cljsjs/react "17.0.2-0"]
                 [cljsjs/react-dom "17.0.2-0"]]
  :plugins [[lein-cljsbuild "1.1.8"]]
  :source-paths ["src"]
  :resource-paths ["resources"]
  :clean-targets ^{:protect false} ["resources/public/js" "target"]
  :cljsbuild {:builds [{:id "min"
                          :source-paths ["src"]
                             :compiler {:main focus.core
                                        :output-to "resources/public/js/app.js"
                                        :output-dir "target/cljsbuild/js"
                                        :externs ["resources/lucide.ext.js"]
                                        :optimizations :advanced
                                        :closure-warnings {:global-this :off}}}
                         {:id "test"
                          :source-paths ["test"]
                          :compiler {:main focus.parser-test
                                     :output-to "target/test.js"
                                     :output-dir "target/test-js"
                                     :target :nodejs
                                     :optimizations :none}}]})
