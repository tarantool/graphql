package = 'graphql'
version = 'scm-1'

source = {
  url = 'git://github.com/tarantool/graphql.git'
}

description = {
  summary = 'GraphQL implementation for Tarantool',
  homepage = 'https://github.com/tarantool/graphql',
  maintainer = 'https://github.com/tarantool',
  license = 'MIT'
}

dependencies = {
  'lua >= 5.1',
  'lulpeg',
}

build = {
  type = 'builtin',
  modules = {
    ['graphql.execute'] = 'graphql/execute.lua',
    ['graphql.introspection'] = 'graphql/introspection.lua',
    ['graphql.parse'] = 'graphql/parse.lua',
    ['graphql.rules'] = 'graphql/rules.lua',
    ['graphql.schema'] = 'graphql/schema.lua',
    ['graphql.types'] = 'graphql/types.lua',
    ['graphql.util'] = 'graphql/util.lua',
    ['graphql.validate'] = 'graphql/validate.lua',
  }
}
