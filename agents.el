;; -*- lexical-binding: t; -*-

;; =============================================================================
;; AGENTES IA (agent-shell, basado en ACP)
;; =============================================================================
;; Nota: se llama agents.el para no chocar con los nombres internos del
;; paquete (agent-shell.el, agent-shell-config.el) ni taparlos en load-path.
;; Se carga con `load` desde init.el para que C-SPC h r re-ejecute los
;; use-package al recargar la config.

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

;; Círculo con el estado del agent-shell junto a cada perspectiva en el
;; prompt de C-SPC TAB TAB (también aparece en persp-kill / persp-rename).
;; El estado se calcula al abrir el prompt (no se refresca en vivo).
(defun my/persp-agent-status (name)
  "Estado del agent-shell del proyecto NAME: blocked, busy o ready.
Si el proyecto tiene varios shells, gana el más urgente."
  (let ((statuses (cl-loop for buf in (agent-shell-buffers)
                           when (with-current-buffer buf
                                  (and (derived-mode-p 'agent-shell-mode)
                                       (ignore-errors
                                         (equal name (agent-shell--project-name)))))
                           collect (agent-shell-status :shell-buffer buf))))
    (cond ((memq 'blocked statuses) 'blocked)
          ((memq 'busy statuses) 'busy)
          ((memq 'ready statuses) 'ready))))

(defun my/persp-agent-annotation (name)
  "Anotación para el candidato NAME: círculo con estado, o vacío."
  (when-let* ((st (my/persp-agent-status name)))
    (format "  %s"
            (propertize "●" 'face (pcase st
                                    ('blocked 'agent-shell-error)
                                    ('busy 'agent-shell-warning)
                                    (_ 'agent-shell-success))))))

(setq persp-interactive-completion-function
      (lambda (&rest args)
        (let ((completion-extra-properties
               `(:annotation-function ,#'my/persp-agent-annotation)))
          (apply #'completing-read args))))
