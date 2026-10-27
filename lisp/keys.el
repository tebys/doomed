;; -*- lexical-binding: t; -*-

;; =============================================================================
;; ATAJOS DE TECLADO PERSONALIZADOS (COSAS DE EMACS)
;; =============================================================================
;; Los gestos estilo Vim (text objects, splits, búsqueda, yy/p) viven en vim.el.

;; Abrir archivos/directorios con C-SPC .
;; C-SPC está reservado por defecto a 'set-mark-command', hay que liberarlo
;; para poder usarlo como prefijo.
(global-unset-key (kbd "C-SPC"))
(global-set-key (kbd "C-SPC .") #'find-file)

;; Todos los buffers con C-SPC b i / matar el actual con C-SPC b d / C-SPC b k
(global-set-key (kbd "C-SPC b i") #'ibuffer)
(global-set-key (kbd "C-SPC b d") #'kill-current-buffer)
(global-set-key (kbd "C-SPC b k") #'kill-current-buffer)

;; Ver la lista de buffers con C-SPC ,
(global-set-key (kbd "C-SPC ,") #'ibuffer)

;; Magit status con C-SPC g s (gg quedó para "ir al inicio", estilo vim)
(global-set-key (kbd "C-x g") #'magit-status)

;; Moverse entre ventanas con C-S-<flecha> (Ctrl + Shift + flecha),
;; dejando S-<flecha> libre para seleccionar texto
(global-set-key (kbd "C-S-<left>") #'windmove-left)
(global-set-key (kbd "C-S-<right>") #'windmove-right)
(global-set-key (kbd "C-S-<up>") #'windmove-up)
(global-set-key (kbd "C-S-<down>") #'windmove-down)

;; Copiar/pegar al estilo del sistema con Super+C / Super+V
(global-set-key (kbd "s-c") #'kill-ring-save)
(global-set-key (kbd "s-v") #'yank)

;; Copiar con C-c y pegar con C-v
(global-set-key (kbd "C-c") #'copy-region-as-kill)
(global-set-key (kbd "C-v") #'yank)

;; Tamaño de fuente estilo Doom: Super+= / Super+- / Super+0
(global-set-key (kbd "s-=") #'my/increase-font-size)
(global-set-key (kbd "s--") #'my/decrease-font-size)
(global-set-key (kbd "s-0") #'my/reset-font-size)

;; Workspaces (perspectiva) estilo Doom: C-SPC TAB ...
(defun my/persp-new ()
  "Pide un nombre y crea un workspace nuevo, cambiando a él."
  (interactive)
  (let ((name (read-string "Nuevo workspace: ")))
    (unless (string-empty-p name)
      (persp-switch name))))

(global-set-key (kbd "C-SPC TAB TAB") #'persp-switch)
(global-set-key (kbd "C-SPC TAB .") #'persp-switch)
(global-set-key (kbd "C-SPC TAB n") #'my/persp-new)
(global-set-key (kbd "C-SPC TAB k") #'persp-kill)
(global-set-key (kbd "C-SPC TAB r") #'persp-rename)

;; =============================================================================
;; map! — versión mínima de la macro de Doom
;; =============================================================================
;; Uso:  (map! :map org-mode-map :v "SPC t a" #'merge-plan)
;;       (map! "SPC t b" #'my-big-font-mode)          ; global
;; - :map KEYMAP   aplica a ese keymap (si aún no existe, espera a que cargue
;;                 la feature, ej. org-mode-map -> org). Sin :map, es global.
;; - :desc "txt"   se acepta e ignora.

(defun my/map--bind (keymap states key def)
  "Enlaza KEY a DEF en KEYMAP (símbolo, o nil para global) según STATES."
  (let* ((seq (kbd key))
         (region-only (and states (cl-every (lambda (s) (memq s '(:v :x))) states)))
         (def (if (and region-only (or (symbolp def) (commandp def)))
                  `(menu-item "" ,def :filter
                              ,(lambda (cmd) (and (use-region-p) cmd)))
                def)))
    (cond
     ((null keymap) (global-set-key seq def))
     ((boundp keymap) (define-key (symbol-value keymap) seq def))
     (t (with-eval-after-load
            (intern (replace-regexp-in-string "\\(?:-mode\\)?-map\\'" ""
                                              (symbol-name keymap)))
          (define-key (symbol-value keymap) seq def))))))

(defmacro map! (&rest args)
  "Define atajos al estilo de `map!' de Doom (subconjunto). Ver comentario arriba."
  (let (keymap states forms)
    (while args
      (let ((arg (pop args)))
        (cond
         ((eq arg :map) (setq keymap (pop args)))
         ((eq arg :desc) (pop args))
         ((keywordp arg) (setq states (list arg)))
         (t (let ((def (pop args)))
              (push `(my/map--bind ',keymap ',states ,arg ,def) forms))))))
    `(progn ,@(nreverse forms))))

;; Recargar toda la configuración (init.el y módulos) con C-SPC h r
(defvar my/config-dir
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))
  "Directorio raíz de esta configuración.")

(defun my/reload-config ()
  "Recarga init.el y los módulos propios de esta configuración."
  (interactive)
  (let ((dir my/config-dir))
    (dolist (feat '(ui keys vim))
      (when (featurep feat)
        (unload-feature feat t)))
    (add-to-list 'load-path (expand-file-name "lisp" dir))
    (load (expand-file-name "init.el" dir) nil t)
    (message "Configuración recargada")))

(global-set-key (kbd "C-SPC h r") #'my/reload-config)

(provide 'keys) ;; Esto permite que Emacs pueda "requerir" este archivo como un módulo
