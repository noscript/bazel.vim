# bazel.vim - [Bazel](https://bazel.build/) build system integration for Vim

* <kbd>Tab</kbd> autocompletion for targets
* goto-definition for BUILD files
* listing references

and more.

## Comparison

|Feature|[bazel.vim](https://github.com/noscript/bazel.vim)|official [vim-bazel](https://github.com/bazelbuild/vim-bazel)|
|-|-|-|
|Zero dependency|✓|✗(requires [Bash completion](https://bazel.build/install/completion) + [vim-maktaba](https://github.com/google/vim-maktaba))|
|Tab completion|✓|✓|
|Integration with Vim terminal|✓|✓(does not reuse terminal window)|
|Build results in QuickFix|✓|✗|
|Go to `BUILD` file|✓|✗|
|Go to label/target definition|✓|✗|
|List references|✓|✗|

## Default mappings

* `gb` - Go to `BUILD` file corresponding to the current buffer.
* `gd` - Go to label definition under cursor (for `BUILD` and `.bzl` files).
* `gr` - List references for label under cursor (for `BUILD` and `.bzl` files).
* `<leader>p` - Print label that corresponds to current buffer.
* `b<C-G>` - Print current buffer path relative to workspace.

## Commands

* `Bazel {args}` - Run Bazel command and open QuickFix when done.

Example:
```
:Bazel build //main:hello-world
```

* `BazelDefinition {target}` - Jump to target definition.

Example:
```
:BazelDefinition //main:hello-world
```

* `BazelReferences {target}` - List target references.

Example:
```
:BazelReferences //lib:hello-time
```

