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
  autocmd VimEnter,BufEnter * bazel#DetectWorkspace()
augroup END
