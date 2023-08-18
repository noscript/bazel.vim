vim9script

if exists("b:did_ftplugin")
  finish
endif
b:did_ftplugin = 1

bazel#DetectWorkspace()

if !exists('g:bazel_no_default_mappings') || !g:bazel_no_default_mappings
  nnoremap <silent> <buffer> gd <Plug>(bazel-definition)
  nnoremap <silent> <buffer> gr <Plug>(bazel-references)
endif
