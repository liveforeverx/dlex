alias Dlex.Api

defmodule Api.Operation.DropOp do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3

  field :NONE, 0
  field :ALL, 1
  field :DATA, 2
  field :ATTR, 3
  field :TYPE, 4
end

defmodule Api.Facet.ValType do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3

  field :STRING, 0
  field :INT, 1
  field :FLOAT, 2
  field :BOOL, 3
  field :DATETIME, 4
end

defmodule Api.Request.VarsEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3

  @type t :: %__MODULE__{
          key: String.t(),
          value: String.t()
        }
  defstruct [:key, :value]

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Api.Metrics.NumUidsEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3

  @type t :: %__MODULE__{
          key: String.t(),
          value: non_neg_integer
        }
  defstruct [:key, :value]

  field :key, 1, type: :string
  field :value, 2, type: :uint64
end

defmodule Api.Metrics do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          num_uids: %{String.t() => non_neg_integer}
        }
  defstruct [:num_uids]

  field :num_uids, 1, repeated: true, type: Api.Metrics.NumUidsEntry, map: true
end

defmodule Api.Request do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          start_ts: non_neg_integer,
          query: String.t(),
          vars: %{String.t() => String.t()},
          read_only: boolean,
          best_effort: boolean,
          mutations: [Api.Mutation.t()],
          commit_now: boolean
        }
  defstruct [:start_ts, :query, :vars, :read_only, :best_effort, :mutations, :commit_now]

  field :start_ts, 1, type: :uint64
  field :query, 4, type: :string
  field :vars, 5, repeated: true, type: Api.Request.VarsEntry, map: true
  field :read_only, 6, type: :bool
  field :best_effort, 7, type: :bool
  field :mutations, 12, repeated: true, type: Api.Mutation
  field :commit_now, 13, type: :bool
end

defmodule Api.Response.UidsEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3

  @type t :: %__MODULE__{
          key: String.t(),
          value: String.t()
        }
  defstruct [:key, :value]

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Api.Uids do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          uids: [String.t()]
        }
  defstruct [:uids]

  field :uids, 1, repeated: true, type: :string
end

defmodule Api.Response do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          json: binary,
          txn: Api.TxnContext.t() | nil,
          latency: Api.Latency.t() | nil,
          metrics: Api.Metrics.t() | nil,
          uids: %{String.t() => String.t()}
        }
  defstruct [:json, :txn, :latency, :metrics, :uids]

  field :json, 1, type: :bytes
  field :txn, 2, type: Api.TxnContext
  field :latency, 3, type: Api.Latency
  field :metrics, 4, type: Api.Metrics
  field :uids, 12, repeated: true, type: Api.Response.UidsEntry, map: true
end

defmodule Api.Mutation do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          set_json: binary,
          delete_json: binary,
          set_nquads: binary,
          del_nquads: binary,
          set: [Api.NQuad.t()],
          del: [Api.NQuad.t()],
          cond: String.t(),
          commit_now: boolean
        }
  defstruct [:set_json, :delete_json, :set_nquads, :del_nquads, :set, :del, :cond, :commit_now]

  field :set_json, 1, type: :bytes
  field :delete_json, 2, type: :bytes
  field :set_nquads, 3, type: :bytes
  field :del_nquads, 4, type: :bytes
  field :set, 5, repeated: true, type: Api.NQuad
  field :del, 6, repeated: true, type: Api.NQuad
  field :cond, 9, type: :string
  field :commit_now, 14, type: :bool
end

defmodule Api.Operation do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          schema: String.t(),
          drop_attr: String.t(),
          drop_all: boolean,
          drop_op: atom | integer,
          drop_value: String.t()
        }
  defstruct [:schema, :drop_attr, :drop_all, :drop_op, :drop_value]

  field :schema, 1, type: :string
  field :drop_attr, 2, type: :string
  field :drop_all, 3, type: :bool
  field :drop_op, 4, type: Api.Operation.DropOp, enum: true
  field :drop_value, 5, type: :string
end

defmodule Api.Payload do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          Data: binary
        }
  defstruct [:Data]

  field :Data, 1, type: :bytes
end

