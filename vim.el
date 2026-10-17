;; -*- lexical-binding: t; -*-

;; =============================================================================
;; GESTOS / ATAJOS ESTILO VIM (sin evil)
;; =============================================================================
;; Separado de keys.el para que este archivo sea el único "simulador de vim".
;; keys.el queda reservado a cosas propias de Emacs.
;;
;; Text objects (bajo C-SPC, como el líder):
;;   ci(   → C-SPC c i (         di(   → C-SPC d i (         yi(   → C-SPC y i (
;;   ci"   → C-SPC c i "         di"   → C-SPC d i "         yi"   → C-SPC y i "
;;   ca(   → C-SPC c a (         da(   → C-SPC d a (         ya(   → C-SPC y a (
;;   ca"   → C-SPC c a "         da"   → C-SPC d a "         ya"   → C-SPC y a "
;;   ciw   → C-SPC c i w         diw   → C-SPC d i w         yiw   → C-SPC y i w
;;   caw   → C-SPC c a w         daw   → C-SPC d a w         yaw   → C-SPC y a w
;;   ctX   → C-SPC c t (pide char)    dtX → C-SPC d t (pide char)
;;   cfX   → C-SPC c f (incluye char) dfX → C-SPC d f (incluye char)
;;   ytX   → C-SPC y t (pide char)    yfX → C-SPC y f (incluye char)
;;   yy    → C-SPC y y                yNy → C-SPC y N y  (o C-u N C-SPC y y)
;;   dd    → C-SPC d d                dNd → C-SPC d N d  (o C-u N C-SPC d d)
;;   p (pega detrás de la línea)      → C-SPC y P   (C-v sigue siendo pegar)
;;   d$/c$/y$ → C-SPC d $ / C-SPC c $ / C-SPC y $
;;
;; Splits: C-w v/s/o/c.  Buscar: C-/ (el / de vim).  gg/G: inicio/fin de buffer.
;; Bloque visual (C-v de vim): C-SPC v y luego d/y/c/I/A/O/p/o/q.
;; =============================================================================

;; Splits estilo Vim: C-w v (vertical) / C-w s (horizontal)
;; C-w era 'kill-region' (cortar), se libera para usarlo como prefijo
(global-unset-key (kbd "C-w"))
(global-set-key (kbd "C-w v") #'split-window-right)
(global-set-key (kbd "C-w s") #'split-window-below)
(global-set-key (kbd "C-w o") #'delete-other-windows)
(global-set-key (kbd "C-w c") #'delete-window)

;; ---------------------------------------------------------------------------
;; Text objects (i/a) sobre paréntesis y comillas dobles
;; ---------------------------------------------------------------------------

(defun my/parens-region ()
  "Devuelve (INICIO . FIN) del paréntesis que contiene al punto."
  (save-excursion
    (when (= (char-after) ?\()
      (forward-char))
    (let ((open (nth 1 (syntax-ppss))))
      (when open
        (goto-char open)
        (condition-case nil
            (forward-list 1)
          (error (goto-char (point-max))))
        (cons open (point))))))

(defun my/quotes-region (qchar)
  "Devuelve (QOPEN . QCLOSE) con las posiciones de las comillas QCHAR que rodean al punto.
El punto puede estar dentro de las comillas o justo sobre una de ellas."
  (save-excursion
    (let ((chars (char-to-string qchar)))
      ;; si el punto está sobre una comilla, entrar a su lado interno
      (if (= (char-after) qchar)
          (goto-char (1+ (point)))
        (when (= (char-before) qchar)
          (forward-char)))
      (when (search-backward chars nil t)
        (let ((qopen (point)))
          (goto-char (1+ qopen))
          (when (search-forward chars nil t)
            (cons qopen (1- (point)))))))))

(defun my/parens-target (around)
  "Región (INICIO . FIN) del paréntesis actual; WITH AROUND incluye los paréntesis."
  (let ((r (my/parens-region)))
    (when r
      (if around r
        (cons (1+ (car r)) (1- (cdr r)))))))

(defun my/quotes-target (qchar around)
  "Región (INICIO . FIN) de las comillas QCHAR; con AROUND incluye las comillas."
  (let ((r (my/quotes-region qchar)))
    (when r
      (if around (cons (car r) (1+ (cdr r)))
        (cons (1+ (car r)) (cdr r))))))

;; ---------------------------------------------------------------------------
;; Text object de palabra (i w / a w) estilo vim
;; ---------------------------------------------------------------------------

(defun my/word-region ()
  "Devuelve (INICIO . FIN) de la palabra bajo el cursor (chars alfanuméricos y _).
Si el cursor está en un espacio, usa la palabra que le sigue."
  (save-excursion
    (let ((wc "[[:alnum:]_]"))
      (unless (looking-at wc)
        (re-search-forward wc nil t))
      (when (looking-at wc)
        (while (looking-back wc 1)
          (backward-char))
        (let ((start (point)))
          (while (looking-at wc)
            (forward-char))
          (cons start (point)))))))

(defun my/word-around (r)
  "Región de la palabra R incluyendo el espacio (o espacios) que la rodea."
  (let* ((start (car r))
         (end (cdr r))
         (after (save-excursion
                  (goto-char end)
                  (skip-chars-forward " \t")
                  (point))))
    (if (> after end)
        (cons start after)
      (cons (save-excursion
              (goto-char start)
              (skip-chars-backward " \t")
              (point))
            end))))

(defun my/word-target (around)
  "Región (INICIO . FIN) de la palabra actual; con AROUND incluye el espacio."
  (let ((r (my/word-region)))
    (when r
      (if around (my/word-around r) r))))

;; ---------------------------------------------------------------------------
;; Acciones sobre regiones (matar / cambiar / copiar)
;; ---------------------------------------------------------------------------

(defface my-yank-highlight
  '((t :inherit highlight :background "#D4AF37" :foreground "#1c1c1c" :extend t))
  "Resaltado dorado para lo que se copia (estilo vim).")

(defun my/yank-region-highlight (start end)
  "Copia START..END al kill ring y resalta brevemente lo copiado en dorado."
  (copy-region-as-kill start end)
  (let ((ov (make-overlay start end)))
    (overlay-put ov 'face 'my-yank-highlight)
    (overlay-put ov 'priority 1000)
    (run-with-timer 0.8 nil (lambda () (delete-overlay ov)))))

(defun my/object-kill (getter around)
  "Mata la región que devuelve (GETTER AROUND) y deja el punto al inicio."
  (let ((r (funcall getter around)))
    (if (null r)
        (user-error "No se encontró el texto object en el punto")
      (kill-region (car r) (cdr r))
      (goto-char (car r)))))

(defun my/object-yank (getter around)
  "Copia la región que devuelve (GETTER AROUND) sin borrarla."
  (let ((r (funcall getter around)))
    (if (null r)
        (user-error "No se encontró el texto object en el punto")
      (my/yank-region-highlight (car r) (cdr r)))))

;; ---------------------------------------------------------------------------
;; Comandos c/d/y + i/a
;; ---------------------------------------------------------------------------

(defun my/change-inside-parens () (interactive) (my/object-kill #'my/parens-target nil))
(defun my/change-around-parens () (interactive) (my/object-kill #'my/parens-target t))
(defun my/change-inside-quotes () (interactive) (my/object-kill (lambda (a) (my/quotes-target ?\" a)) nil))
(defun my/change-around-quotes () (interactive) (my/object-kill (lambda (a) (my/quotes-target ?\" a)) t))
(defun my/delete-inside-parens () (interactive) (my/object-kill #'my/parens-target nil))
(defun my/delete-around-parens () (interactive) (my/object-kill #'my/parens-target t))
(defun my/delete-inside-quotes () (interactive) (my/object-kill (lambda (a) (my/quotes-target ?\" a)) nil))
(defun my/delete-around-quotes () (interactive) (my/object-kill (lambda (a) (my/quotes-target ?\" a)) t))
(defun my/yank-inside-parens () (interactive) (my/object-yank #'my/parens-target nil))
(defun my/yank-around-parens () (interactive) (my/object-yank #'my/parens-target t))
(defun my/yank-inside-quotes () (interactive) (my/object-yank (lambda (a) (my/quotes-target ?\" a)) nil))
(defun my/yank-around-quotes () (interactive) (my/object-yank (lambda (a) (my/quotes-target ?\" a)) t))
(defun my/change-inside-word () (interactive) (my/object-kill #'my/word-target nil))
(defun my/change-around-word () (interactive) (my/object-kill #'my/word-target t))
(defun my/delete-inside-word () (interactive) (my/object-kill #'my/word-target nil))
(defun my/delete-around-word () (interactive) (my/object-kill #'my/word-target t))
(defun my/yank-inside-word () (interactive) (my/object-yank #'my/word-target nil))
(defun my/yank-around-word () (interactive) (my/object-yank #'my/word-target t))

(global-set-key (kbd "C-SPC c i (") #'my/change-inside-parens)
(global-set-key (kbd "C-SPC c i \"") #'my/change-inside-quotes)
(global-set-key (kbd "C-SPC c a (") #'my/change-around-parens)
(global-set-key (kbd "C-SPC c a \"") #'my/change-around-quotes)
(global-set-key (kbd "C-SPC d i (") #'my/delete-inside-parens)
(global-set-key (kbd "C-SPC d i \"") #'my/delete-inside-quotes)
(global-set-key (kbd "C-SPC d a (") #'my/delete-around-parens)
(global-set-key (kbd "C-SPC d a \"") #'my/delete-around-quotes)
(global-set-key (kbd "C-SPC y i (") #'my/yank-inside-parens)
(global-set-key (kbd "C-SPC y i \"") #'my/yank-inside-quotes)
(global-set-key (kbd "C-SPC y a (") #'my/yank-around-parens)
(global-set-key (kbd "C-SPC y a \"") #'my/yank-around-quotes)
(global-set-key (kbd "C-SPC c i w") #'my/change-inside-word)
(global-set-key (kbd "C-SPC c a w") #'my/change-around-word)
(global-set-key (kbd "C-SPC d i w") #'my/delete-inside-word)
(global-set-key (kbd "C-SPC d a w") #'my/delete-around-word)
(global-set-key (kbd "C-SPC y i w") #'my/yank-inside-word)
(global-set-key (kbd "C-SPC y a w") #'my/yank-around-word)
(global-set-key (kbd "C-SPC y y") #'my/copy-lines)
(global-set-key (kbd "C-SPC y P") #'my/paste-after)

;; ---------------------------------------------------------------------------
;; yy / yNy y p (pegar detrás de la línea)
;; ---------------------------------------------------------------------------

(defun my/copy-lines (n)
  "Copia N líneas (la actual y N-1 siguientes) al kill ring, como el yy de vim."
  (interactive "p")
  (let ((start (line-beginning-position))
        (end (save-excursion (forward-line n) (point))))
    (my/yank-region-highlight start end)
    (message "%d línea(s) copiadas" n)))

(defun my/paste-after ()
  "Pega después del final de la línea actual (p de vim para registros de línea)."
  (interactive)
  (let ((text (current-kill 0)))
    (save-excursion
      (end-of-line)
      (if (string-suffix-p "\n" text)
          (progn (forward-line) (insert text))
        (newline)
        (insert text)))
    (forward-line 1)))

(defun my/delete-lines (n)
  "Borra N líneas completas (la actual y N-1 siguientes), como dd/dNd de vim."
  (interactive "p")
  (let ((start (line-beginning-position))
        (end (save-excursion (forward-line n) (point))))
    (kill-region start end)
    (message "%d línea(s) borradas" n)))

(global-set-key (kbd "C-SPC d d") #'my/delete-lines)

;; Contador tipeado en el medio: dNd / yNy (ej. C-SPC d 2 d borra 2 líneas)
(defun my/read-count-then (target fn)
  "Lee dígitos y luego TARGET (la tecla del operador), y llama a FN con el número.
Permite escribir el conteo entre las dos letras del operador, como d2d/y2y de vim."
  (let ((num "")
        (ch (if (integerp last-command-event) last-command-event nil))
        done)
    (while (not done)
      (cond
       ((and ch (>= ch ?0) (<= ch ?9))
        (setq num (concat num (char-to-string ch)))
        (setq ch (read-char (format "Número (%d)%c" (length num) target))))
       ((eq ch target) (setq done t))
       ((eq ch ?\C-g) (keyboard-quit))
       (t (user-error "Se esperaba un número y después '%c'" target))))
    (funcall fn (max 1 (string-to-number num)))))

(defun my/delete-lines-count () (interactive) (my/read-count-then ?d #'my/delete-lines))
(defun my/copy-lines-count () (interactive) (my/read-count-then ?y #'my/copy-lines))

(dolist (d (number-sequence ?0 ?9))
  (global-set-key (kbd (format "C-SPC d %c" d)) #'my/delete-lines-count)
  (global-set-key (kbd (format "C-SPC y %c" d)) #'my/copy-lines-count))

;; ---------------------------------------------------------------------------
;; t / f (hasta / a través de un carácter) con c, d, y
;; ---------------------------------------------------------------------------

(defun my/until-char-region (c &optional include)
  "Devuelve (INICIO . FIN) de la línea hasta el carácter C buscado hacia adelante.
Con INCLUDE, el carácter C queda incluido en FIN."
  (when c
    (let ((start (point))
          (chars (char-to-string c))
          (line-end (line-end-position)))
      (save-excursion
        (goto-char start)
        (when (search-forward chars line-end t)
          (let ((end (point)))
            (cons start (if include end (1- end)))))))))

(defun my/until-char-action (include)
  "Mata la región hasta el carácter ingresado (hasta o incluyendo según INCLUDE)."
  (let* ((c (read-char (if include
                           "Hasta e incluyendo qué carácter? "
                         "Hasta qué carácter? ")))
         (r (my/until-char-region c include)))
    (if (null r)
        (user-error "Carácter no encontrado en la línea")
      (kill-region (car r) (cdr r))
      (goto-char (car r)))))

(defun my/yank-until-char-action (include)
  "Copia desde el punto hasta el carácter ingresado (hasta o incluyendo según INCLUDE)."
  (let* ((c (read-char (if include
                           "Hasta e incluyendo qué carácter? "
                         "Hasta qué carácter? ")))
         (r (my/until-char-region c include)))
    (if (null r)
        (user-error "Carácter no encontrado en la línea")
      (my/yank-region-highlight (car r) (cdr r)))))

(defun my/delete-until-char () (interactive) (my/until-char-action nil))
(defun my/change-until-char () (interactive) (my/until-char-action nil))
(defun my/delete-through-char () (interactive) (my/until-char-action t))
(defun my/change-through-char () (interactive) (my/until-char-action t))
(defun my/yank-until-char () (interactive) (my/yank-until-char-action nil))
(defun my/yank-through-char () (interactive) (my/yank-until-char-action t))

(global-set-key (kbd "C-SPC c t") #'my/change-until-char)
(global-set-key (kbd "C-SPC c f") #'my/change-through-char)
(global-set-key (kbd "C-SPC d t") #'my/delete-until-char)
(global-set-key (kbd "C-SPC d f") #'my/delete-through-char)
(global-set-key (kbd "C-SPC y t") #'my/yank-until-char)
(global-set-key (kbd "C-SPC y f") #'my/yank-through-char)

;; ---------------------------------------------------------------------------
;; $ (fin de línea) con c, d, y  →  d$ = C-SPC d $, etc.
;; ---------------------------------------------------------------------------

(defun my/kill-to-eol ()
  "Mata desde el punto hasta el final de la línea actual."
  (interactive)
  (let ((start (point))
        (end (line-end-position)))
    (if (= start end)
        (user-error "Ya estás al final de la línea")
      (kill-region start end))))

(defun my/yank-to-eol ()
  "Copia desde el punto hasta el final de la línea actual."
  (interactive)
  (let ((start (point))
        (end (line-end-position)))
    (if (= start end)
        (user-error "Ya estás al final de la línea")
      (my/yank-region-highlight start end))))

(global-set-key (kbd "C-SPC d $") #'my/kill-to-eol)
(global-set-key (kbd "C-SPC c $") #'my/kill-to-eol)
(global-set-key (kbd "C-SPC y $") #'my/yank-to-eol)

;; ---------------------------------------------------------------------------
;; Bloque visual estilo vim (el C-v de vim): C-SPC v, mover, y d/y/c/I/A/p/o/q
;; ---------------------------------------------------------------------------

(require 'rect)

(defun my/block--bounds ()
  (cons (region-beginning) (region-end)))

(defun my/block--off ()
  (when my/block-mode (my/block-mode -1)))

(defun my/block-cancel ()
  (interactive)
  (deactivate-mark)
  (my/block-mode -1))

(defun my/block-kill ()
  "Borra el bloque (d de vim)."
  (interactive)
  (let ((r (my/block--bounds)))
    (kill-rectangle (car r) (cdr r)))
  (my/block-mode -1))

(defun my/block-copy ()
  "Copia el bloque (y de vim)."
  (interactive)
  (let ((r (my/block--bounds)))
    (copy-rectangle-as-kill (car r) (cdr r)))
  (my/block-mode -1))

(defun my/block-change ()
  "Reemplaza el bloque por un texto, en todas las líneas (c de vim)."
  (interactive)
  (call-interactively #'string-rectangle)
  (my/block-mode -1))

(defun my/block-insert ()
  "Inserta texto al inicio del bloque en cada línea (I de vim)."
  (interactive)
  (call-interactively #'string-insert-rectangle)
  (my/block-mode -1))

(defun my/block-open ()
  "Abre un hueco en blanco desplazando a la derecha (O de vim)."
  (interactive)
  (let ((r (my/block--bounds)))
    (open-rectangle (car r) (cdr r)))
  (my/block-mode -1))

(defun my/block--append-line (startcol endcol string)
  (move-to-column endcol t)
  (insert string))

(defun my/block-append (start end string)
  "Agrega texto al final del bloque en cada línea (A de vim)."
  (interactive
   (list (region-beginning) (region-end)
         (read-string (format-prompt "Añadir rectángulo" "") nil 'string-rectangle-history)))
  (barf-if-buffer-read-only)
  (apply-on-rectangle #'my/block--append-line start end string)
  (my/block-mode -1))

(defun my/block-paste ()
  "Pega el último rectángulo copiado/borrado (p de vim)."
  (interactive)
  (yank-rectangle)
  (my/block-mode -1))

(defvar my/block-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "d") #'my/block-kill)
    (define-key map (kbd "x") #'my/block-kill)
    (define-key map (kbd "y") #'my/block-copy)
    (define-key map (kbd "c") #'my/block-change)
    (define-key map (kbd "I") #'my/block-insert)
    (define-key map (kbd "A") #'my/block-append)
    (define-key map (kbd "O") #'my/block-open)
    (define-key map (kbd "p") #'my/block-paste)
    (define-key map (kbd "P") #'my/block-paste)
    (define-key map (kbd "o") #'rectangle-exchange-point-and-mark)
    (define-key map (kbd "q") #'my/block-cancel)
    (define-key map (kbd "C-g") #'my/block-cancel)
    map)
  "Teclas del modo bloque visual (mientras `my/block-mode' está activo).")

(define-minor-mode my/block-mode
  "Modo bloque visual estilo vim (equivalente al C-v de vim).

Activá con `C-SPC v', movete para definir el rectángulo y después:
  d borrar   y copiar   c cambiar   I insertar al inicio del bloque
  A agregar  O abrir hueco   p pegar rectángulo   o cambiar de esquina
  q salir"
  :lighter " Bloque"
  :keymap my/block-mode-map
  (if my/block-mode
      (progn
        (rectangle-mark-mode 1)
        (unless (region-active-p)
          (set-mark (point))
          (activate-mark))
        (add-hook 'deactivate-mark-hook #'my/block--off nil t)
        (message "Bloque: movete y luego d/y/c/I/A/O/p/o/q"))
    (remove-hook 'deactivate-mark-hook #'my/block--off t)
    (when rectangle-mark-mode (rectangle-mark-mode -1))))

(global-set-key (kbd "C-SPC v") #'my/block-mode)

(provide 'vim) ;; Para poder desenlazarlo en la recarga de config
