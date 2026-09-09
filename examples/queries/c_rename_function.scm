; examples/queries/c_rename_function.scm
([(function_definition declarator: (function_declarator declarator: (identifier) @name))
  (call_expression function: (identifier) @name)]
 (#eq? @name "add"))
