Lua implementation of GraphQL for Tarantool
===========================================

Lua implementation of GraphQL for Tarantool. It is based on [graphql-lua](https://github.com/bjornbytes/graphql-lua).


Installation
------------

```bash
tarantoolctl rocks install https://raw.githubusercontent.com/tarantool/graphql/master/graphql-scm-1.rockspec
```

Example
---

```lua
local parse = require 'graphql.parse'
local schema = require 'graphql.schema'
local types = require 'graphql.types'
local validate = require 'graphql.validate'
local execute = require 'graphql.execute'

-- Parse a query
local ast = parse [[
query getUser($id: ID) {
  person(id: $id) {
    firstName
    lastName
  }
}
]]

-- Create a type
local Person = types.object {
  name = 'Person',
  fields = {
    id = types.id.nonNull,
    firstName = types.string.nonNull,
    middleName = types.string,
    lastName = types.string.nonNull,
    age = types.int.nonNull
  }
}

-- Create a schema
local schema = schema.create {
  query = types.object {
    name = 'Query',
    fields = {
      person = {
        kind = Person,
        arguments = {
          id = types.id
        },
        resolve = function(rootValue, arguments)
          if arguments.id ~= 1 then return nil end

          return {
            id = 1,
            firstName = 'Bob',
            lastName = 'Ross',
            age = 52
          }
        end
      }
    }
  }
}

-- Validate a parsed query against a schema
validate(schema, ast)

-- Execution
local rootValue = {}
local variables = { id = 1 }
local operationName = 'getUser'

execute(schema, ast, rootValue, variables, operationName)

--[[
{
  person = {
    firstName = 'Bob',
    lastName = 'Ross'
  }
}
]]
```

Status
---

- [x] Parsing
  - [ ] Improve error messages
- [x] Type system
- [x] Introspection
- [x] Validation
- [x] Execution
  - [ ] Asynchronous execution (coroutines)
- [ ] Example server

Running tests
---

```bash
tarantoolctl rocks make # optionally
tarantool tests/runner.lua
```

License
---

MIT
