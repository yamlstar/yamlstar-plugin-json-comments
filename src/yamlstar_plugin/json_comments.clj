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

(defn- text-between
  [characters start end]
  (str/join (subvec characters start end)))

(defn- line-records
  [characters]
  (let [length (count characters)]
    (loop [start 0 records []]
      (if (>= start length)
        records
        (let [end (loop [position start]
                    (if (and (< position length)
                             (not (#{\newline \return}
                                   (nth characters position))))
                      (recur (inc position))
                      position))
              next-start (cond
                           (>= end length) end
                           (and (= \return (nth characters end))
                                (< (inc end) length)
                                (= \newline
                                   (nth characters (inc end))))
                           (+ end 2)
                           :else (inc end))]
          (recur next-start
                 (conj records {:start start
                                :end next-start
                                :text (text-between
                                       characters start end)})))))))

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
  [characters]
  (loop [records (line-records characters) block nil ranges []]
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

(defn- json-token-before?
  [characters value-start slash-position]
  (let [value (str/trim
               (text-between characters value-start slash-position))
        value (if (re-find #"^(?:-|\?)\s+" value)
                (str/replace-first value #"^(?:-|\?)\s+" "")
                value)
        value (if (re-find #"^(?:---|\.\.\.)\s+" value)
                (str/replace-first value #"^(?:---|\.\.\.)\s+" "")
                value)]
    (boolean (re-matches json-token-pattern value))))

(defn- document-marker-before?
  [characters value-start slash-position]
  (let [value (str/trim
               (text-between characters value-start slash-position))]
    (contains? #{"---" "..."} value)))

(defn- block-header-before?
  [characters line-start slash-position]
  (let [prefix (text-between characters line-start slash-position)]
    (boolean (re-matches block-header-prefix-pattern prefix))))

(defn- json-colon-before?
  [characters position]
  (and (pos? position)
       (= \: (nth characters (dec position)))
       (> position 1)
       (contains? #{\' \" \] \}}
                  (nth characters (- position 2)))))

(defn- comment-boundary?
  [characters position quoted-end? after-comment?
   line-start value-start prefix-eligible?]
  (let [simple-boundary?
        (or (zero? position)
            quoted-end?
            after-comment?
            (json-colon-before? characters position)
            (let [previous (nth characters (dec position))]
              (or (whitespace? previous)
                  (structural-boundary? previous))))]
    (cond
      simple-boundary? [true prefix-eligible?]
      (not prefix-eligible?) [false false]
      :else
      [(or (json-token-before? characters value-start position)
           (document-marker-before? characters value-start position)
           (block-header-before? characters line-start position))
       false])))

(defn- quote-start?
  [characters position]
  (or (zero? position)
      (let [previous (nth characters (dec position))]
        (or (whitespace? previous)
            (contains? #{\[ \{ \, \: \?} previous)))))

(defn- mask-comment
  [comment]
  (str/replace comment #"[^\r\n]" " "))

(defn- line-comment-end
  [characters length position]
  (loop [position position]
    (if (or (>= position length)
            (#{\newline \return} (nth characters position)))
      position
      (recur (inc position)))))

(defn- block-comment-end
  [characters length position]
  (loop [position position]
    (cond
      (>= (inc position) length) nil
      (and (= \* (nth characters position))
           (= \/ (nth characters (inc position))))
      (+ position 2)
      :else (recur (inc position)))))

(defn- context-after-character
  [characters length position line-start value-start prefix-eligible?]
  (let [character (nth characters position)
        next-character (when (< (inc position) length)
                         (nth characters (inc position)))
        previous-character (when (pos? position)
                             (nth characters (dec position)))]
    (cond
      (#{\newline \return} character)
      [(inc position) (inc position) true]

      (#{\[ \{ \,} character)
      [line-start (inc position) true]

      (and (= character \:)
           (or (and next-character (whitespace? next-character))
               (contains? #{\' \" \] \}} previous-character)))
      [line-start (inc position) true]

      :else [line-start value-start prefix-eligible?])))

(defn- advance-context
  [characters length start end line-start value-start prefix-eligible?]
  (loop [position start
         line-start line-start
         value-start value-start
         prefix-eligible? prefix-eligible?]
    (if (>= position end)
      [line-start value-start prefix-eligible?]
      (let [[line-start value-start prefix-eligible?]
            (context-after-character
             characters length position line-start value-start
             prefix-eligible?)]
        (recur (inc position) line-start value-start
               prefix-eligible?)))))

(defn sanitize-comments
  "Replace JSON-style comments with spaces while preserving offsets."
  [input]
  (if (and (nil? (str/index-of input "//"))
           (nil? (str/index-of input "/*")))
    input
    (let [characters (vec input)
          ranges (block-scalar-ranges characters)
          length (count characters)]
      (loop [position 0
             ranges ranges
             output []
             copy-start 0
             quote nil
             escaped? false
             quoted-end? false
             after-comment? false
             line-start 0
             value-start 0
             prefix-eligible? true]
        (if (>= position length)
          (if (empty? output)
            input
            (str/join
             (conj output
                   (text-between characters copy-start length))))
          (if-let [[start end] (first ranges)]
            (cond
              (= position start)
              (let [[line-start value-start prefix-eligible?]
                    (advance-context
                     characters length position end line-start value-start
                     prefix-eligible?)]
                (recur end (next ranges) output copy-start nil false
                       false false line-start value-start
                       prefix-eligible?))

              (> position start)
              (recur position (next ranges) output copy-start quote
                     escaped? quoted-end? after-comment? line-start
                     value-start prefix-eligible?)

              :else
              (let [character (nth characters position)
                    next-character (when (< (inc position) length)
                                     (nth characters (inc position)))
                    [boundary? checked-prefix?]
                    (if (and (= character \/)
                             (#{\/ \*} next-character))
                      (comment-boundary?
                       characters position quoted-end? after-comment?
                       line-start value-start prefix-eligible?)
                      [false prefix-eligible?])]
                (cond
                  quote
                  (let [step (if (and (= quote :single)
                                      (= character \')
                                      (= next-character \'))
                               2 1)
                        single-end? (and (= step 1)
                                         (= quote :single)
                                         (= character \'))
                        double-end? (and (= quote :double)
                                         (= character \" )
                                         (not escaped?))
                        end (+ position step)
                        [line-start value-start prefix-eligible?]
                        (advance-context
                         characters length position end line-start
                         value-start checked-prefix?)]
                    (recur end ranges output copy-start
                           (if (or single-end? double-end?) nil quote)
                           (and (= quote :double)
                                (= character \\)
                                (not escaped?))
                           (or single-end? double-end?) false line-start
                           value-start prefix-eligible?))

                  (and (#{\' \"} character)
                       (quote-start? characters position))
                  (let [[line-start value-start prefix-eligible?]
                        (context-after-character
                         characters length position line-start value-start
                         checked-prefix?)]
                    (recur (inc position) ranges output copy-start
                           (if (= character \') :single :double)
                           false false false line-start value-start
                           prefix-eligible?))

                  boundary?
                  (let [end (if (= next-character \/)
                              (line-comment-end
                               characters length (+ position 2))
                              (or (block-comment-end
                                   characters length (+ position 2))
                                  (throw
                                   (ex-info "Unterminated block comment"
                                            {:position position}))))
                        [line-start value-start prefix-eligible?]
                        (advance-context
                         characters length position end line-start
                         value-start checked-prefix?)]
                    (recur end ranges
                           (conj output
                                 (text-between
                                  characters copy-start position)
                                 (mask-comment
                                  (text-between characters position end)))
                           end nil false false true line-start value-start
                           prefix-eligible?))

                  :else
                  (let [[line-start value-start prefix-eligible?]
                        (context-after-character
                         characters length position line-start value-start
                         checked-prefix?)]
                    (recur (inc position) ranges output copy-start nil
                           false false false line-start value-start
                           prefix-eligible?)))))
            (recur position [[length length]] output copy-start quote
                   escaped? quoted-end? after-comment? line-start
                   value-start prefix-eligible?)))))))

(defn parse-events
  "Parse input and return the event vector before transport encoding."
  [input options-edn]
  (let [options (if (str/blank? options-edn)
                  {}
                  (read-string options-edn))]
    (when-not (map? options)
      (throw (ex-info "Plugin options must be an EDN map"
                      {:options options})))
    (parser/parse (sanitize-comments input))))

(defn parse-edn
  "Parse input and return a YAMLStar event vector encoded as EDN."
  [input options-edn]
  (pr-str (parse-events input options-edn)))
