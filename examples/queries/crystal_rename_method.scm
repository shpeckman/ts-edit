; examples/queries/crystal_rename_method.scm
([(method_def name: (identifier) @name)
  (call method: (identifier) @name)]
 (#eq? @name "greet"))
