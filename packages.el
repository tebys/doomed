;; -*- lexical-binding: t; -*-

;; =============================================================================
;; PAQUETES Y EXTENSIONES
;; =============================================================================

;; Control de versiones con Magit
(use-package magit
  :custom
  ;; Guarda sin preguntar los buffers modificados del repo antes de pull,
  ;; commit, etc. (el valor por defecto, t, pregunta cada vez).
  (magit-save-repository-buffers 'dontask))

;; Servidor de lenguaje (LSP). Viene incluido en Emacs, no se descarga.
(use-package eglot
  :ensure nil
  :hook (fennel-mode . eglot-ensure))

;; Soporte para Fennel
(use-package fennel-mode
  :mode "\\.fnl\\'")

;; Soporte para mise
(use-package mise
  :ensure t
  :config (global-mise-mode))

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

;; Org-babel: ejecutar bloques de código dentro de org (C-c C-c sobre el bloque).
;; Org viene incluido en Emacs; solo se habilitan los lenguajes.
(use-package org
  :ensure nil
  :config
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (shell . t)))
  ;; Ejecutar bloques sin pedir confirmación (ojo con .org de terceros).
  (setq org-confirm-babel-evaluate nil)
  ;; Seleccionar con S-flecha en org
  (setq org-support-shift-select t)
  ;; Para que <s TAB inserte un #+begin_src (estilo Doom).
  (require 'org-tempo))

(use-package ob-async
  :after org
  :ensure t)

;; Dired: con dos ventanas abiertas, copiar/mover (C, R) propone la otra como destino.
(use-package dired
  :ensure nil
  :config
  (setq dired-dwim-target t))

;; Terminales
(use-package eshell) ; incluido en Emacs
(use-package vterm)

;; La config de agent-shell (y anotaciones de perspectivas) vive en agents.el,
;; que init.el carga después de este archivo.

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
