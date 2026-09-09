; examples/queries/json_find_pair.scm
(object
  (pair key: (string (string_content) @_key)) @pair
  . ","? @comma
  (#eq? @_key "debug"))
