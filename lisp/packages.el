;; -*- lexical-binding: t; -*-

;; For debugging and optimizing
;;(setq use-package-verbose t)
;;(setq use-package-compute-statistics t) ;; M-x use-package-report


;; =============================================================================
;; PAQUETES Y EXTENSIONES
;; =============================================================================

(use-package sly
  :ensure t
  :commands (sly sly-connect)
  )

;; Control de versiones con Magit
(use-package magit
  :hook C-SPC g g
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
  :commands agent-shell
  :init
  (advice-add 'agent-shell :before (lambda (&rest _) (global-mise-mode 1))))

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
  ;; Transcripts de agent-shell: ruido en C-SPC p s g (grep) y en el índice.
  (add-to-list 'projectile-globally-ignored-directories ".agent-shell")
  (define-key (current-global-map) (kbd "C-SPC p") 'projectile-command-map))

;; Org-babel: ejecutar bloques de código dentro de org (C-c C-c sobre el bloque).
;; Org viene incluido en Emacs; solo se habilitan los lenguajes.
(use-package org
  :ensure nil
  :mode ("\\.org\\'" . org-mode)
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

;; Presentaciones desde un .org: C-SPC o p. Flechas ←/→ cambian de slide
;; (cada heading de primer nivel es una slide), q sale.
(use-package visual-fill-column)
(use-package org-present
  :after org
  :bind ("C-SPC o p" . org-present)
  :config
  (defun my/org-present-start ()
    (setq-local face-remapping-alist '((default (:height 1.5) default)
                                       (header-line (:height 2.0) header-line)
                                       (org-level-1 (:height 1.75) org-level-1)
                                       (org-level-2 (:height 1.5) org-level-2)))
    (setq-local header-line-format " ")
    (setq-local visual-fill-column-width 90
                visual-fill-column-center-text t)
    (visual-fill-column-mode 1)
    (visual-line-mode 1)
    (org-display-inline-images)
    (org-present-hide-cursor)
    (org-present-read-only))

  (defun my/org-present-end ()
    (setq-local face-remapping-alist nil)
    (setq-local header-line-format nil)
    (visual-fill-column-mode -1)
    (visual-line-mode -1)
    (org-remove-inline-images)
    (org-present-show-cursor)
    (org-present-read-write))

  (add-hook 'org-present-mode-hook #'my/org-present-start)
  (add-hook 'org-present-mode-quit-hook #'my/org-present-end)
  ;; Al cambiar de slide: solo ese heading, con su contenido visible.
  (add-hook 'org-present-after-navigate-functions
            (lambda (&rest _) (org-overview) (org-show-entry) (org-show-children))))

(use-package ob-async
  :after org
  :ensure t)

;; Dired: con dos ventanas abiertas, copiar/mover (C, R) propone la otra como destino.
(use-package dired
  :ensure nil
  :config
  (setq dired-dwim-target t))

;; Terminales
(use-package eshell
  :bind ("C-SPC o e" . eshell)) ; incluido en Emacs
(use-package vterm
  :bind ("C-SPC o t" . vterm))

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
