(defproject org.yamlstar/yamlstar-plugin-json-comments "0.1.9-SNAPSHOT"
  :description "JSON-style comment sanitizer plugin for YAMLStar"
  :url "https://github.com/yamlstar/yamlstar-plugin-json-comments"
  :license {:name "MIT License"
            :url "https://opensource.org/licenses/MIT"}
  :dependencies [[org.clojure/clojure "1.12.0"]]
  :source-paths ["src"]
  :test-paths ["test"]
  :deploy-repositories
  [["releases" {:url "https://repo.clojars.org"
                :username :env/clojars_username
                :password :env/clojars_password
                :sign-releases false}]])
