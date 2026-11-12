;;; org2azw3.el --- Exporta una novela en Org directamente a AZW3 (KF8)  -*- lexical-binding: t; -*-

;; Uso interactivo:  M-x org2azw3-export-buffer   (desde el buffer .org)
;; Uso en batch:     emacs -Q --batch -l org2azw3.el -f org2azw3-batch libro.org [salida.azw3]
;;
;; Escribe el contenedor PalmDB/KF8 byte a byte.  Estructura del archivo:
;;   registro 0   cabecera PalmDOC + MOBI (versión 8) + EXTH + título
;;   texto        flujo 0 = esqueletos y fragmentos XHTML, flujo 1 = CSS
;;   índices      chunk (fragmentos), skel (esqueletos), ncx (tabla de contenidos)
;;   cierre       FDST, FLIS, FCIS y marca de fin de archivo
;; El texto va sin comprimir.

;;; Code:

(eval-and-compile
  (add-to-list 'load-path
               (file-name-directory (or load-file-name buffer-file-name default-directory))))
(require 'cl-lib)
(require 'org)
(require 'org-element)
(require 'org-id)
(require 'ucs-normalize)

;;; Parser: árbol de org-element -> lista de capítulos

;; Subconjunto de Org soportado:
;;   #+TITLE: / #+AUTHOR: / #+LANGUAGE:   metadatos (language por defecto: es)
;;   * Capítulo                           un capítulo por cada título de nivel 1
;;   ** Sección                           subtítulo dentro del capítulo
;;   -----                                separador de escena
;;   *negrita*  /cursiva/                 formato en línea
;;   # comentario                         se ignora

(defun org2azw3--escape (s)
  (replace-regexp-in-string
   ">" "&gt;"
   (replace-regexp-in-string
    "<" "&lt;"
    (replace-regexp-in-string "&" "&amp;" s t t) t t) t t))

(defun org2azw3--inline (data)
  "Convierte objetos de Org (lista o string) en HTML en línea."
  (string-trim
   (mapconcat
    (lambda (o)
      (if (stringp o)
          (org2azw3--escape (replace-regexp-in-string "\n" " " (substring-no-properties o)))
        (concat
         (pcase (org-element-type o)
           ('bold (format "<strong>%s</strong>" (org2azw3--inline (org-element-contents o))))
           ('italic (format "<em>%s</em>" (org2azw3--inline (org-element-contents o))))
           ('entity (org2azw3--escape (or (org-element-property :utf-8 o) "")))
           ('line-break " ")
           ((or 'verbatim 'code) (org2azw3--escape (org-element-property :value o)))
           (_ (org2azw3--inline (org-element-contents o))))
         ;; los espacios tras un objeto viven en :post-blank, no en el texto
         (make-string (or (org-element-property :post-blank o) 0) ?\s))))
    data "")))

(defun org2azw3--parse (tree)
  "Devuelve una lista de capítulos (:title :blocks) a partir de TREE."
  (let (chapters)
    (cl-labels
        ((ensure (title)
           (unless chapters
             (push (list :title title :blocks nil) chapters)))
         (add (block)
           (ensure "Inicio")
           (let ((ch (car chapters)))
             (plist-put ch :blocks (cons block (plist-get ch :blocks)))))
         (walk (node)
           (pcase (org-element-type node)
             ('headline
              (if (= (org-element-property :level node) 1)
                  (push (list :title (org-element-property :raw-value node)
                              :html (org2azw3--inline (org-element-property :title node))
                              :blocks nil)
                        chapters)
                (add (list 'h2 (org2azw3--inline (org-element-property :title node)))))
              (mapc #'walk (org-element-contents node)))
             ('paragraph (add (list 'p (org2azw3--inline (org-element-contents node)))))
             ('horizontal-rule (add (list 'break)))
             ((or 'org-data 'section 'quote-block 'center-block 'special-block)
              (mapc #'walk (org-element-contents node))))))
      (walk tree))
    (dolist (ch chapters)
      (plist-put ch :blocks (nreverse (plist-get ch :blocks))))
    (nreverse chapters)))

(defun org2azw3--keyword (kws key)
  (car (cdr (assoc key kws))))

(defconst org2azw3--record-size 4096)
(defconst org2azw3--null #xFFFFFFFF)

(defconst org2azw3--css
  "body { margin: 0; }
h1 { font-size: 1.5em; font-weight: bold; text-align: center; margin: 2em 0 1.5em 0; }
h2 { font-size: 1.2em; font-weight: bold; margin: 1.5em 0 1em 0; }
p { margin: 0; text-indent: 1.2em; text-align: justify; }
p.sin { text-indent: 0; }
p.escena { text-indent: 0; text-align: center; margin: 1em 0; }
")

;;; Bytes

(defun org2azw3--u8 (n) (unibyte-string (logand n 255)))
(defun org2azw3--u16 (n) (unibyte-string (logand (ash n -8) 255) (logand n 255)))
(defun org2azw3--u32 (n)
  (unibyte-string (logand (ash n -24) 255) (logand (ash n -16) 255)
                  (logand (ash n -8) 255) (logand n 255)))
(defun org2azw3--zeros (n) (make-string n 0))
(defun org2azw3--ffs (n) (apply #'unibyte-string (make-list n 255)))
(defun org2azw3--utf8 (s) (encode-coding-string s 'utf-8))

(defun org2azw3--align (s)
  "Rellena S con ceros hasta un múltiplo de 4 bytes."
  (let ((extra (mod (length s) 4)))
    (if (zerop extra) s (concat s (org2azw3--zeros (- 4 extra))))))

(defun org2azw3--encint (value)
  "Entero de ancho variable; el bit alto marca el último byte."
  (let ((bytes (list (logior (logand value 127) 128))))
    (setq value (ash value -7))
    (while (> value 0)
      (push (logand value 127) bytes)
      (setq value (ash value -7)))
    (apply #'unibyte-string bytes)))

(defun org2azw3--encint-backward (value)
  "Entero de ancho variable; el bit alto marca el primer byte."
  (let ((bytes (list (logand value 127))))
    (setq value (ash value -7))
    (while (> value 0)
      (push (logand value 127) bytes)
      (setq value (ash value -7)))
    (setcar bytes (logior (car bytes) 128))
    (apply #'unibyte-string bytes)))

(defun org2azw3--trailing-entry (raw)
  "RAW seguido de su tamaño total como entero de ancho variable inverso."
  (let ((lsize 1) encoded)
    (while (progn
             (setq encoded (org2azw3--encint-backward (+ (length raw) lsize)))
             (/= (length encoded) lsize))
      (setq lsize (1+ lsize)))
    (concat raw encoded)))

(defun org2azw3--base32 (n)
  (let ((digits "0123456789ABCDEFGHIJKLMNOPQRSTUV") (out ""))
    (while (> n 0)
      (setq out (concat (string (aref digits (mod n 32))) out)
            n (/ n 32)))
    (if (string-empty-p out) "0" out)))

(defun org2azw3--base32-pad (n digits)
  (let ((s (org2azw3--base32 n)))
    (concat (make-string (max 0 (- digits (length s))) ?0) s)))

;;; Documento: esqueleto + fragmento por capítulo

(defun org2azw3--chunk-html (ch aidbase)
  "HTML de los bloques de CH, con atributos aid a partir de AIDBASE+1."
  (let ((j 0) (prev t))                 ; prev: el bloque anterior no es un párrafo
    (cl-flet ((aid () (org2azw3--base32 (+ aidbase (cl-incf j)))))
      (concat
       (format "<h1 aid=\"%s\">%s</h1>"
               (aid) (or (plist-get ch :html) (org2azw3--escape (plist-get ch :title))))
       (mapconcat
        (lambda (b)
          (prog1
              (pcase (car b)
                ('p (format "<p%s aid=\"%s\">%s</p>"
                            (if prev " class=\"sin\"" "") (aid) (cadr b)))
                ('h2 (format "<h2 aid=\"%s\">%s</h2>" (aid) (cadr b)))
                ('break (format "<p class=\"escena\" aid=\"%s\">* * *</p>" (aid))))
            (setq prev (not (eq (car b) 'p)))))
        (plist-get ch :blocks)
        "")))))

(defun org2azw3--document (ch i lang)
  "Devuelve (SKELETON CHUNK INSERT) en bytes para el capítulo CH número I."
  (let* ((aidbase (* i 1000000))
         (body-aid (org2azw3--base32 aidbase))
         (prefix (org2azw3--utf8
                  (format "<?xml version='1.0' encoding='utf-8'?>\n<html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"%s\" xml:lang=\"%s\"><head><title>%s</title><link href=\"kindle:flow:0001?mime=text/css\" rel=\"stylesheet\" type=\"text/css\"/></head><body aid=\"%s\">"
                          lang lang (org2azw3--escape (plist-get ch :title)) body-aid)))
         (suffix "</body></html>")
         (chunk (org2azw3--utf8 (org2azw3--chunk-html ch aidbase))))
    (list (concat prefix suffix) chunk (length prefix) body-aid)))

;;; Índices

(defun org2azw3--cncx (strings)
  "Devuelve (REGISTROS . TABLA) con las cadenas de STRINGS (offset por cadena)."
  (let ((table (make-hash-table :test 'equal)) (buf "") (order nil))
    (dolist (s strings)
      (unless (gethash s table)
        (let* ((utf8 (org2azw3--utf8 (substring s 0 (min (length s) 500))))
               (raw (concat (org2azw3--encint (length utf8)) utf8)))
          (puthash s (length buf) table)
          (push s order)
          (setq buf (concat buf raw)))))
    (when (> (length buf) (- #x10000 1024))
      (error "Demasiadas cadenas para un registro CNCX"))
    (cons (if (string-empty-p buf) nil (list (org2azw3--align buf))) table)))

(defun org2azw3--shift (mask)
  (let ((s 0))
    (while (zerop (logand mask 1)) (setq mask (ash mask -1) s (1+ s)))
    s))

(defun org2azw3--control-bytes (tag-types tags)
  (let ((cbs nil) (acc 0))
    (dolist (tt tag-types)
      (cl-destructuring-bind (name _number vpe mask endflag) tt
        (if (= endflag 1)
            (progn (push acc cbs) (setq acc 0))
          (let ((nentries (/ (length (cdr (assq name tags))) vpe)))
            (setq acc (logior acc (logand mask (ash nentries (org2azw3--shift mask)))))))))
    (nreverse cbs)))

(defun org2azw3--index (tag-types control-byte-count entries cncx-records)
  "Registros de un índice: cabecera, datos y CNCX.
ENTRIES es una lista de (CLAVE . ((TAG . VALORES) ...))."
  (let* ((tagx (let ((b (mapconcat (lambda (tt) (unibyte-string (nth 1 tt) (nth 2 tt) (nth 3 tt) (nth 4 tt)))
                                   tag-types "")))
                 (concat "TAGX" (org2azw3--u32 (+ 12 (length b)))
                         (org2azw3--u32 control-byte-count) b)))
         (block "") (idxt "") (last-key ""))
    (dolist (e entries)
      (let* ((key (org2azw3--utf8 (car e))) (tags (cdr e))
             (cbs (org2azw3--control-bytes tag-types tags))
             (raw (concat (org2azw3--u8 (length key)) key
                          (apply #'unibyte-string cbs)
                          (mapconcat
                           (lambda (tt)
                             (mapconcat #'org2azw3--encint (cdr (assq (nth 0 tt) tags)) ""))
                           tag-types ""))))
        (setq idxt (concat idxt (org2azw3--u16 (+ 192 (length block))))
              block (concat block raw)
              last-key key)))
    (when (> (length block) (- #x10000 192 1048))
      (error "Índice demasiado grande para un registro"))
    (let* ((block (org2azw3--align block))
           (idxt-block (org2azw3--align (concat "IDXT" idxt)))
           (data (concat "INDX" (org2azw3--u32 192) (org2azw3--zeros 4) (org2azw3--u32 1)
                         (org2azw3--zeros 4) (org2azw3--u32 (+ 192 (length block)))
                         (org2azw3--u32 (length entries)) (org2azw3--ffs 8)
                         (org2azw3--zeros 156) block idxt-block))
           (geometry (org2azw3--align
                      (concat (org2azw3--u8 (length last-key)) last-key
                              (org2azw3--u16 (length entries)))))
           (idxt-head (org2azw3--align (concat "IDXT" (org2azw3--u16 (+ 192 (length tagx))))))
           (header (concat "INDX" (org2azw3--u32 192) (org2azw3--zeros 8) (org2azw3--u32 2)
                           (org2azw3--u32 (+ 192 (length tagx) (length geometry)))
                           (org2azw3--u32 1) (org2azw3--u32 65001) (org2azw3--u32 org2azw3--null)
                           (org2azw3--u32 (length entries)) (org2azw3--zeros 12)
                           (org2azw3--u32 (length cncx-records)) (org2azw3--zeros 124)
                           (org2azw3--u32 192) (org2azw3--zeros 8)
                           tagx geometry idxt-head)))
      (append (list header data) cncx-records))))

(defconst org2azw3--skel-tags
  '((chunk-count 1 1 3 0) (geometry 6 2 12 0) (eof 0 0 0 1)))
(defconst org2azw3--chunk-tags
  '((cncx-offset 2 1 1 0) (file-number 3 1 2 0) (sequence 4 1 4 0) (geometry 6 2 8 0) (eof 0 0 0 1)))
(defconst org2azw3--ncx-tags
  '((offset 1 1 1 0) (length 2 1 2 0) (label 3 1 4 0) (depth 4 1 8 0)
    (parent 21 1 16 0) (first-child 22 1 32 0) (last-child 23 1 64 0)
    (pos-fid 6 2 128 0) (eof 0 0 0 1)))

;;; Registros de texto

(defun org2azw3--overlap (text cut)
  "Bytes de TEXT tras CUT que completan un carácter UTF-8 partido en CUT."
  (let ((i (1- cut)))
    (while (and (> i 0) (= (logand (aref text i) #xC0) #x80)) (setq i (1- i)))
    (let* ((lead (aref text i))
           (want (cond ((>= lead #xF0) 4) ((>= lead #xE0) 3) ((>= lead #xC0) 2) (t 1)))
           (extra (max 0 (- want (- cut i)))))
      (substring text cut (min (length text) (+ cut extra))))))

(defun org2azw3--tbs (entries rec-start rec-len)
  "Secuencia de bytes finales de indexado para un registro de texto.
ENTRIES son (INDEX OFFSET LENGTH), contiguos y de profundidad 0."
  (let* ((rec-end (+ rec-start rec-len))
         (local (cl-remove-if-not
                 (lambda (e) (and (< (nth 1 e) rec-end) (> (+ (nth 1 e) (nth 2 e)) rec-start)))
                 entries)))
    (if (null local)
        ""
      (let* ((last-e (car (last local)))
             (spans (and (< (- (nth 1 last-e) rec-start) 0)
                         (> (+ (- (nth 1 last-e) rec-start) (nth 2 last-e)) rec-len)))
             (flags (logior 2 (if spans 1 0) (if (cdr local) 4 0))))
        (concat (org2azw3--encint (logior (ash (car (car local)) 3) (logand flags 7)))
                (org2azw3--encint 8)
                (if (cdr local) (org2azw3--u8 (length local)) "")
                (if spans (org2azw3--encint 0) ""))))))

(defun org2azw3--text-records (text ncx-entries)
  (let ((pos 0) (n (length text)) records)
    (while (< pos n)
      (let* ((cut (min n (+ pos org2azw3--record-size)))
             (data (substring text pos cut))
             (overlap (if (< cut n) (org2azw3--overlap text cut) "")))
        (push (concat data overlap (org2azw3--u8 (length overlap))
                      (org2azw3--trailing-entry (org2azw3--tbs ncx-entries pos (length data))))
              records)
        (setq pos cut)))
    (nreverse records)))

;;; EXTH y registro 0

(defun org2azw3--exth-record (code data)
  (concat (org2azw3--u32 code) (org2azw3--u32 (+ 8 (length data))) data))

(defun org2azw3--exth (title author lang uuid)
  (let* ((recs (list
                (and author (org2azw3--exth-record 100 (org2azw3--utf8 author)))
                (org2azw3--exth-record 503 (org2azw3--utf8 title))
                (org2azw3--exth-record 524 (org2azw3--utf8 lang))
                (org2azw3--exth-record 112 (org2azw3--utf8 (concat "org2azw3:" uuid)))
                (org2azw3--exth-record 106 (org2azw3--utf8 (format-time-string "%Y-%m-%d" nil t)))
                (org2azw3--exth-record 204 (org2azw3--u32 202))
                (org2azw3--exth-record 205 (org2azw3--u32 2))
                (org2azw3--exth-record 206 (org2azw3--u32 9))
                (org2azw3--exth-record 207 (org2azw3--u32 0))
                (org2azw3--exth-record 125 (org2azw3--u32 0))
                (org2azw3--exth-record 528 "true")))
         (recs (delq nil recs))
         (body (apply #'concat recs))
         (pad (org2azw3--zeros (- 4 (mod (length body) 4)))))
    (concat "EXTH" (org2azw3--u32 (+ 12 (length body))) (org2azw3--u32 (length recs)) body pad)))

(defun org2azw3--language-code (lang)
  (or (cdr (assoc (downcase (car (split-string lang "-")))
                  '(("es" . 10) ("en" . 9) ("fr" . 12) ("de" . 7) ("it" . 16) ("pt" . 22) ("ca" . 3))))
      0))

(defun org2azw3--record0 (&rest a)
  "Construye el registro 0 a partir de los argumentos con nombre A."
  (let* ((exth (org2azw3--exth (plist-get a :title) (plist-get a :author)
                               (plist-get a :lang) (plist-get a :uuid)))
         (title (org2azw3--utf8 (plist-get a :title)))
         (u32 #'org2azw3--u32) (null org2azw3--null)
         (head (concat
                (org2azw3--u16 1) (org2azw3--u16 0)                     ; sin compresión
                (funcall u32 (plist-get a :text-length))
                (org2azw3--u16 (plist-get a :text-records))
                (org2azw3--u16 org2azw3--record-size)
                (org2azw3--u16 0) (org2azw3--u16 0)
                "MOBI" (funcall u32 264) (funcall u32 2) (funcall u32 65001)
                (funcall u32 (random #xFFFFFFFF)) (funcall u32 8)
                (funcall u32 null) (funcall u32 null)                   ; orth / infl
                (apply #'concat (make-list 8 (funcall u32 null)))       ; índices extra
                (funcall u32 (plist-get a :first-non-text))
                (funcall u32 (+ 280 (length exth)))                     ; offset del título
                (funcall u32 (length title))
                (funcall u32 (org2azw3--language-code (plist-get a :lang)))
                (funcall u32 0) (funcall u32 0) (funcall u32 8)
                (funcall u32 null)                                      ; primer recurso
                (org2azw3--zeros 16)                                    ; Huffman
                (funcall u32 #x50)                                      ; flags EXTH
                (org2azw3--zeros 32) (funcall u32 null)
                (funcall u32 null) (org2azw3--zeros 12)                 ; DRM
                (org2azw3--zeros 8)
                (funcall u32 (plist-get a :fdst)) (funcall u32 2)
                (funcall u32 (plist-get a :fcis)) (funcall u32 1)
                (funcall u32 (plist-get a :flis)) (funcall u32 1)
                (org2azw3--zeros 8)
                (funcall u32 null) (funcall u32 0) (org2azw3--ffs 8)    ; SRCS
                (funcall u32 3)                                         ; multibyte + TBS
                (funcall u32 (plist-get a :ncx))
                (funcall u32 (plist-get a :chunk))
                (funcall u32 (plist-get a :skel))
                (funcall u32 null) (funcall u32 null)                   ; datp / guide
                (funcall u32 null) (funcall u32 0) (funcall u32 null) (funcall u32 0))))
    (cl-assert (= (length head) 280))
    (concat head exth title (org2azw3--zeros 8192))))

(defconst org2azw3--flis
  (concat "FLIS" (unibyte-string 0 0 0 8 0 #x41 0 0 0 0 0 0 255 255 255 255 0 1 0 3 0 0 0 3 0 0 0 1)
          (org2azw3--ffs 4)))

(defun org2azw3--fcis (text-length)
  (concat "FCIS" (unibyte-string 0 0 0 #x14 0 0 0 #x10 0 0 0 2 0 0 0 0)
          (org2azw3--u32 text-length)
          (unibyte-string 0 0 0 0 0 0 0 #x28 0 0 0 0 0 0 0 #x28 0 0 0 8 0 1 0 1 0 0 0 0)))

;;; Ensamblado

(defun org2azw3--palmdb-name (title)
  (let* ((ascii (replace-regexp-in-string
                 "[^ -~]" ""
                 (ucs-normalize-NFD-string title)))
         (name (replace-regexp-in-string " " "_" ascii)))
    (setq name (substring name 0 (min 31 (length name))))
    (concat name (org2azw3--zeros (- 32 (length name))))))

(defun org2azw3--palmdb (title records)
  (let* ((n (length records)) (now (floor (float-time)))
         (offset (+ 78 (* 8 n) 2)) (list ""))
    (cl-loop for r in records for i from 0
             do (setq list (concat list (org2azw3--u32 offset) (org2azw3--u8 0)
                                   (substring (org2azw3--u32 (* 2 i)) 1))
                      offset (+ offset (length r))))
    (concat (org2azw3--palmdb-name title) (org2azw3--u16 0) (org2azw3--u16 0)
            (org2azw3--u32 now) (org2azw3--u32 now) (org2azw3--zeros 16)
            "BOOKMOBI" (org2azw3--u32 (1- (* 2 n))) (org2azw3--u32 0) (org2azw3--u16 n)
            list (org2azw3--zeros 2) (apply #'concat records))))

(defun org2azw3--build (chapters title author lang)
  "Devuelve el contenido (bytes) del AZW3 para CHAPTERS."
  (let* ((docs (cl-loop for ch in chapters for i from 0 collect (org2azw3--document ch i lang)))
         (flow0 "") skel-table chunk-table ncx-entries)
    ;; flujo 0: esqueleto + fragmento de cada capítulo
    (cl-loop for d in docs for ch in chapters for i from 0
             do (cl-destructuring-bind (skel chunk ins body-aid) d
                  (let ((start (length flow0)))
                    (push (list i start (length skel)) skel-table)
                    (push (list (+ start ins) body-aid i (length chunk)) chunk-table)
                    (push (list i (+ start ins) (plist-get ch :title)) ncx-entries)
                    (setq flow0 (concat flow0 skel chunk)))))
    (setq skel-table (nreverse skel-table) chunk-table (nreverse chunk-table)
          ncx-entries (nreverse ncx-entries))
    (let* ((css (org2azw3--utf8 org2azw3--css))
           (text (concat flow0 css))
           ;; NCX: longitud de cada entrada hasta el inicio de la siguiente
           (ncx (cl-loop for (e . rest) on ncx-entries
                         collect (list (nth 0 e) (nth 1 e)
                                       (- (if rest (nth 1 (car rest)) (length flow0)) (nth 1 e))
                                       (nth 2 e))))
           (text-records (org2azw3--text-records text (mapcar (lambda (e) (take 3 e)) ncx)))
           (pad (let ((r (mod (apply #'+ (mapcar #'length text-records)) 4)))
                  (and (/= r 0) (org2azw3--zeros (- 4 r)))))
           (records (list nil)) (uuid (org-id-uuid)))
      (setq records (append records text-records (and pad (list pad))))
      (cl-flet ((add (recs) (prog1 (length records)
                              (setq records (append records recs)))))
        (let* ((first-non-text (length records))
               (selector (lambda (c) (format "P-//*[@aid='%s']" (nth 1 c))))
               (chunk-cncx (org2azw3--cncx (mapcar selector chunk-table)))
               (ncx-cncx (org2azw3--cncx (mapcar (lambda (e) (nth 3 e)) ncx)))
               (chunk-idx
                (add (org2azw3--index
                      org2azw3--chunk-tags 1
                      (mapcar (lambda (c)
                                (cons (format "%010d" (nth 0 c))
                                      `((cncx-offset ,(gethash (funcall selector c) (cdr chunk-cncx)))
                                        (file-number ,(nth 2 c)) (sequence ,(nth 2 c))
                                        (geometry 0 ,(nth 3 c)))))
                              chunk-table)
                      (car chunk-cncx))))
               (skel-idx
                (add (org2azw3--index
                      org2azw3--skel-tags 1
                      (mapcar (lambda (s)
                                (cons (format "SKEL%010d" (nth 0 s))
                                      `((chunk-count 1 1)
                                        (geometry ,(nth 1 s) ,(nth 2 s) ,(nth 1 s) ,(nth 2 s)))))
                              skel-table)
                      nil)))
               (ncx-idx
                (add (org2azw3--index
                      org2azw3--ncx-tags 1
                      (mapcar (lambda (e)
                                (cons (format "%04X" (nth 0 e))
                                      `((offset ,(nth 1 e)) (length ,(nth 2 e))
                                        (label ,(gethash (nth 3 e) (cdr ncx-cncx)))
                                        (depth 0) (pos-fid ,(nth 0 e) 0))))
                              ncx)
                      (car ncx-cncx))))
               ;; FDST, FLIS, FCIS, EOF
               (fdst-idx
                (add (list (concat "FDST" (org2azw3--u32 12) (org2azw3--u32 2)
                                   (org2azw3--u32 0) (org2azw3--u32 (length flow0))
                                   (org2azw3--u32 (length flow0)) (org2azw3--u32 (length text)))
                           org2azw3--flis
                           (org2azw3--fcis (length text))
                           (concat (unibyte-string #xE9 #x8E) "\r\n")))))
          (setcar records
                  (org2azw3--record0
                   :title title :author author :lang lang :uuid uuid
                   :text-length (length text) :text-records (length text-records)
                   :first-non-text first-non-text
                   :fdst fdst-idx :flis (1+ fdst-idx) :fcis (+ 2 fdst-idx)
                   :ncx ncx-idx :chunk chunk-idx :skel skel-idx))
          (org2azw3--palmdb title records))))))

;;;###autoload
(defun org2azw3-export-buffer (&optional azw3-path)
  "Exporta el buffer Org actual a AZW3 en AZW3-PATH y devuelve la ruta."
  (interactive)
  (let* ((out (expand-file-name
               (or azw3-path (concat (file-name-sans-extension (or buffer-file-name "libro")) ".azw3"))))
         (kws (org-collect-keywords '("TITLE" "AUTHOR" "LANGUAGE")))
         (title (or (org2azw3--keyword kws "TITLE") "Sin título"))
         (author (org2azw3--keyword kws "AUTHOR"))
         (lang (or (org2azw3--keyword kws "LANGUAGE") "es"))
         (chapters (org2azw3--parse (org-element-parse-buffer))))
    (unless chapters (user-error "El archivo .org no tiene contenido"))
    (let ((data (org2azw3--build chapters title author lang))
          (coding-system-for-write 'no-conversion))
      (write-region data nil out nil 'silent))
    (message "listo: %s (%d capítulos)" out (length chapters))
    out))

(defun org2azw3-batch ()
  "Punto de entrada para `emacs --batch': ORG [AZW3] en `command-line-args-left'."
  (let* ((org (or (pop command-line-args-left)
                  (error "uso: emacs -Q --batch -l org2azw3.el -f org2azw3-batch libro.org [salida.azw3]")))
         (out (pop command-line-args-left)))
    (with-temp-buffer
      (insert-file-contents org)
      (delay-mode-hooks (org-mode))
      (setq buffer-file-name (expand-file-name org))
      (org2azw3-export-buffer out)
      (set-buffer-modified-p nil))))

(provide 'org2azw3)
;;; org2azw3.el ends here
