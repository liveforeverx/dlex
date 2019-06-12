# Used by "mix format"
locals_without_parens = [
  # Query
  # Schema
  schema: 1,
  schema: 2,
  field: 2,
  field: 3
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
