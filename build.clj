(ns build
  (:require [clojure.tools.build.api :as b]
            [deps-deploy.deps-deploy :as dd]))

(def lib 'org.yamlstar/yamlstar-plugin-json-comments)
(def version (or (System/getenv "VERSION") "0.1.9-SNAPSHOT"))
(def class-dir "target/classes")
(def basis (b/create-basis {:project "deps.edn"}))
(def jar-file (format "target/%s-%s.jar" (name lib) version))

(defn clean [_]
  (b/delete {:path "target"}))

(defn jar [_]
  (clean nil)
  (b/write-pom
   {:class-dir class-dir
    :lib lib
    :version version
    :basis basis
    :src-dirs ["src"]
    :scm {:url "https://github.com/yamlstar/yamlstar-plugin-json-comments"}
    :pom-data
    [[:description "JSON-style comment sanitizer plugin for YAMLStar"]
     [:url "https://github.com/yamlstar/yamlstar-plugin-json-comments"]
     [:licenses
      [:license
       [:name "MIT"]
       [:url "https://opensource.org/license/mit/"]]]]})
  (b/copy-dir {:src-dirs ["src"] :target-dir class-dir})
  (b/jar {:class-dir class-dir :jar-file jar-file})
  (println "Wrote" jar-file))

(defn deploy [_]
  (jar nil)
  (dd/deploy
   {:installer :remote
    :artifact jar-file
    :pom-file (b/pom-path {:lib lib :class-dir class-dir})}))
