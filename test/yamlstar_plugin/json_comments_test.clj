(ns yamlstar-plugin.json-comments-test
  (:require [clojure.string :as str]
            [clojure.test :refer [deftest is run-tests testing]]
            [yaml-parser.core :as parser]
            [yamlstar-plugin.json-comments :as comments]))

(defn events
  [input]
  (comments/parse-events input "{}"))

(defn scalar-values
  [input]
  (->> (events input)
       (filter #(= "scalar" (:event %)))
       (mapv :value)))

(deftest comments-after-plain-scalars-test
  (is (= ["a" "true" "b" "foo// not a comment"
          "c" "foo" "d" "http://not-a-comment.com"]
         (scalar-values
          (str "{\"a\":true// comment\n"
               ",\"b\":foo// not a comment\n"
               ",\"c\":foo // comment\n"
               ",\"d\":http://not-a-comment.com}")))))

(deftest json-token-boundary-test
  (testing "JSON literals and numbers permit adjacent comments"
    (is (= ["null" "true" "false" "-20" "1.25" "1e3"]
           (->> (scalar-values
                 (str "[null// c\n,true/* c */,false// c\n,"
                      "-20/* c */,1.25// c\n,1e3/* c */]"))
                vec))))
  (testing "non-JSON scalars retain adjacent comment markers"
    (is (= ["True// text" "01// text" "nullish/* text */"]
           (scalar-values
            "[True// text, 01// text, nullish/* text */]")))))

(deftest scalar-content-test
  (testing "quoted and block scalars retain comment markers"
    (is (= ["double" "http://example.com/* path */"
            "single" "// text /* text */"
            "literal" "// line\n/* block */\n"]
           (scalar-values
            (str "double: \"http://example.com/* path */\"\n"
                 "single: '// text /* text */'\n"
                 "literal: |\n"
                 "  // line\n"
                 "  /* block */\n"))))))

(deftest separation-and-documents-test
  (is (= ["a" "1" "b" "true" "false" "c" "d" "null"]
         (scalar-values
          (str "{// before\n"
               "\"a\":1,/* comma */\"b\":[true// value\n"
               ",false],\"c\":{/* nested */\"d\":null}}"))))
  (is (= ["true" "false"]
         (scalar-values
          "--- true// first\n.../* between */\n--- false\n"))))

(deftest unchanged-input-events-test
  (let [input "a: 1\nb: [true, false]\nc: http://example.com\n"]
    (is (= (parser/parse input) (events input)))))

(deftest sanitizer-fast-path-test
  (testing "input without comment markers is returned without copying"
    (let [input (str "values: [" (str/join "," (repeat 10000 "0")) "]\n")]
      (is (identical? input (comments/sanitize-comments input)))))
  (testing "plain scalars containing many URLs remain unchanged"
    (let [input (str "url: "
                     (str/join "/" (repeat 1000 "http://example.com"))
                     "\n")]
      (is (identical? input (comments/sanitize-comments input))))))

(deftest sanitizer-offset-test
  (let [input (str "a: true// 注\r\n"
                   "b: false/* λ\nμ */\n")
        sanitized (comments/sanitize-comments input)]
    (is (= (count input) (count sanitized)))
    (is (= (str "a: true    \r\n"
                "b: false    \n    \n")
           sanitized))))

(deftest sanitizer-large-comment-test
  (let [prefix (apply str (repeat 50000 "a"))
        input (str "value: " prefix " // remove\n")
        sanitized (comments/sanitize-comments input)]
    (is (= (count input) (count sanitized)))
    (is (= (str "value: " prefix "          \n") sanitized))))

(deftest errors-test
  (is (thrown-with-msg? Exception #"Unterminated block comment"
                        (events "value: true/* comment\n")))
  (is (thrown-with-msg? Exception #"options must be an EDN map"
                        (comments/parse-events "x" "[]"))))

(defn -main
  [& _]
  (let [{:keys [fail error]}
        (run-tests 'yamlstar-plugin.json-comments-test)]
    (when (pos? (+ fail error))
      (System/exit 1))))
