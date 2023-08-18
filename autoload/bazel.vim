vim9script noclear

var s_INIT = 'init'
var s_NOT_BAZEL = 'not bazel'
var s_DETECTED = 'detected'
var s_CONFIGURED = 'configured'
var s_FAILED = 'failed'
var s_PENDING = 'pending'

var s_extra_args = ' --noshow_progress --curses=no --ui_event_filters=-info,-warning,-stderr 2>&1'

if !exists('g:bazel')
  g:bazel = {
    status: s_INIT,
    info: {},
    command_winid: -1,
  }
endif

def S__backtrace(): list<string>
  var backtrace_items = expand('<stack>')->substitute('^\(\<function\>\|\<script\>\) ', '', '')->split('\.\.')[: -1]
  backtrace_items->remove(-1) # remove 'S__backtrace()' entry
  backtrace_items[-1] ..= ':'

  var backtrace: list<string>
  var indent = ''
  for item in backtrace_items
    backtrace += [indent .. item]
    indent ..= '  '
  endfor
  return backtrace
enddef

def S__abort(msg__a: list<string>)
  echohl Error
  for m in S__backtrace()[: -2] # -2 to remove 'S__abort()' entry
    echomsg m
  endfor
  echohl None

  for m in msg__a
    echomsg m
  endfor

  silent! interrupt()
enddef

# removes double and trailing slashes
def S__clean_path(path__a: string): string
  return path__a->substitute('\/\+', '/', 'g')->substitute('\/$', '', '')
enddef

# returns file path relative to dir
def S__rel_path(file_abs__a: string, dir_abs__a: string): string
  var path = file_abs__a
    ->fnamemodify(':p')
    ->fnamemodify(':s#^' .. dir_abs__a->fnamemodify(':p') .. '##')
    ->fnamemodify(':s#^/##')->substitute('\/\+', '/', 'g')
  if path->empty()
    path = '.'
  endif
  return path->S__clean_path()
enddef

# extracts bazel label or file path under cursor with quotes removed, if any
def S__token_under_cursor(): string
  var isfname = &isfname
  set isfname+=:,@-@
  var path = expand('<cfile>')
  &isfname = isfname

  return path
enddef

# for bazel files returns label that corresponds to item under cursor, otherwise label for the current buffer
def S__label(): string
  if !empty(&bt) # not a file
    return ''
  endif

  if &ft == 'bzl'
    var path = expand('%:p:h')
    var label_prefix = path->substitute(g:bazel.info.workspace, '/', '')

    var label = S__token_under_cursor()
    if label =~ '^//' || label =~ '^@' # label
      return label
    elseif label =~ '^:' # relative label
      label = label[1 :]
    endif
    return label_prefix .. ':' .. label
  else
    S__configure()

    if g:bazel.status != s_CONFIGURED
      return ''
    endif

    var path = expand('%:p')->S__rel_path(g:bazel.info.workspace)
    var output = systemlist($'cd "{g:bazel.info.workspace}"; bazel query ''"{path}"'' --output label {s_extra_args}')

    if v:shell_error != 0 || empty(output)
      S__abort(output)
    endif

    return output[0]
  endif
enddef

# parses <path>:<lnum>:<col> and opens the file in current buffer
def S__jump_to_location(location__a: string)
  var tokens = matchlist(location__a, '^\(.*\):\(\d\+\):\(\d\+\): .*$')
  execute 'edit' tokens[1]
  var lnum = tokens[2]->str2nr()
  if lnum > 0
    cursor(lnum, tokens[3]->str2nr())
  endif
enddef

# opens location where the label points to in current buffer, or opens quickfix if more than one occurrence
def S__jump_to_label(label__a: string)
  S__configure()

  var path = label__a->substitute(':__subpackages__', '/...', '')
  echo 'Fetching...'
  var output = systemlist($'cd "{g:bazel.info.workspace}"; bazel query ''"{path}"'' --output location {s_extra_args}')
  echo '' | redraw

  if v:shell_error != 0 || empty(output)
    S__abort(output)
  endif

  if len(output) == 1
    S__jump_to_location(output[0])
  else
    cgetexpr output
    copen
  endif
enddef

# runs command in terminal, then opens quickfix
def S__run_command(cmd__a: string)
  S__configure()

  var cmd = 'bazel ' .. cmd__a

  if win_id2win(g:bazel.command_winid) == 0
    botright split
    g:bazel.command_winid = win_getid()
  else
    win_gotoid(g:bazel.command_winid)
  endif

  var term_bufnr: number
  term_bufnr = term_start(cmd, {
    curwin: true,
    exit_cb: (job, exit_code) => {
      term_wait(term_bufnr)
      cgetbuffer
      set bt=quickfix
      copen
      setqflist([], 'r', {title: cmd})
    },
  })
enddef

