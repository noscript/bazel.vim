vim9script

if !executable('bazel')
  finish
endif

if exists('g:bazel_loaded')
  finish
endif
g:bazel_loaded = true

import autoload 'bazel.vim'

augroup Bazel
  autocmd!
  autocmd FileType bzl if expand('%:t') == 'BUILD' | bazel#DetectWorkspace() | endif
  autocmd DirChanged * bazel#DetectWorkspace()
augroup END
