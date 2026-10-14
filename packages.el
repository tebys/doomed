;; -*- lexical-binding: t; -*-

;; =============================================================================
;; PAQUETES Y EXTENSIONES
;; =============================================================================

;; Control de versiones con Magit
(use-package magit)

;; Servidor de lenguaje (LSP). Viene incluido en Emacs, no se descarga.
(use-package eglot
  :ensure nil
  :hook (fennel-mode . eglot-ensure))

;; Soporte para Fennel
(use-package fennel-mode
  :mode "\\.fnl\\'")

;; =============================================================================
;; MINIBUFFER / M-x al estilo Doom (vertico + orderless + marginalia)
;; =============================================================================

;; Interfaz de completado en el minibuffer con lista viva de opciones
(use-package vertico
  :config (vertico-mode))

;; Filtrado flexible por espacios (orden de las palabras no importa)
(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

;; Destacado de opciones (anotaciones tipo Doom van con marginalia)
(use-package marginalia
  :config (marginalia-mode))

;; Gestión de proyectos (todos los comandos bajo C-SPC p)
;; Nota: projectile-keymap-prefix se lee al cargar el paquete, así que
;; se enlaza el mapa directamente bajo el prefijo C-SPC.
(use-package projectile
  :config
  (projectile-mode 1)
  (define-key (current-global-map) (kbd "C-SPC p") 'projectile-command-map))

;; Terminales
(use-package eshell) ; incluido en Emacs
(use-package vterm)

;; Shell de agentes IA (agent-shell, basado en ACP)
(use-package agent-shell
  :ensure t
  :config
  (setq agent-shell-permission-responder-function
        #'agent-shell-permission-allow-always)

  ;; Autocompactar: al terminar un turno, si el contexto usado supera el
  ;; umbral, se envía /compact al agente.
  (defvar my/agent-shell-compact-threshold 150000
    "Tokens de contexto a partir de los cuales se autocompacta.")

  (defun my/agent-shell-maybe-compact (shell-buffer)
    "Envía /compact en SHELL-BUFFER si el contexto supera el umbral."
    (when (buffer-live-p shell-buffer)
      (with-current-buffer shell-buffer
        (let ((used (map-nested-elt (agent-shell--state) '(:usage :context-used))))
          (when (and (numberp used)
                     (> used my/agent-shell-compact-threshold)
                     ;; Evita reenviar mientras el contador aún no refleja el compact.
                     (not (eq used (bound-and-true-p my/agent-shell--compacted-at))))
            (setq-local my/agent-shell--compacted-at used)
            (message "agent-shell: contexto en %dk, compactando..." (/ used 1000))
            (agent-shell-insert :text "/compact" :submit t :no-focus t
                                :shell-buffer shell-buffer))))))

  (defun my/agent-shell-setup-autocompact ()
    (let ((buf (current-buffer)))
      (agent-shell-subscribe-to
       :shell-buffer buf
       :event 'turn-complete
       :on-event (lambda (_event) (my/agent-shell-maybe-compact buf)))))

  (add-hook 'agent-shell-mode-hook #'my/agent-shell-setup-autocompact))

;; Notificaciones del sistema cuando un agent-shell necesita atención.
;; macOS usa AppleScript (ns-do-applescript); Linux usa el nativo vía D-Bus.
(defun my/agent-shell-notify (title body)
  (cond
   ((fboundp 'ns-do-applescript)
    (let ((q (lambda (s) (format "\"%s\"" (replace-regexp-in-string "[\"\\\\]" "\\\\\\&" s)))))
      (ns-do-applescript
       (format "display notification %s with title %s sound name \"Glass\""
               (funcall q body) (funcall q title)))))
   ((eq system-type 'gnu/linux)
    (if (executable-find "notify-send")
        (start-process "agent-shell-notify" nil
                       "notify-send" "-a" "agent-shell" title body)
      (when (fboundp 'notifications-notify)
        (notifications-notify :title title
                              :body body
                              :app-name "agent-shell")))
    (when (executable-find "canberra-gtk-play")
      (start-process "agent-shell-sound" nil
                     "canberra-gtk-play" "-i" "bell")))))

(defun my/agent-shell-on-event (event)
  (let ((buf (current-buffer))
        (data (map-elt event :data)))
    (message "agent-shell event: %s" (map-elt event :event))
    (pcase (map-elt event :event)
      ('permission-request
       (my/agent-shell-notify "Agent Shell: Needs Input" (buffer-name buf)))
      ('turn-complete
       (my/agent-shell-notify
        (if (member (map-elt data :stop-reason) '("end_turn" "cancelled"))
            "Agent Shell: Idle" "Agent Shell: Failed")
        (buffer-name buf)))
      ('error
       (my/agent-shell-notify "Agent Shell: Failed"
                              (or (map-elt data :message) (buffer-name buf)))))))

(defun my/agent-shell-subscribe ()
  (dolist (event '(permission-request turn-complete error))
    (agent-shell-subscribe-to :shell-buffer (current-buffer)
                              :event event
                              :on-event #'my/agent-shell-on-event)))

(add-hook 'agent-shell-mode-hook #'my/agent-shell-subscribe)

;; Workspaces (perspectivas) al estilo Doom: C-SPC TAB ...
;; El guard (unless persp-mode) evita que la recarga de config duplique el modo.
(use-package perspective
  :ensure t
  :config
  (setq persp-mode-prefix-key (kbd "C-SPC w"))
  (unless persp-mode (persp-mode 1)))

;; Integración projectile <-> workspace: al cambiar de proyecto crea/cambia
;; la perspectiva correspondiente (workspace por proyecto).
;; Rebindamos C-SPC p p = projectile-switch-project → versión con perspectiva,
;; porque el remap del paquete no aplica a nuestro atajo (vive en otro mapa).
(use-package persp-projectile
  :ensure t
  :after (perspective projectile)
  :config
  (define-key projectile-command-map (kbd "p") #'projectile-persp-switch-project))

;; NOTA: init.el lo carga con `load` (no con require) para que la recarga de
;; config re-ejecute siempre los use-package. Este provide queda para poder
;; `require` en otros contextos sin error.
(provide 'packages)
