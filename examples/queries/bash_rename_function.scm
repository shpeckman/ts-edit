; examples/queries/bash_rename_function.scm
([(function_definition name: (word) @name)
  (command_name (word) @name)]
 (#eq? @name "build"))
