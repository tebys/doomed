;; -*- lexical-binding: t; -*-

;; =============================================================================
;; CONFIGURACIÓN DE INTERFAZ Y ESTÉTICA CYBERPUNK / WATCH DOGS
;; =============================================================================

;; Interfaz minimalista y rectilínea estilo terminal hacker
(setq inhibit-startup-message t)    ; Quita la pantalla de bienvenida
(scroll-bar-mode -1)                ; Desactiva barra de scroll
(tool-bar-mode -1)                  ; Desactiva barra de herramientas
(menu-bar-mode -1)                  ; Desactiva el menú superior de texto
(global-display-line-numbers-mode 1); Números de línea verticales

;; Resaltar paréntesis con colores llamativos
(show-paren-mode 1)

;; Fuentes con íconos para barras y menús
(use-package all-the-icons)

;; =============================================================================
;; EL TEMA VISUAL (Tron Legacy - Tonos cian/azul digital estilo Watch Dogs)
;; =============================================================================
;;(use-package tron-legacy-theme
;;  :ensure t
;;  :config
;;  (load-theme 'tron-legacy t))

(use-package kusanagi-theme
  :config
  (load-theme 'kusanagi t))

;; Si prefieres usar una tipografía específica estilo monospace (ej. JetBrains Mono o Fira Code)
;; descompone y edita las siguientes líneas:
;; (set-face-attribute 'default nil :font "JetBrains Mono-11" :weight 'regular)

;; =============================================================================
;; FUENTE GRANDE AL ESTILO DOOM
;; =============================================================================
(defvar my/font-height-initial 170
  "Altura inicial de la fuente default (décimas de punto).")

(defun my/set-font-height (height)
  "Aplica HEIGHT (décimas de punto) a la fuente default en toda la interfaz."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (bound-and-true-p text-scale-mode)
        (text-scale-mode -1))))
  (set-face-attribute 'default nil :height height))

(defun my/increase-font-size (n)
  "Aumenta la fuente default en N pasos (10 décimas de punto c/u)."
  (interactive "p")
  (my/set-font-height (+ (round (face-attribute 'default :height)) (* 10 n))))

(defun my/decrease-font-size (n)
  "Disminuye la fuente default en N pasos (10 décimas de punto c/u)."
  (interactive "p")
  (my/set-font-height (max 50 (- (round (face-attribute 'default :height))
                                 (* 10 n)))))

(defun my/reset-font-size ()
  "Restaura el tamaño inicial de la fuente default."
  (interactive)
  (my/set-font-height my/font-height-initial))

(my/set-font-height my/font-height-initial)

(provide 'ui) ;; Esto permite que Emacs pueda "requerir" este archivo como un módulo
