package = 'graphql'
version = 'scm-1'

source = {
  url = 'git+https://github.com/tarantool/graphql.git'
}

description = {
  summary = 'GraphQL implementation for Tarantool',
  homepage = 'https://github.com/tarantool/graphql',
  maintainer = 'https://github.com/tarantool',
  license = 'MIT'
}

dependencies = {
  'lua >= 5.1',
  'luagraphqlparser == 0.2.0-1',
}

build = {
    type = 'cmake',
    variables = {
        TARANTOOL_DIR = '$(TARANTOOL_DIR)',
        TARANTOOL_INSTALL_LIBDIR = '$(LIBDIR)',
        TARANTOOL_INSTALL_LUADIR = '$(LUADIR)',
        TARANTOOL_INSTALL_BINDIR = '$(BINDIR)',
    }
}
