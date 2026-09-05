(ns yamlstar-plugin.json-comments
  "JSON-style comment sanitizer and reference-parser entry point."
  (:require [clojure.string :as str]
            [yaml-parser.core :as parser]))

(def ^:private json-token-pattern
  #"(?:null|true|false|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)")

(def ^:private block-header-pattern
  (re-pattern
   (str "^( *)(?:(?:.*: )|(?:- )|(?:\\? ))?[|>]"
        "([1-9]?[+-]?|[+-]?[1-9]?)(?: *(?:#|//|/\\*).*)?$")))

(def ^:private block-header-prefix-pattern
  (re-pattern
   (str "^( *)(?:(?:.*: )|(?:- )|(?:\\? ))?[|>]"
        "(?:[1-9]?[+-]?|[+-]?[1-9]?)$")))

(defn- line-records
  [input]
  (let [length (count input)]
    (loop [start 0 records []]
      (if (>= start length)
        records
        (let [end (loop [position start]
                    (if (and (< position length)
                             (not (#{\newline \return}
                                   (nth input position))))
                      (recur (inc position))
                      position))
              next-start (cond
                           (>= end length) end
                           (and (= \return (nth input end))
                                (< (inc end) length)
                                (= \newline (nth input (inc end))))
                           (+ end 2)
                           :else (inc end))]
          (recur next-start
                 (conj records {:start start
                                :end next-start
                                :text (subs input start end)})))))))

(defn- indentation
  [text]
  (count (or (second (re-find #"^( *)" text)) "")))

(defn- block-header
  [text]
  (when-let [match (re-matches block-header-pattern text)]
    (let [modifier (nth match 2)
          digit (re-find #"[1-9]" modifier)]
      {:header-indent (count (nth match 1))
       :content-indent (when digit
                         (+ (count (nth match 1))
                            (parse-long digit)))})))

(defn- block-scalar-ranges
  [input]
  (loop [records (line-records input) block nil ranges []]
    (if-let [{:keys [start end text]} (first records)]
      (let [indent (indentation text)
            blank? (boolean (re-matches #"[ \t]*" text))
            content-indent (:content-indent block)
            content? (and block
                          (or blank?
                              (and content-indent
                                   (>= indent content-indent))
                              (and (nil? content-indent)
                                   (> indent (:header-indent block)))))]
        (if content?
          (recur (next records)
                 (if (or blank? content-indent)
                   block
                   (assoc block :content-indent indent))
                 (conj ranges [start end]))
          (recur (next records) (block-header text) ranges)))
      ranges)))

(defn- whitespace?
  [character]
  (contains? #{\space \tab \newline \return} character))

(defn- structural-boundary?
  [character]
  (contains? #{\[ \] \{ \} \,} character))

(defn- value-start
  [input slash-position]
  (loop [position (dec slash-position)]
    (if (neg? position)
      0
      (let [character (nth input position)]
        (cond
          (#{\newline \return \[ \{ \,} character) (inc position)
          (and (= character \:)
               (< (inc position) slash-position)
               (whitespace? (nth input (inc position))))
          (inc position)
          (and (= character \:)
               (pos? position)
               (contains? #{\' \" \] \}}
                          (nth input (dec position))))
          (inc position)
          :else (recur (dec position)))))))

(defn- json-token-before?
  [input slash-position]
  (let [value (str/trim
               (subs input (value-start input slash-position)
                     slash-position))
        value (if (re-find #"^(?:-|\?)\s+" value)
                (str/replace-first value #"^(?:-|\?)\s+" "")
                value)
        value (if (re-find #"^(?:---|\.\.\.)\s+" value)
                (str/replace-first value #"^(?:---|\.\.\.)\s+" "")
                value)]
    (boolean (re-matches json-token-pattern value))))

(defn- document-marker-before?
  [input slash-position]
  (let [value (str/trim
               (subs input (value-start input slash-position)
                     slash-position))]
    (contains? #{"---" "..."} value)))

(defn- block-header-before?
  [input slash-position]
  (let [line-start (loop [position (dec slash-position)]
                     (if (or (neg? position)
                             (#{\newline \return}
                              (nth input position)))
                       (inc position)
                       (recur (dec position))))
        prefix (subs input line-start slash-position)]
    (boolean (re-matches block-header-prefix-pattern prefix))))

(defn- json-colon-before?
  [input position]
  (and (pos? position)
       (= \: (nth input (dec position)))
       (> position 1)
       (contains? #{\' \" \] \}}
                  (nth input (- position 2)))))

(defn- comment-boundary?
  [input position quoted-end? after-comment?]
  (or (zero? position)
      quoted-end?
      after-comment?
      (json-colon-before? input position)
      (let [previous (nth input (dec position))]
        (or (whitespace? previous)
            (structural-boundary? previous)))
      (json-token-before? input position)
      (document-marker-before? input position)
      (block-header-before? input position)))

(defn- quote-start?
  [input position]
  (or (zero? position)
      (let [previous (nth input (dec position))]
        (or (whitespace? previous)
            (contains? #{\[ \{ \, \: \?} previous)))))

(defn- mask-comment
  [comment]
  (str/replace comment #"[^\r\n]" " "))

(defn- line-comment-end
  [input position]
  (let [length (count input)]
    (loop [position position]
      (if (or (>= position length)
              (#{\newline \return} (nth input position)))
        position
        (recur (inc position))))))

(defn sanitize-comments
  "Replace JSON-style comments with spaces while preserving offsets."
  [input]
  (let [ranges (block-scalar-ranges input)
        length (count input)]
    (loop [position 0
           ranges ranges
           output []
           quote nil
           escaped? false
           quoted-end? false
           after-comment? false]
      (if (>= position length)
        (str/join output)
        (if-let [[start end] (first ranges)]
          (cond
            (= position start)
            (recur end (next ranges) (conj output (subs input start end))
                   nil false false false)

            (> position start)
            (recur position (next ranges) output quote escaped?
                   quoted-end? after-comment?)

            :else
            (let [character (nth input position)
                  next-character (when (< (inc position) length)
                                   (nth input (inc position)))]
              (cond
                quote
                (if (and (= quote :single)
                         (= character \')
                         (= next-character \'))
                  (recur (+ position 2) ranges
                         (conj output "''") quote false false false)
                  (let [single-end? (and (= quote :single)
                                         (= character \'))
                        double-end? (and (= quote :double)
                                         (= character \" )
                                         (not escaped?))]
                    (recur (inc position) ranges (conj output character)
                           (if (or single-end? double-end?) nil quote)
                           (and (= quote :double)
                                (= character \\)
                                (not escaped?))
                           (or single-end? double-end?) false)))

                (and (#{\' \"} character)
                     (quote-start? input position))
                (recur (inc position) ranges (conj output character)
                       (if (= character \') :single :double)
                       false false false)

                (and (= character \/)
                     (#{\/ \*} next-character)
                     (comment-boundary? input position quoted-end?
                                        after-comment?))
                (let [end (if (= next-character \/)
                            (line-comment-end input (+ position 2))
                            (if-let [close (str/index-of input "*/"
                                                         (+ position 2))]
                              (+ close 2)
                              (throw
                               (ex-info "Unterminated block comment"
                                        {:position position}))))]
                  (recur end ranges
                         (conj output
                               (mask-comment (subs input position end)))
                         nil false false true))

                :else
                (recur (inc position) ranges (conj output character)
                       nil false false false))))
          (recur position [[length length]] output quote escaped?
                 quoted-end? after-comment?))))))

(defn parse-edn
  "Parse input and return a YAMLStar event vector encoded as EDN."
  [input options-edn]
  (let [options (if (str/blank? options-edn)
                  {}
                  (read-string options-edn))]
    (when-not (map? options)
      (throw (ex-info "Plugin options must be an EDN map"
                      {:options options})))
    (pr-str (parser/parse (sanitize-comments input)))))