export def DetectWorkspace()
  if g:bazel.status != s_INIT && g:bazel.status != s_NOT_BAZEL
    return
  endif

  var cwd = getcwd()
  var workspace_file = findfile('WORKSPACE', cwd .. ';')
  if empty(workspace_file)
    g:bazel.status = s_NOT_BAZEL
    return
  endif

  g:bazel.status = s_DETECTED
  g:bazel.info.workspace = workspace_file->fnamemodify(':h')

  command! -nargs=+ -complete=customlist,bazel#CompleteList Bazel           S__run_command(<q-args>)
  command! -nargs=1 -complete=customlist,bazel#CompleteList BazelDefinition S__jump_to_label(<q-args>)
  command! -nargs=1 -complete=customlist,bazel#CompleteList BazelReferences S__show_references(<q-args>)

  if !exists('g:bazel_no_default_mappings') || !g:bazel_no_default_mappings
    nnoremap <silent> gb          <Plug>(bazel-goto-build)
    nnoremap <silent> b<C-G>      <Plug>(bazel-print-rel)
    nnoremap <silent> <leader>p   <Plug>(bazel-print-label)
  endif

  set errorformat^=%t%*[^:]:\ %f:%l:%c:\ %m # recognize error type in "<TYPE>: <file><lnum>:<col>: <message>" form
enddef

def S__configure()
  if g:bazel.status == s_CONFIGURED || g:bazel.status == s_PENDING || g:bazel.status == s_NOT_BAZEL
    return
  endif

  g:bazel.status = s_PENDING

  echo 'Configuring bazel...'
  var output = systemlist($'bazel info {s_extra_args}')
  echo '' | redraw
  if v:shell_error != 0
    g:bazel.status = s_FAILED
    S__abort(output)
  endif

  for line in output
    if empty(line) || line == 'Starting local Bazel server and connecting to it...'
      continue
    endif
    if line !~ '^\S\+: '
      S__abort(['Wrong line format: ' .. line])
    endif
    var [key, value; _] = line->split(': ')
    g:bazel.info[key] = value
  endfor
  g:bazel.status = s_CONFIGURED

  execute $'set path^={g:bazel.info.output_path}/**'
  execute $'set path^={g:bazel.info.workspace}/**'
  # make sure '.' is first:
  set path-=.
  set path^=.
enddef

# for non-file buffers jumps to location the label points to, otherwise jumps to BUILD file corresponding to the current buffer
def S__goto_build()
  if !empty(&bt) # quickfix or terminal
    var token = S__token_under_cursor()
    if empty(token)
      return
    endif
    if token =~ '^//' || token =~ '^@' # label
      wincmd w
      S__jump_to_label(token)
    endif
  else
    S__configure()
    var path = expand('%:p')->S__rel_path(g:bazel.info.workspace)
    var output = systemlist($'cd "{g:bazel.info.workspace}"; bazel query ''"{path}"'' --output location --noincompatible_display_source_file_location {s_extra_args}')

    if v:shell_error != 0 || empty(output)
      S__abort(output)
    endif

    S__jump_to_location(output[0])
  endif
enddef

def S__goto_definition()
  var token = S__token_under_cursor()
  if empty(token)
    return
  endif

  if token =~ '^//' || token =~ '^@' # label
    S__jump_to_label(token)
  elseif token =~ '^:' # relative label
    search('name = "' .. token[1 :] .. '"', 'bW')
  else
    var path = expand('%:p:h') .. '/' .. token
    if filereadable(path) # file
      execute 'edit' expand('%:p:h') .. '/' .. token
    else
      return
    endif
  endif
enddef

def S__show_references(label__a = '')
  S__configure()

  var label = label__a
  if empty(label)
    label = S__label()
  endif
  if empty(label)
    return
  endif

  echo 'Fetching...'
  var output = systemlist($'cd "{g:bazel.info.workspace}"; bazel query ''rdeps(//..., "{label}")'' --output location {s_extra_args}')
  echo '' | redraw
  cgetexpr output
  copen
enddef

def S__print_label()
  var label = S__label()
  echo S__label()
enddef

def S__print_relative_path()
  S__configure()
  echo expand('%:p')->S__rel_path(g:bazel.info.workspace)
enddef

export def CompleteList(arg_lead__a: string, cmd_line__a: string, cursor_pos__a: number): list<string>
  S__configure()

  var arg_lead = arg_lead__a
  if empty(arg_lead)
    arg_lead = '//'
  endif

  if arg_lead[: 1] == '//'
    var separator_pos = len(arg_lead) - 1 - split(arg_lead, '\zs')->reverse()->match('[:/]')
    var target_prefix = arg_lead[: separator_pos - 1]

    var target = target_prefix .. '/...'
    if target == '//...'
      target = '...'
    endif

    var targets = systemlist($'cd "{g:bazel.info.workspace}"; bazel query ''"{target}"'' {s_extra_args}')
    if v:shell_error != 0
      echoerr 'Bazel query error: ' .. v:shell_error
      return []
    endif

    # leave only one extra component
    targets->map((_, val) => val->substitute($'^\({target_prefix}[:/][^:/]\+[:/]*\).*', "\\1", ''))
    targets->sort()->uniq()

    # filter
    targets->filter((_, val) => val =~ '^' .. arg_lead)

    return targets
  else
    return []
  endif
enddef

nnoremap <unique> <Plug>(bazel-goto-build)  <ScriptCmd>S__goto_build()<CR>
nnoremap <unique> <Plug>(bazel-print-rel)   <ScriptCmd>S__print_relative_path()<CR>
nnoremap <unique> <Plug>(bazel-print-label) <ScriptCmd>S__print_label()<CR>
nnoremap <unique> <Plug>(bazel-references)  <ScriptCmd>S__show_references()<CR>
nnoremap <unique> <Plug>(bazel-definition)  <ScriptCmd>S__goto_definition()<CR>