defmodule Api.TxnContext do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          start_ts: non_neg_integer,
          commit_ts: non_neg_integer,
          aborted: boolean,
          keys: [String.t()],
          preds: [String.t()]
        }
  defstruct [:start_ts, :commit_ts, :aborted, :keys, :preds]

  field :start_ts, 1, type: :uint64
  field :commit_ts, 2, type: :uint64
  field :aborted, 3, type: :bool
  field :keys, 4, repeated: true, type: :string
  field :preds, 5, repeated: true, type: :string
end

defmodule Api.Check do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{}
  defstruct []
end

defmodule Api.Version do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          tag: String.t()
        }
  defstruct [:tag]

  field :tag, 1, type: :string
end

defmodule Api.Latency do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          parsing_ns: non_neg_integer,
          processing_ns: non_neg_integer,
          encoding_ns: non_neg_integer,
          assign_timestamp_ns: non_neg_integer,
          total_ns: non_neg_integer
        }
  defstruct [:parsing_ns, :processing_ns, :encoding_ns, :assign_timestamp_ns, :total_ns]

  field :parsing_ns, 1, type: :uint64
  field :processing_ns, 2, type: :uint64
  field :encoding_ns, 3, type: :uint64
  field :assign_timestamp_ns, 4, type: :uint64
  field :total_ns, 5, type: :uint64
end

defmodule Api.NQuad do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          subject: String.t(),
          predicate: String.t(),
          object_id: String.t(),
          object_value: Api.Value.t() | nil,
          label: String.t(),
          lang: String.t(),
          facets: [Api.Facet.t()]
        }
  defstruct [:subject, :predicate, :object_id, :object_value, :label, :lang, :facets]

  field :subject, 1, type: :string
  field :predicate, 2, type: :string
  field :object_id, 3, type: :string
  field :object_value, 4, type: Api.Value
  field :label, 5, type: :string
  field :lang, 6, type: :string
  field :facets, 7, repeated: true, type: Api.Facet
end

defmodule Api.Value do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          val: {atom, any}
        }
  defstruct [:val]

  oneof :val, 0
  field :default_val, 1, type: :string, oneof: 0
  field :bytes_val, 2, type: :bytes, oneof: 0
  field :int_val, 3, type: :int64, oneof: 0
  field :bool_val, 4, type: :bool, oneof: 0
  field :str_val, 5, type: :string, oneof: 0
  field :double_val, 6, type: :double, oneof: 0
  field :geo_val, 7, type: :bytes, oneof: 0
  field :date_val, 8, type: :bytes, oneof: 0
  field :datetime_val, 9, type: :bytes, oneof: 0
  field :password_val, 10, type: :string, oneof: 0
  field :uid_val, 11, type: :uint64, oneof: 0
end

defmodule Api.Facet do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          key: String.t(),
          value: binary,
          val_type: atom | integer,
          tokens: [String.t()],
          alias: String.t()
        }
  defstruct [:key, :value, :val_type, :tokens, :alias]

  field :key, 1, type: :string
  field :value, 2, type: :bytes
  field :val_type, 3, type: Api.Facet.ValType, enum: true
  field :tokens, 4, repeated: true, type: :string
  field :alias, 5, type: :string
end

defmodule Api.LoginRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          userid: String.t(),
          password: String.t(),
          refresh_token: String.t()
        }
  defstruct [:userid, :password, :refresh_token]

  field :userid, 1, type: :string
  field :password, 2, type: :string
  field :refresh_token, 3, type: :string
end

defmodule Api.Jwt do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          access_jwt: String.t(),
          refresh_jwt: String.t()
        }
  defstruct [:access_jwt, :refresh_jwt]

  field :access_jwt, 1, type: :string
  field :refresh_jwt, 2, type: :string
end

defmodule Api.Dgraph.Service do
  @moduledoc false
  use GRPC.Service, name: "api.Dgraph"

  rpc :Login, Api.LoginRequest, Api.Response
  rpc :Query, Api.Request, Api.Response
  rpc :Alter, Api.Operation, Api.Payload
  rpc :CommitOrAbort, Api.TxnContext, Api.TxnContext
  rpc :CheckVersion, Api.Check, Api.Version
end

defmodule Api.Dgraph.Stub do
  @moduledoc false
  use GRPC.Stub, service: Api.Dgraph.Service
end
