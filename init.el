;; -*- lexical-binding: t; -*-

;; =============================================================================
;; 1. REPOSITORIOS DE PAQUETES (MELPA)
;; =============================================================================
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; Descargar el índice si es la primera vez que inicias esta config
(unless package-archive-contents
  (package-refresh-contents))

;; Configurar 'use-package' para automatizar descargas de extensiones
(unless (package-installed-p 'use-package)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t) ; Fuerza a que todo se descargue automáticamente

;; Evita que Emacs reescriba init.el con customizations (eso pisaba líneas)
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

;; =============================================================================
;; 2. CARGAR MÓDULOS PROPIOS (Archivos separados)
;; =============================================================================
(add-to-list 'load-path user-emacs-directory)
(require 'ui)
(require 'keys)
;; vim.el va DESPUÉS de keys.el porque keys.el libera C-SPC (lo desata el prefijo)
(require 'vim)
;; packages se carga con `load` (no require) para que la recarga de config
;; (C-SPC h r) re-ejecute siempre los use-package dentro.
(load "packages.el" nil t)

;; =============================================================================
;; 3. PORTAPAPELES / CLIPBOARD
;; =============================================================================
(setq select-enable-clipboard t)
(setq select-enable-primary t)
(setq save-interprogram-paste-before-kill t)
