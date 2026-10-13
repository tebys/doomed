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
(defvar my/font-height-base nil
  "Altura base (décimas de punto) de la fuente default antes de escalar.")

(defvar my/big-font-ratio 1.5
  "Factor de aumento para el modo de fuente grande.")

(defun my/ensure-font-height-base ()
  "Guarda la altura base (décimas de punto) desde la fuente original del frame."
  (unless my/font-height-base
    (let* ((font (face-attribute 'default :font nil 'default))
           (size (and (stringp font) (font-get (font-parse font) :size))))
      (setq my/font-height-base (round (* (if (numberp size) size 10) 10))))))

(define-minor-mode my-big-font-mode
  "Alterna el tamaño grande de fuente (estilo Doom)."
  :init-value nil
  (if my-big-font-mode
      (progn
        (my/ensure-font-height-base)
        (set-face-attribute 'default nil :height
                            (round (* my/font-height-base my/big-font-ratio))))
    (when my/font-height-base
      (set-face-attribute 'default nil :height my/font-height-base))))

(my-big-font-mode 1) ; La fuente por defecto arranca en 1.5x

(defun my/increase-font-size (n)
  "Aumenta la fuente default en N pasos (10 décimas de punto c/u)."
  (interactive "p")
  (my/ensure-font-height-base)
  (setq my/font-height-base (+ my/font-height-base (* 10 n)))
  (set-face-attribute 'default nil :height my/font-height-base))

(defun my/decrease-font-size (n)
  "Disminuye la fuente default en N pasos (10 décimas de punto c/u)."
  (interactive "p")
  (my/ensure-font-height-base)
  (setq my/font-height-base (max 50 (- my/font-height-base (* 10 n))))
  (set-face-attribute 'default nil :height my/font-height-base))

(defun my/reset-font-size ()
  "Restaura el tamaño base de la fuente default."
  (interactive)
  (my/ensure-font-height-base)
  (setq my-big-font-mode nil)
  (set-face-attribute 'default nil :height my/font-height-base))

(provide 'ui) ;; Esto permite que Emacs pueda "requerir" este archivo como un módulo
