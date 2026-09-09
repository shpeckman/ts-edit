; examples/queries/python_rename_function.scm
([(function_definition name: (identifier) @name)
  (call function: (identifier) @name)]
 (#eq? @name "greet"))
