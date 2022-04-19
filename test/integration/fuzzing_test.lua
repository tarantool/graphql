local execute = require('graphql.execute')
local json = require('json')
local parse = require('graphql.parse')
local schema = require('graphql.schema')
local types = require('graphql.types')
local validate = require('graphql.validate')

local t = require('luatest')
local g = t.group('fuzzing')

local test_schema_name = 'default'
local function check_request(query, query_schema, mutation_schema, directives, opts)
    opts = opts or {}
    local root = {
        query = types.object({
            name = 'Query',
            fields = query_schema or {},
        }),
        mutation = types.object({
            name = 'Mutation',
            fields = mutation_schema or {},
        }),
        directives = directives,
    }

    local compiled_schema = schema.create(root, test_schema_name, opts)

    local parsed = parse.parse(query)

    validate.validate(compiled_schema, parsed)

    local rootValue = {}
    local variables = opts.variables or {}
    return execute.execute(compiled_schema, parsed, rootValue, variables)
end

-- constants
local Nullable = true
local NonNullable = false

local ARGUMENTS = 1
local ARGUMENT_TYPE = 1
local ARGUMENT_NULLABILITY = 2
local ARGUMENT_INNER_TYPE = 3
local ARGUMENT_INNER_NULLABILITY = 4
local INPUT_VALUE = 5
local VARIABLE_NULLABILITY = 6
local VARIABLE_INNER_TYPE = 7
local VARIABLE_INNER_NULLABILITY = 8
local VARIABLE_DEFAULT = 9
local EXPECTED_ERROR = 2

local my_enum = types.enum({
    name = 'MyEnum',
    values = {
        a = { value = 'a' },
        b = { value = 'b' },
    },
})

local object_fields = {
    input_object_arg = types.string,
}

local my_input_object = types.inputObject({
    name = 'MyInputObject',
    fields = object_fields,
    kind = types.string,
})

local my_object = types.object({
    name = 'MyObject',
    fields = object_fields,
})

local function isString(value)
    return type(value) == 'string'
end

local function coerceString(value)
    if value ~= nil then
        value = tostring(value)
        if not isString(value) then return end
        return value
    end
    return box.NULL
end

local custom_string = types.scalar({
    name = 'CustomString',
    description = 'Custom string type',
    serialize = coerceString,
    parseValue = coerceString,
    parseLiteral = function(node)
        return coerceString(node.value)
    end,
    isValueOfTheType = isString,
})

local function decodeJson(value)
    if value ~= nil then
        return json.decode(value)
    end
    return box.NULL
end

local json_type = types.scalar({
    name = 'Json',
    description = 'Custom type with JSON decoding',
    serialize = function(value)
        if type(value) ~= 'string' then
            return json.encode(value)
        else
            -- in some cases need to prevent dual json.encode
            return value
        end
    end,
    parseValue = decodeJson,
    parseLiteral = function(node)
        return decodeJson(node.value)
    end,
    isValueOfTheType = isString,
})

local graphql_types = {
    ['enum'] = {
        graphql_type = my_enum,
        var_type = 'MyEnum',
        value = 'b',
        default = 'a',
    },
    ['boolean_true'] = {
        graphql_type = types.boolean,
        var_type = 'Boolean',
        value = true,
        default = false,
    },
    ['boolean_false'] = {
        graphql_type = types.boolean,
        var_type = 'Boolean',
        value = false,
        default = true,
    },
    ['id'] = {
        graphql_type = types.id,
        var_type = 'ID',
        value = '00000000-0000-0000-0000-000000000000',
        default = '11111111-1111-1111-1111-111111111111',
    },
    ['int'] = {
        graphql_type = types.int,
        var_type = 'Int',
        value = 2^30,
        default = 0,
    },
    ['float'] = {
        graphql_type = types.float,
        var_type = 'Float',
        value = 1.1111111,
        default = 0,
    },
    ['string'] = {
        graphql_type = types.string,
        var_type = 'String',
        value = 'Test string',
        default = 'Default Test string',
    },
    ['custom_string'] = {
        graphql_type = custom_string,
        var_type = 'CustomString',
        value = 'Test custom string',
        default = 'Default test custom string',
    },
    ['custom_json'] = {
        graphql_type = json_type,
        var_type = 'Json',
        value = '{"test":123}',
        default = '{"test":0}',
    },
    ['inputObject'] = {
        graphql_type = my_input_object,
        var_type = 'MyInputObject',
        value = { input_object_arg = "Input Object Test String" },
        default = { input_object_arg = "Default Input Object Test String" },
    },
}

local function is_box_null(value)
    if value and value == nil then
        return true
    end
    return false
end

local function gen_schema(argument_list)
    local function make_type(argument)
        local list_type
        if argument[ARGUMENT_TYPE] == 'list' then
            if #argument > 1 and argument[ARGUMENT_INNER_NULLABILITY] == NonNullable then
                list_type = types.list(types.nonNull(graphql_types[argument[ARGUMENT_INNER_TYPE]].graphql_type))
            else
                list_type = types.list(graphql_types[argument[ARGUMENT_INNER_TYPE]].graphql_type)
            end
            if argument[ARGUMENT_NULLABILITY] == NonNullable then
                list_type = types.nonNull(list_type)
            end
        else
            if #argument > 1 and argument[ARGUMENT_NULLABILITY] == NonNullable then
                list_type = types.nonNull(graphql_types[argument[ARGUMENT_TYPE]].graphql_type)
            else
                list_type = graphql_types[argument[ARGUMENT_TYPE]].graphql_type
            end
        end
        return list_type
    end

    local function gen_fields(_argument_list)
        local args = {}
        for k, v in ipairs(_argument_list) do
            if v[ARGUMENT_TYPE] == 'inputObject' then
                args['arg'..tostring(k)] = my_object
            elseif v[ARGUMENT_TYPE] == 'list' then
                if v[ARGUMENT_INNER_TYPE] == 'inputObject' then
                    args['arg'..tostring(k)] = types.list(my_object)
                else
                    args['arg'..tostring(k)] = make_type(v)
                end
            else
                args['arg'..tostring(k)] = make_type(v)
            end
        end
        return args
    end

    local function gen_arguments(_argument_list)
        local args = {}
        for k, v in ipairs(_argument_list) do
            args['arg'..tostring(k)] = make_type(v)
        end
        return args
    end

    return {
        ['test'] = {
            kind = types.object({
                name = 'result',
                fields = gen_fields(argument_list)
            }),
            arguments = gen_arguments(argument_list),
            resolve = function(_, args)
                return args
            end,
        }
    }
end

local function gen_value(argument_type, argument_value)
    local value = ''
    if argument_value == nil then
        value = 'null'
    elseif argument_type == 'string' or argument_type == 'id' or
            argument_type == 'custom_string' then
        value = '"'..tostring(argument_value)..'"'
    elseif argument_type == 'custom_json' then
        value = '"""'..tostring(argument_value)..'"""'
    elseif argument_type == 'inputObject' then
        local fields_count = 0
        for k1, v1 in pairs(argument_value) do
            fields_count = fields_count + 1
            value = value..'{ '..k1..': "'..tostring(v1)..'"'
            if fields_count < #argument_value then
                value = value..', '
            end
        end
        if value ~= '' then
            value = value..' }'
        end
    else
        value = tostring(argument_value)
    end
    return value
end

-- Each query has the following format:
-- query                                                    ### reserved word
-- MyQuery                                                  ### operation name
-- ($var1: varType1, $var2: varType2 = var2Default, ...)    ### a set of variables if provided
-- {
-- top_field_name(arg1: value1, arg2: $var1, ....)          ### top_field with arguments
-- {
-- field1                                                   ### set of field names to be return in result
-- ...
-- }
-- }
-- This function generate query according to provided arguments (see "Suite format" description below)

local function gen_query(argument_list)
    -- gen query variables
    local variables = ''
    for k, v in ipairs(argument_list) do
        -- if VARIABLE_NULLABILITY ~= nil we have to add variables to query
        if v[VARIABLE_NULLABILITY] ~= nil then
            if variables == '' then
                variables = variables .. '('
            end

            local var
            if v[ARGUMENT_TYPE] == 'list' then
                if v[VARIABLE_INNER_NULLABILITY] == NonNullable then
                    var = '$var'..tostring(k)..': ['..graphql_types[v[VARIABLE_INNER_TYPE]].var_type..'!]'
                else
                    var = '$var'..tostring(k)..': ['..graphql_types[v[VARIABLE_INNER_TYPE]].var_type..']'
                end
            else
                var = '$var'..tostring(k)..': '..graphql_types[v[ARGUMENT_TYPE]].var_type
            end

            if v[VARIABLE_NULLABILITY] == NonNullable then
                var = var..'!'
            end
            if type(v[VARIABLE_DEFAULT]) ~= 'nil' then
                if v[ARGUMENT_TYPE] == 'list' then
                    if is_box_null(v[VARIABLE_DEFAULT]) then
                        var = var..' = null'
                    else
                        var = var..' = ['
                        for k1, v1 in ipairs(v[VARIABLE_DEFAULT] or {}) do
                            var = var..gen_value(v[ARGUMENT_INNER_TYPE], v1)
                            if k1 < #v[VARIABLE_DEFAULT] then
                                var = var..', '
                            end
                        end
                        var = var..']'
                    end
                else
                    var = var..' = '..gen_value(v[ARGUMENT_TYPE], v[VARIABLE_DEFAULT])
                end
            end
            if k < #argument_list then
                var = var..', '
            end
            variables = variables..var
        end

    end
    if variables ~= '' then
        variables = variables..') '
    end

    -- gen top_field with arguments
    local query = 'query MyQuery'..variables..' { test('

    for k, v in ipairs(argument_list) do
        local value

        -- if VARIABLE_NULLABILITY ~= nil set argument == variable
        if v[VARIABLE_NULLABILITY] ~= nil then
            value = '$var'..tostring(k)
        else
            if v[ARGUMENT_TYPE] == 'list' then
                if v[INPUT_VALUE] == nil then
                    value = 'null'
                else
                    value = '['
                    for k1, v1 in ipairs(v[INPUT_VALUE] or {}) do
                        value = value..gen_value(v[ARGUMENT_INNER_TYPE], v1)
                        if k1 < #v[INPUT_VALUE] then
                            value = value..', '
                        end
                    end
                    value = value..']'
                end
            else
                value = gen_value(v[ARGUMENT_TYPE], v[INPUT_VALUE])
            end
        end

        query = query..'arg'..tostring(k)..': '..value

        if k < #argument_list then
            query = query..', '
        end
    end

    -- generate set of field names to be return in result
    local result = ' { '
    for k, v in ipairs(argument_list) do
        if v[ARGUMENT_TYPE] == 'inputObject' then
            result = result..'arg'..tostring(k).. ' { '
            local fields_count = 0
            for k1 in pairs(object_fields) do
                fields_count = fields_count + 1
                result = result..' '..k1
                if fields_count < #object_fields then
                    result = result..', '
                end
            end
            result = result..' }'
        elseif v[ARGUMENT_TYPE] == 'list' then
            if v[ARGUMENT_INNER_TYPE] == 'inputObject' then
                result = result..'arg'..tostring(k).. ' { '
                local fields_count = 0
                for k1 in pairs(object_fields) do
                    fields_count = fields_count + 1
                    result = result..' '..k1
                    if fields_count < #object_fields then
                        result = result..', '
                    end
                end
                result = result..' }'
            else
                result = result..'arg'..tostring(k)
            end
        else
            result = result..'arg'..tostring(k)
        end
        if k < #argument_list then
            result = result..', '
        end
    end
    result = result..' }'

    return query..') '..result..' }'
end

local function gen_variables(argument_list)
    local variables
    for k, v in ipairs(argument_list) do
        if v[VARIABLE_NULLABILITY] ~= nil then
            variables = variables or {}
            if v[INPUT_VALUE] ~= nil then
                variables['var'..tostring(k)] = v[INPUT_VALUE]
            elseif is_box_null(v[INPUT_VALUE]) then
                variables['var'..tostring(k)] = box.NULL
            end
        end
    end
    return variables
end

local function gen_result(argument_list, is_error)
    if not is_error then
        local result = {}
        for k, v in ipairs(argument_list) do
            local result_value
            if (type(v[INPUT_VALUE]) == 'nil' and type(v[VARIABLE_DEFAULT]) ~= 'nil') then
                result_value = v[VARIABLE_DEFAULT]
            else
                result_value = v[INPUT_VALUE]
            end
            if v[ARGUMENT_TYPE] == 'custom_json' then
                if result_value ~= nil then
                    result['arg'..tostring(k)] = result_value
                else
                    result['arg'..tostring(k)] = 'null'
                end
            elseif v[ARGUMENT_TYPE] == 'list' and v[ARGUMENT_INNER_TYPE] == 'custom_json' then
                if result_value ~= nil then
                    local values = {}
                    for _, value in ipairs(result_value) do
                        if value ~= nil then
                            table.insert(values, value)
                        else
                            table.insert(values, 'null')
                        end
                    end
                    result['arg'..tostring(k)] = values
                else
                    result['arg'..tostring(k)] = result_value
                end
            else
                result['arg'..tostring(k)] = result_value
            end
        end
        return {test = result}
    end
end

-- Suite format: {[{argument_type, argument_nullability, argument_inner_type, argument_inner_nullability,
-- value, variable_nullability, variable_inner_type, variable_inner_nullability, default}], expected_error}
local function check_suite(suite_name, suite) -- luacheck: no unused args
    for _, v in ipairs(suite) do
        local query = gen_query(v[ARGUMENTS])
        local query_schema = gen_schema(v[ARGUMENTS])
        local variables = gen_variables(v[ARGUMENTS])
        local query_result = gen_result(v[ARGUMENTS], v[EXPECTED_ERROR] ~= nil)

        local ok, res = pcall(check_request, query, query_schema, nil, nil, { variables = variables })

        -- INVESTIGATION CHECKS, UNCOMMENT TO PRINT OUT CHECK RESULTS, USE "-C" FLAG FOR LUATEST
        -- local result, err
        -- if ok then
        --     result = json.encode(res)
        -- else
        --     err = res
        -- end

        -- print(
        --     'Suite: '..suite_name..
        --     ', Case #'..tostring(_)..
        --     ':: Query: '..query..
        --     ', Variables: '..json.encode(variables)..
        --     ', OK: '..tostring(ok)..
        --     ', expected error: '..tostring(v[2])..
        --     ', error: '..tostring(json.encode(err))..
        --     ', data: '..tostring(result)..
        --     ', gen_result: '..tostring(json.encode(query_result))
        -- )

        -- real test checks
        if v[2] == nil then
            t.assert_equals(ok, true)
            t.assert_items_equals(res, query_result)
        else
            t.assert_equals(ok, false)
            t.assert_str_contains(res, v[EXPECTED_ERROR])
        end
    end
end

-- Test scalar, inputObject or enum single argument
g.test_nonlist_arguments_nullability = function ()
    for k, v in pairs(graphql_types) do
        local test_suite = {
            -- (1) Argument: T->Value: value - OK
            {{{k, Nullable, nil, nil, v.value, nil, nil, nil, nil}}, nil},
            -- (2) Argument: T->Value: nil - OK
            {{{k, Nullable, nil, nil, nil, nil, nil, nil, nil}}, nil},
            -- (3) Argument: T->Value: null - OK
            {{{k, Nullable, nil, nil, box.NULL, nil, nil, nil, nil}}, nil},
            -- (4) Argument: T!->Value: value - OK
            {{{k, NonNullable, nil, nil, v.value, nil, nil, nil, nil}}, nil},
            -- (5) Argument: T!->Value: nil - FAIL
            {
                {{k, NonNullable, nil, nil, nil, nil, nil, nil, nil}},
                'Expected non-null for "NonNull('..v.var_type..')", got null',
            },
            -- (6) Argument: T!->Value: null - FAIL
            {
                {{k, NonNullable, nil, nil, box.NULL, nil, nil, nil, nil}},
                'Expected non-null for "NonNull('..v.var_type..')", got null',
            },
        }
        check_suite('Single argument', test_suite)
    end
end

-- Test single list argument with inner type of scalar, inputObject or enum
g.test_list_arguments_nullability = function ()
    for k, v in pairs(graphql_types) do
        local test_suite = {
            -- (1) Argument: [T]->Value: [value(s)] - OK
            {{{'list', Nullable, k, Nullable, {v.value}, nil, nil, nil, nil}}, nil},
            -- (2) Argument: [T]->Value: [] - OK
            {{{'list', Nullable, k, Nullable, {}, nil, nil, nil, nil}}, nil},
            -- (3) Argument: [T]->Value: [null] - OK
            {{{'list', Nullable, k, Nullable, {box.NULL}, nil, nil, nil, nil}}, nil},
            -- (4) Argument: [T]->Value: nil - OK
            {{{'list', Nullable, k, Nullable, nil, nil, nil, nil, nil}}, nil},
            -- (5) Argument: [T]->Value: null - OK
            {{{'list', Nullable, k, Nullable, box.NULL, nil, nil, nil, nil}}, nil},
            -- (6) Argument: [T!]->Value: [value(s)] - OK
            {{{'list', Nullable, k, NonNullable, {v.value}, nil, nil, nil, nil}}, nil},
            -- (7) Argument: [T!]->Value: [] - OK
            {{{'list', Nullable, k, NonNullable, {nil}, nil, nil, nil, nil}}, nil},
            -- (8) Argument: [T!]->Value: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, nil, nil, nil, nil}},
                'Expected non-null for \"NonNull('..v.var_type..')\", got null',
            },
            -- (9) Argument: [T!]->Value: nil - OK
            {{{'list', Nullable, k, NonNullable, nil, nil, nil, nil, nil}}, nil},
            -- (10) Argument: [T!]->Value: null - OK
            {{{'list', Nullable, k, NonNullable, box.NULL, nil, nil, nil, nil}}, nil},
            -- (11) Argument: [T]!->Value: [value(s)] - OK
            {{{'list', NonNullable, k, Nullable, {v.value}, nil, nil, nil, nil}}, nil},
            -- (12) Argument: [T]!->Value: [] - OK
            {{{'list', NonNullable, k, Nullable, {}, nil, nil, nil, nil}}, nil},
            -- (13) Argument: [T]!->Value: [null] - OK
            {{{'list', NonNullable, k, Nullable, {box.NULL}, nil, nil, nil, nil}}, nil},
            -- (14) Argument: [T]!->Value: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, nil, nil, nil, nil}},
                'Expected non-null for \"NonNull(List('..v.var_type..'))\", got null',
            },
            -- (15) Argument: [T]!->Value: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, nil, nil, nil, nil}},
                'Expected non-null for \"NonNull(List('..v.var_type..'))\", got null',
            },
            -- (16) Argument: [T!]!->Value: [value(s)] - OK
            {{{'list', NonNullable, k, NonNullable, {v.value}, nil, nil, nil, nil}}, nil},
            -- (17) Argument: [T!]!->Value: [] - OK
            {{{'list', NonNullable, k, NonNullable, {}, nil, nil, nil, nil}}, nil},
            -- (18) Argument: [T!]!->Value: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, nil, nil, nil, nil}},
                'Expected non-null for \"NonNull('..v.var_type..')\", got null',
            },
            -- (19) Argument: [T!]!->Value: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, nil, nil, nil, nil}},
                'Expected non-null for \"NonNull(List(NonNull('..v.var_type..')))\", got null',
            },
            -- (20) Argument: [T!]!->Value: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, nil, nil, nil, nil}},
                'Expected non-null for \"NonNull(List(NonNull('..v.var_type..')))\", got null',
            },
        }
        check_suite('Single list argument', test_suite)
    end
end

-- Test single scalar, inputObject or enum argument and value provided with variable
g.test_nonlist_arguments_with_variables_nullability = function ()
    for k, v in pairs(graphql_types) do
        local test_suite = {
            -- (1) Argument: T->Variable: T->Value: value-> Default: value - OK
            {{{k, Nullable, nil, nil, v.value, Nullable, nil, nil, v.default}}, nil},
            -- (2) Argument: T->Variable: T->Value: value-> Default: nil - OK
            {{{k, Nullable, nil, nil, v.value, Nullable, nil, nil, nil}}, nil},
            -- (3) Argument: T->Variable: T->Value: value-> Default: null - OK
            {{{k, Nullable, nil, nil, v.value, Nullable, nil, nil, box.NULL}}, nil},
            -- (4) Argument: T->Variable: T->Value: nil-> Default: value - OK
            {{{k, Nullable, nil, nil, nil, Nullable, nil, nil, v.default}}, nil},
            -- (5) Argument: T->Variable: T->Value: nil-> Default: nil - OK
            {{{k, Nullable, nil, nil, nil, Nullable, nil, nil, nil}}, nil},
            -- (6) Argument: T->Variable: T->Value: nil-> Default: null - OK
            {{{k, Nullable, nil, nil, nil, Nullable, nil, nil, box.NULL}}, nil},
            -- (7) Argument: T->Variable: T->Value: null-> Default: value - OK
            {{{k, Nullable, nil, nil, box.NULL, Nullable, nil, nil, v.default}}, nil},
            -- (8) Argument: T->Variable: T->Value: null-> Default: nil - OK
            {{{k, Nullable, nil, nil, box.NULL, Nullable, nil, nil, nil}}, nil},
            -- (9) Argument: T->Variable: T->Value: null-> Default: null - OK
            {{{k, Nullable, nil, nil, box.NULL, Nullable, nil, nil, box.NULL}}, nil},
            -- (10) Argument: T->Variable: T!->Value: value-> Default: value - FAIL
            {
                {{k, Nullable, nil, nil, v.value, NonNullable, nil, nil, v.default}},
                'Non-null variables can not have default values',
            },
            -- (11) Argument: T->Variable: T!->Value: value-> Default: nil - OK
            {{{k, Nullable, nil, nil, v.value, NonNullable, nil, nil, nil}}, nil},
            -- (12) Argument: T->Variable: T!->Value: value-> Default: null - FAIL
            {
                {{k, Nullable, nil, nil, v.value, NonNullable, nil, nil, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (13) Argument: T->Variable: T!->Value: nil-> Default: value - FAIL
            {
                {{k, Nullable, nil, nil, nil, NonNullable, nil, nil, v.default}},
                'Non-null variables can not have default values',
            },
            -- (14) Argument: T->Variable: T!->Value: nil-> Default: nil - FAIL
            {
                {{k, Nullable, nil, nil, nil, NonNullable, nil, nil, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (15) Argument: T->Variable: T!->Value: nil-> Default: null - FAIL
            {
                {{k, Nullable, nil, nil, nil, NonNullable, nil, nil, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (16) Argument: T->Variable: T!->Value: null-> Default: value - FAIL
            {
                {{k, Nullable, nil, nil, box.NULL, NonNullable, nil, nil, v.default}},
                'Non-null variables can not have default values',
            },
            -- (17) Argument: T->Variable: T!->Value: null-> Default: nil - FAIL
            {
                {{k, Nullable, nil, nil, box.NULL, NonNullable, nil, nil, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (18) Argument: T->Variable: T!->Value: null-> Default: null - FAIL
            {
                {{k, Nullable, nil, nil, box.NULL, NonNullable, nil, nil, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (19) Argument: T!->Variable: T->Value: value-> Default: value - OK
            {{{k, NonNullable, nil, nil, v.value, Nullable, nil, nil, v.default}}, nil},
            -- (20) Argument: T!->Variable: T->Value: value-> Default: nil - FAIL
            {
                {{k, NonNullable, nil, nil, v.value, Nullable, nil, nil, nil}},
                'Variable "var1" type mismatch: the variable type "'..v.var_type..'" '..
                'is not compatible with the argument type "NonNull('..v.var_type..')"',
            },
            -- (21) Argument: T!->Variable: T->Value: value-> Default: null - OK
            {{{k, NonNullable, nil, nil, v.value, Nullable, nil, nil, box.NULL}}, nil},
            -- (22) Argument: T!->Variable: T->Value: nil-> Default: value - OK
            {{{k, NonNullable, nil, nil, nil, Nullable, nil, nil, v.default}}, nil},
            -- (23) Argument: T!->Variable: T->Value: nil-> Default: nil - FAIL
            {
                {{k, NonNullable, nil, nil, nil, Nullable, nil, nil, nil}},
                'Variable "var1" type mismatch: the variable type "'..v.var_type..'" '..
                'is not compatible with the argument type "NonNull('..v.var_type..')"',
            },
            -- (24) Argument: T!->Variable: T->Value: nil-> Default: null - FAIL
            {
                {{k, NonNullable, nil, nil, nil, Nullable, nil, nil, box.NULL}},
                'Expected non-null for \"NonNull('..v.var_type..')\", got null',
            },
            -- (25) Argument: T!->Variable: T->Value: null-> Default: value - FAIL
            {
                {{k, NonNullable, nil, nil, box.NULL, Nullable, nil, nil, v.default}},
                'Expected non-null for \"NonNull('..v.var_type..')\", got null',
            },
            -- (26) Argument: T!->Variable: T->Value: null-> Default: nil - FAIL
            {
                {{k, NonNullable, nil, nil, box.NULL, Nullable, nil, nil, nil}},
                'Variable "var1" type mismatch: the variable type "'..v.var_type..'" '..
                'is not compatible with the argument type "NonNull('..v.var_type..')"',
            },
            -- (27) Argument: T!->Variable: T->Value: null-> Default: null - FAIL
            {
                {{k, NonNullable, nil, nil, box.NULL, Nullable, nil, nil, box.NULL}},
                'Expected non-null for \"NonNull('..v.var_type..')\", got null',
            },
            -- (28) Argument: T!->Variable: T!->Value: value-> Default: value - FAIL
            {
                {{k, NonNullable, nil, nil, v.value, NonNullable, nil, nil, v.default}},
                'Non-null variables can not have default values',
            },
            -- (29) Argument: T!->Variable: T!->Value: value-> Default: nil - OK
            {{{k, NonNullable, nil, nil, v.value, NonNullable, nil, nil, nil}}, nil},
            -- (30) Argument: T!->Variable: T!->Value: value-> Default: null - FAIL
            {
                {{k, NonNullable, nil, nil, v.value, NonNullable, nil, nil, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (31) Argument: T!->Variable: T!->Value: nil-> Default: value - FAIL
            {
                {{k, NonNullable, nil, nil, nil, NonNullable, nil, nil, v.default}},
                'Non-null variables can not have default values',
            },
            -- (32) Argument: T!->Variable: T!->Value: nil-> Default: nil - FAIL
            {
                {{k, NonNullable, nil, nil, nil, NonNullable, nil, nil, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (33) Argument: T!->Variable: T!->Value: nil-> Default: null - FAIL
            {
                {{k, NonNullable, nil, nil, nil, NonNullable, nil, nil, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (34) Argument: T!->Variable: T!->Value: null-> Default: value - FAIL
            {
                {{k, NonNullable, nil, nil, box.NULL, NonNullable, nil, nil, v.default}},
                'Non-null variables can not have default values',
            },
            -- (35) Argument: T!->Variable: T!->Value: null-> Default: nil - FAIL
            {
                {{k, NonNullable, nil, nil, box.NULL, NonNullable, nil, nil, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (36) Argument: T!->Variable: T!->Value: null-> Default: null - FAIL
            {
                {{k, NonNullable, nil, nil, box.NULL, NonNullable, nil, nil, box.NULL}},
                'Non-null variables can not have default values',
            },
        }
        check_suite('Single argument with vars', test_suite)
    end
end

-- Test single list argument and variable with inner type of scalar, inputObject or enum
g.test_list_arguments_with_variables_nullability = function ()
    --t.skip_if(true)
    for k, v in pairs(graphql_types) do
        local test_suite = {
            -- (1) Argument: [T] -> Variable: [T] -> Value: [value(s)] -> Default: [value(s)] - OK
            {{{'list', Nullable, k, Nullable, {v.value}, Nullable, k, Nullable, {v.default}}}, nil},
            -- (2) Argument: [T] -> Variable: [T] -> Value: [value(s)] -> Default: [nil] - OK
            {{{'list', Nullable, k, Nullable, {v.value}, Nullable, k, Nullable, {nil}}}, nil},
            -- (3) Argument: [T] -> Variable: [T] -> Value: [value(s)] -> Default: [null] - OK
            {{{'list', Nullable, k, Nullable, {v.value}, Nullable, k, Nullable, {box.NULL}}}, nil},
            -- (4) Argument: [T] -> Variable: [T] -> Value: [value(s)] -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, {v.value}, Nullable, k, Nullable, nil}}, nil},
            -- (5) Argument: [T] -> Variable: [T] -> Value: [value(s)] -> Default: null - OK
            {{{'list', Nullable, k, Nullable, {v.value}, Nullable, k, Nullable, box.NULL}}, nil},
            -- (6) Argument: [T] -> Variable: [T] -> Value: [] -> Default: [value(s)] - OK
            {{{'list', Nullable, k, Nullable, {}, Nullable, k, Nullable, {v.default}}}, nil},
            -- (7) Argument: [T] -> Variable: [T] -> Value: [] -> Default: [] - OK
            {{{'list', Nullable, k, Nullable, {}, Nullable, k, Nullable, {nil}}}, nil},
            -- (8) Argument: [T] -> Variable: [T] -> Value: [] -> Default: [null] - OK
            {{{'list', Nullable, k, Nullable, {}, Nullable, k, Nullable, {box.NULL}}}, nil},
            -- (9) Argument: [T] -> Variable: [T] -> Value: [] -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, {}, Nullable, k, Nullable, nil}}, nil},
            -- (10) Argument: [T] -> Variable: [T] -> Value: [] -> Default: null - OK
            {{{'list', Nullable, k, Nullable, {}, Nullable, k, Nullable, box.NULL}}, nil},
            -- (11) Argument: [T] -> Variable: [T] -> Value: [null] -> Default: [value(s)] - OK
            {{{'list', Nullable, k, Nullable, {box.NULL}, Nullable, k, Nullable, {v.default}}}, nil},
            -- (12) Argument: [T] -> Variable: [T] -> Value: [null] -> Default: [] - OK
            {{{'list', Nullable, k, Nullable, {box.NULL}, Nullable, k, Nullable, {nil}}}, nil},
            -- (13) Argument: [T] -> Variable: [T] -> Value: [null] -> Default: [null] - OK
            {{{'list', Nullable, k, Nullable, {box.NULL}, Nullable, k, Nullable, {box.NULL}}}, nil},
            -- (14) Argument: [T] -> Variable: [T] -> Value: [null] -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, {box.NULL}, Nullable, k, Nullable, nil}}, nil},
            -- (15) Argument: [T] -> Variable: [T] -> Value: [null] -> Default: null - OK
            {{{'list', Nullable, k, Nullable, {box.NULL}, Nullable, k, Nullable, box.NULL}}, nil},
            -- (16) Argument: [T] -> Variable: [T] -> Value: nil -> Default: [value(s)] - OK
            {{{'list', Nullable, k, Nullable, nil, Nullable, k, Nullable, {v.default}}}, nil},
            -- (17) Argument: [T] -> Variable: [T] -> Value: nil -> Default: [] - OK
            {{{'list', Nullable, k, Nullable, nil, Nullable, k, Nullable, {nil}}}, nil},
            -- (18) Argument: [T] -> Variable: [T] -> Value: nil -> Default: [null] - OK
            {{{'list', Nullable, k, Nullable, nil, Nullable, k, Nullable, {box.NULL}}}, nil},
            -- (19) Argument: [T] -> Variable: [T] -> Value: nil -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, nil, Nullable, k, Nullable, nil}}, nil},
            -- (20) Argument: [T] -> Variable: [T] -> Value: nil -> Default: null - OK
            {{{'list', Nullable, k, Nullable, nil, Nullable, k, Nullable, box.NULL}}, nil},
            -- (21) Argument: [T] -> Variable: [T] -> Value: null -> Default: [value(s)] - OK
            {{{'list', Nullable, k, Nullable, box.NULL, Nullable, k, Nullable, {v.default}}}, nil},
            -- (22) Argument: [T] -> Variable: [T] -> Value: null -> Default: [] - OK
            {{{'list', Nullable, k, Nullable, box.NULL, Nullable, k, Nullable, {nil}}}, nil},
            -- (23) Argument: [T] -> Variable: [T] -> Value: null -> Default: [null] - OK
            {{{'list', Nullable, k, Nullable, box.NULL, Nullable, k, Nullable, {box.NULL}}}, nil},
            -- (24) Argument: [T] -> Variable: [T] -> Value: null -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, box.NULL, Nullable, k, Nullable, nil}}, nil},
            -- (25) Argument: [T] -> Variable: [T] -> Value: null -> Default: null - OK
            {{{'list', Nullable, k, Nullable, box.NULL, Nullable, k, Nullable, box.NULL}}, nil},
            -- (26) Argument: [T] -> Variable: [T!] -> Value: [value(s)] -> Default: [value(s)] - OK
            {{{'list', Nullable, k, Nullable, {v.value}, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (27) Argument: [T] -> Variable: [T!] -> Value: [value(s)] -> Default: [nil] - OK
            {{{'list', Nullable, k, Nullable, {v.value}, Nullable, k, NonNullable, {nil}}}, nil},
            -- (28) Argument: [T] -> Variable: [T!] -> Value: [value(s)] -> Default: [null] - OK
            {{{'list', Nullable, k, Nullable, {v.value}, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (29) Argument: [T] -> Variable: [T!] -> Value: [value(s)] -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, {v.value}, Nullable, k, NonNullable, nil}}, nil},
            -- (30) Argument: [T] -> Variable: [T!] -> Value: [value(s)] -> Default: null - OK
            {{{'list', Nullable, k, Nullable, {v.value}, Nullable, k, NonNullable, box.NULL}}, nil},
            -- (31) Argument: [T] -> Variable: [T!] -> Value: [] -> Default: [value(s)] - OK
            {{{'list', Nullable, k, Nullable, {}, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (32) Argument: [T] -> Variable: [T!] -> Value: [] -> Default: [] - OK
            {{{'list', Nullable, k, Nullable, {}, Nullable, k, NonNullable, {nil}}}, nil},
            -- (33) Argument: [T] -> Variable: [T!] -> Value: [] -> Default: [null] - OK
            {{{'list', Nullable, k, Nullable, {}, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (34) Argument: [T] -> Variable: [T!] -> Value: [] -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, {}, Nullable, k, NonNullable, nil}}, nil},
            -- (35) Argument: [T] -> Variable: [T!] -> Value: [] -> Default: null - OK
            {{{'list', Nullable, k, Nullable, {}, Nullable, k, NonNullable, box.NULL}}, nil},
            -- (36) Argument: [T] -> Variable: [T!] -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, Nullable, k, NonNullable, {v.default}}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (37) Argument: [T] -> Variable: [T!] -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, Nullable, k, NonNullable, {nil}}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (38) Argument: [T] -> Variable: [T!] -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, Nullable, k, NonNullable, {box.NULL}}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (39) Argument: [T] -> Variable: [T!] -> Value: [null] -> Default: nil - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, Nullable, k, NonNullable, nil}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (40) Argument: [T] -> Variable: [T!] -> Value: [null] -> Default: null - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, Nullable, k, NonNullable, box.NULL}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (41) Argument: [T] -> Variable: [T!] -> Value: nil -> Default: [value(s)] - OK
            {{{'list', Nullable, k, Nullable, nil, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (42) Argument: [T] -> Variable: [T!] -> Value: nil -> Default: [] - OK
            {{{'list', Nullable, k, Nullable, nil, Nullable, k, NonNullable, {nil}}}, nil},
            -- (43) Argument: [T] -> Variable: [T!] -> Value: nil -> Default: [null] - OK
            {{{'list', Nullable, k, Nullable, nil, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (44) Argument: [T] -> Variable: [T!] -> Value: nil -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, nil, Nullable, k, NonNullable, nil}}, nil},
            -- (45) Argument: [T] -> Variable: [T!] -> Value: nil -> Default: null - OK
            {{{'list', Nullable, k, Nullable, nil, Nullable, k, NonNullable, box.NULL}}, nil},
            -- (46) Argument: [T] -> Variable: [T!] -> Value: null -> Default: [value(s)] - OK
            {{{'list', Nullable, k, Nullable, box.NULL, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (47) Argument: [T] -> Variable: [T!] -> Value: null -> Default: [] - OK
            {{{'list', Nullable, k, Nullable, box.NULL, Nullable, k, NonNullable, {nil}}}, nil},
            -- (48) Argument: [T] -> Variable: [T!] -> Value: null -> Default: [null] - OK
            {{{'list', Nullable, k, Nullable, box.NULL, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (49) Argument: [T] -> Variable: [T!] -> Value: null -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, box.NULL, Nullable, k, NonNullable, nil}}, nil},
            -- (50) Argument: [T] -> Variable: [T!] -> Value: null -> Default: null - OK
            {{{'list', Nullable, k, Nullable, box.NULL, Nullable, k, NonNullable, box.NULL}}, nil},
            -- (51) Argument: [T] -> Variable: [T]! -> Value: [value(s)] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, Nullable, {v.value}, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (52) Argument: [T] -> Variable: [T]! -> Value: [value(s)] -> Default: [nil] - FAIL
            {
                {{'list', Nullable, k, Nullable, {v.value}, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (53) Argument: [T] -> Variable: [T]! -> Value: [value(s)] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, Nullable, {v.value}, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (54) Argument: [T] -> Variable: [T]! -> Value: [value(s)] -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, {v.value}, NonNullable, k, Nullable, nil}}, nil},
            -- (55) Argument: [T] -> Variable: [T]! -> Value: [value(s)] -> Default: null - FAIL
            {
                {{'list', Nullable, k, Nullable, {v.value}, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (56) Argument: [T] -> Variable: [T]! -> Value: [] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, Nullable, {}, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (57) Argument: [T] -> Variable: [T]! -> Value: [] -> Default: [] - FAIL
            {
                {{'list', Nullable, k, Nullable, {}, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (58) Argument: [T] -> Variable: [T]! -> Value: [] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, Nullable, {}, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (59) Argument: [T] -> Variable: [T]! -> Value: [] -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, {}, NonNullable, k, Nullable, nil}}, nil},
            -- (60) Argument: [T] -> Variable: [T]! -> Value: [] -> Default: null - FAIL
            {
                {{'list', Nullable, k, Nullable, {}, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (61) Argument: [T] -> Variable: [T]! -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (62) Argument: [T] -> Variable: [T]! -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (63) Argument: [T] -> Variable: [T]! -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (64) Argument: [T] -> Variable: [T]! -> Value: [null] -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, {box.NULL}, NonNullable, k, Nullable, nil}}, nil},
            -- (65) Argument: [T] -> Variable: [T]! -> Value: [null] -> Default: null - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (66) Argument: [T] -> Variable: [T]! -> Value: nil -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, Nullable, nil, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (67) Argument: [T] -> Variable: [T]! -> Value: nil -> Default: [] - FAIL
            {
                {{'list', Nullable, k, Nullable, nil, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (68) Argument: [T] -> Variable: [T]! -> Value: nil -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, Nullable, nil, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (69) Argument: [T] -> Variable: [T]! -> Value: nil -> Default: nil - FAIL
            {
                {{'list', Nullable, k, Nullable, nil, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (70) Argument: [T] -> Variable: [T]! -> Value: nil -> Default: null - FAIL
            {
                {{'list', Nullable, k, Nullable, nil, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (71) Argument: [T] -> Variable: [T]! -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, Nullable, box.NULL, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (72) Argument: [T] -> Variable: [T]! -> Value: null -> Default: [] - FAIL
            {
                {{'list', Nullable, k, Nullable, box.NULL, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (73) Argument: [T] -> Variable: [T]! -> Value: null -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, Nullable, box.NULL, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (74) Argument: [T] -> Variable: [T]! -> Value: null -> Default: nil - FAIL
            {
                {{'list', Nullable, k, Nullable, box.NULL, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (75) Argument: [T] -> Variable: [T]! -> Value: null -> Default: null - FAIL
            {
                {{'list', Nullable, k, Nullable, box.NULL, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (76) Argument: [T] -> Variable: [T!]! -> Value: [value(s)] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, Nullable, {v.value}, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (77) Argument: [T] -> Variable: [T!]! -> Value: [value(s)] -> Default: [nil] - FAIL
            {
                {{'list', Nullable, k, Nullable, {v.value}, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (78) Argument: [T] -> Variable: [T!]! -> Value: [value(s)] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, Nullable, {v.value}, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (79) Argument: [T] -> Variable: [T!]! -> Value: [value(s)] -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, {v.value}, NonNullable, k, NonNullable, nil}}, nil},
            -- (80) Argument: [T] -> Variable: [T!]! -> Value: [value(s)] -> Default: null - FAIL
            {
                {{'list', Nullable, k, Nullable, {v.value}, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (81) Argument: [T] -> Variable: [T!]! -> Value: [] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, Nullable, {}, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (82) Argument: [T] -> Variable: [T!]! -> Value: [] -> Default: [] - FAIL
            {
                {{'list', Nullable, k, Nullable, {}, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (83) Argument: [T] -> Variable: [T!]! -> Value: [] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, Nullable, {}, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (84) Argument: [T] -> Variable: [T!]! -> Value: [] -> Default: nil - OK
            {{{'list', Nullable, k, Nullable, {}, NonNullable, k, NonNullable, nil}}, nil},
            -- (85) Argument: [T] -> Variable: [T!]! -> Value: [] -> Default: null - FAIL
            {
                {{'list', Nullable, k, Nullable, {}, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (86) Argument: [T] -> Variable: [T!]! -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (87) Argument: [T] -> Variable: [T!]! -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (88) Argument: [T] -> Variable: [T!]! -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (89) Argument: [T] -> Variable: [T!]! -> Value: [null] -> Default: nil - OK
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, NonNullable, k, NonNullable, nil}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (90) Argument: [T] -> Variable: [T!]! -> Value: [null] -> Default: null - FAIL
            {
                {{'list', Nullable, k, Nullable, {box.NULL}, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (91) Argument: [T] -> Variable: [T!]! -> Value: nil -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, Nullable, nil, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (92) Argument: [T] -> Variable: [T!]! -> Value: nil -> Default: [] - FAIL
            {
                {{'list', Nullable, k, Nullable, nil, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (93) Argument: [T] -> Variable: [T!]! -> Value: nil -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, Nullable, nil, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (94) Argument: [T] -> Variable: [T!]! -> Value: nil -> Default: nil - FAIL
            {
                {{'list', Nullable, k, Nullable, nil, NonNullable, k, NonNullable, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (95) Argument: [T] -> Variable: [T!]! -> Value: nil -> Default: null - FAIL
            {
                {{'list', Nullable, k, Nullable, nil, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (96) Argument: [T] -> Variable: [T!]! -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, Nullable, box.NULL, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (97) Argument: [T] -> Variable: [T!]! -> Value: null -> Default: [] - FAIL
            {
                {{'list', Nullable, k, Nullable, box.NULL, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (98) Argument: [T] -> Variable: [T!]! -> Value: null -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, Nullable, box.NULL, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (99) Argument: [T] -> Variable: [T!]! -> Value: null -> Default: nil - FAIL
            {
                {{'list', Nullable, k, Nullable, box.NULL, NonNullable, k, NonNullable, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (100) Argument: [T] -> Variable: [T!]! -> Value: null -> Default: null - FAIL
            {
                {{'list', Nullable, k, Nullable, box.NULL, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (101) Argument: [T!] -> Variable: [T] -> Value: [value(s)] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, Nullable, k, Nullable, {v.default}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (102) Argument: [T!] -> Variable: [T] -> Value: [value(s)] -> Default: [nil] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, Nullable, k, Nullable, {nil}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (103) Argument: [T!] -> Variable: [T] -> Value: [value(s)] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, Nullable, k, Nullable, {box.NULL}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (104) Argument: [T!] -> Variable: [T] -> Value: [value(s)] -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (105) Argument: [T!] -> Variable: [T] -> Value: [value(s)] -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, Nullable, k, Nullable, box.NULL}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (106) Argument: [T!] -> Variable: [T] -> Value: [] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, Nullable, k, Nullable, {v.default}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (107) Argument: [T!] -> Variable: [T] -> Value: [] -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, Nullable, k, Nullable, {nil}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (108) Argument: [T!] -> Variable: [T] -> Value: [] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, Nullable, k, Nullable, {box.NULL}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (109) Argument: [T!] -> Variable: [T] -> Value: [] -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (110) Argument: [T!] -> Variable: [T] -> Value: [] -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, Nullable, k, Nullable, box.NULL}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (111) Argument: [T!] -> Variable: [T] -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, Nullable, k, Nullable, {v.default}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (112) Argument: [T!] -> Variable: [T] -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, Nullable, k, Nullable, {nil}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (113) Argument: [T!] -> Variable: [T] -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, Nullable, k, Nullable, {box.NULL}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (114) Argument: [T!] -> Variable: [T] -> Value: [null] -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (115) Argument: [T!] -> Variable: [T] -> Value: [null] -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, Nullable, k, Nullable, box.NULL}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (116) Argument: [T!] -> Variable: [T] -> Value: nil -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, Nullable, k, Nullable, {v.default}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (117) Argument: [T!] -> Variable: [T] -> Value: nil -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, Nullable, k, Nullable, {nil}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (118) Argument: [T!] -> Variable: [T] -> Value: nil -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, Nullable, k, Nullable, {box.NULL}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (119) Argument: [T!] -> Variable: [T] -> Value: nil -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (120) Argument: [T!] -> Variable: [T] -> Value: nil -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, Nullable, k, Nullable, box.NULL}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (121) Argument: [T!] -> Variable: [T] -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, Nullable, k, Nullable, {v.default}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (122) Argument: [T!] -> Variable: [T] -> Value: null -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, Nullable, k, Nullable, {nil}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (123) Argument: [T!] -> Variable: [T] -> Value: null -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, Nullable, k, Nullable, {box.NULL}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (124) Argument: [T!] -> Variable: [T] -> Value: null -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (125) Argument: [T!] -> Variable: [T] -> Value: null -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, Nullable, k, Nullable, box.NULL}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (126) Argument: [T!] -> Variable: [T!] -> Value: [value(s)] -> Default: [value(s)] - OK
            {{{'list', Nullable, k, NonNullable, {v.value}, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (127) Argument: [T!] -> Variable: [T!] -> Value: [value(s)] -> Default: [nil] - OK
            {{{'list', Nullable, k, NonNullable, {v.value}, Nullable, k, NonNullable, {nil}}}, nil},
            -- (128) Argument: [T!] -> Variable: [T!] -> Value: [value(s)] -> Default: [null] - OK
            {{{'list', Nullable, k, NonNullable, {v.value}, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (129) Argument: [T!] -> Variable: [T!] -> Value: [value(s)] -> Default: nil - OK
            {{{'list', Nullable, k, NonNullable, {v.value}, Nullable, k, NonNullable, nil}}, nil},
            -- (130) Argument: [T!] -> Variable: [T!] -> Value: [value(s)] -> Default: null - OK
            {{{'list', Nullable, k, NonNullable, {v.value}, Nullable, k, NonNullable, box.NULL}}, nil},
            -- (131) Argument: [T!] -> Variable: [T!] -> Value: [] -> Default: [value(s)] - OK
            {{{'list', Nullable, k, NonNullable, {}, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (132) Argument: [T!] -> Variable: [T!] -> Value: [] -> Default: [] - OK
            {{{'list', Nullable, k, NonNullable, {}, Nullable, k, NonNullable, {nil}}}, nil},
            -- (133) Argument: [T!] -> Variable: [T!] -> Value: [] -> Default: [null] - OK
            {{{'list', Nullable, k, NonNullable, {}, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (134) Argument: [T!] -> Variable: [T!] -> Value: [] -> Default: nil - OK
            {{{'list', Nullable, k, NonNullable, {}, Nullable, k, NonNullable, nil}}, nil},
            -- (135) Argument: [T!] -> Variable: [T!] -> Value: [] -> Default: null - OK
            {{{'list', Nullable, k, NonNullable, {}, Nullable, k, NonNullable, box.NULL}}, nil},
            -- (136) Argument: [T!] -> Variable: [T!] -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, Nullable, k, NonNullable, {v.default}}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (137) Argument: [T!] -> Variable: [T!] -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, Nullable, k, NonNullable, {nil}}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (138) Argument: [T!] -> Variable: [T!] -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, Nullable, k, NonNullable, {box.NULL}}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (139) Argument: [T!] -> Variable: [T!] -> Value: [null] -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, Nullable, k, NonNullable, nil}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (140) Argument: [T!] -> Variable: [T!] -> Value: [null] -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, Nullable, k, NonNullable, box.NULL}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (141) Argument: [T!] -> Variable: [T!] -> Value: nil -> Default: [value(s)] - OK
            {{{'list', Nullable, k, NonNullable, nil, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (142) Argument: [T!] -> Variable: [T!] -> Value: nil -> Default: [] - OK
            {{{'list', Nullable, k, NonNullable, nil, Nullable, k, NonNullable, {nil}}}, nil},
            -- (143) Argument: [T!] -> Variable: [T!] -> Value: nil -> Default: [null] - OK
            {{{'list', Nullable, k, NonNullable, nil, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (144) Argument: [T!] -> Variable: [T!] -> Value: nil -> Default: nil - OK
            {{{'list', Nullable, k, NonNullable, nil, Nullable, k, NonNullable, nil}}, nil},
            -- (145) Argument: [T!] -> Variable: [T!] -> Value: nil -> Default: null - OK
            {{{'list', Nullable, k, NonNullable, nil, Nullable, k, NonNullable, box.NULL}}, nil},
            -- (146) Argument: [T!] -> Variable: [T!] -> Value: null -> Default: [value(s)] - OK
            {{{'list', Nullable, k, NonNullable, box.NULL, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (147) Argument: [T!] -> Variable: [T!] -> Value: null -> Default: [] - OK
            {{{'list', Nullable, k, NonNullable, box.NULL, Nullable, k, NonNullable, {nil}}}, nil},
            -- (148) Argument: [T!] -> Variable: [T!] -> Value: null -> Default: [null] - OK
            {{{'list', Nullable, k, NonNullable, box.NULL, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (149) Argument: [T!] -> Variable: [T!] -> Value: null -> Default: nil - OK
            {{{'list', Nullable, k, NonNullable, box.NULL, Nullable, k, NonNullable, nil}}, nil},
            -- (150) Argument: [T!] -> Variable: [T!] -> Value: null -> Default: null - OK
            {{{'list', Nullable, k, NonNullable, box.NULL, Nullable, k, NonNullable, box.NULL}}, nil},
            -- (151) Argument: [T!] -> Variable: [T]! -> Value: [value(s)] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (152) Argument: [T!] -> Variable: [T]! -> Value: [value(s)] -> Default: [nil] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (153) Argument: [T!] -> Variable: [T]! -> Value: [value(s)] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (154) Argument: [T!] -> Variable: [T]! -> Value: [value(s)] -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (155) Argument: [T!] -> Variable: [T]! -> Value: [value(s)] -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (156) Argument: [T!] -> Variable: [T]! -> Value: [] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (157) Argument: [T!] -> Variable: [T]! -> Value: [] -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (158) Argument: [T!] -> Variable: [T]! -> Value: [] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (159) Argument: [T!] -> Variable: [T]! -> Value: [] -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (160) Argument: [T!] -> Variable: [T]! -> Value: [] -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (161) Argument: [T!] -> Variable: [T]! -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (162) Argument: [T!] -> Variable: [T]! -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (163) Argument: [T!] -> Variable: [T]! -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (164) Argument: [T!] -> Variable: [T]! -> Value: [null] -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (165) Argument: [T!] -> Variable: [T]! -> Value: [null] -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (166) Argument: [T!] -> Variable: [T]! -> Value: nil -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (167) Argument: [T!] -> Variable: [T]! -> Value: nil -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (168) Argument: [T!] -> Variable: [T]! -> Value: nil -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (169) Argument: [T!] -> Variable: [T]! -> Value: nil -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (170) Argument: [T!] -> Variable: [T]! -> Value: nil -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (171) Argument: [T!] -> Variable: [T]! -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (172) Argument: [T!] -> Variable: [T]! -> Value: null -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (173) Argument: [T!] -> Variable: [T]! -> Value: null -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (174) Argument: [T!] -> Variable: [T]! -> Value: null -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"List(NonNull('..v.var_type..'))\"',
            },
            -- (175) Argument: [T!] -> Variable: [T]! -> Value: null -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (176) Argument: [T!] -> Variable: [T!]! -> Value: [value(s)] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (177) Argument: [T!] -> Variable: [T!]! -> Value: [value(s)] -> Default: [nil] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (178) Argument: [T!] -> Variable: [T!]! -> Value: [value(s)] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (179) Argument: [T!] -> Variable: [T!]! -> Value: [value(s)] -> Default: nil - OK
            {{{'list', Nullable, k, NonNullable, {v.value}, NonNullable, k, NonNullable, nil}}, nil},
            -- (180) Argument: [T!] -> Variable: [T!]! -> Value: [value(s)] -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, {v.value}, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (181) Argument: [T!] -> Variable: [T!]! -> Value: [] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (182) Argument: [T!] -> Variable: [T!]! -> Value: [] -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (183) Argument: [T!] -> Variable: [T!]! -> Value: [] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (184) Argument: [T!] -> Variable: [T!]! -> Value: [] -> Default: nil - OK
            {{{'list', Nullable, k, NonNullable, {}, NonNullable, k, NonNullable, nil}}, nil},
            -- (185) Argument: [T!] -> Variable: [T!]! -> Value: [] -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, {}, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (186) Argument: [T!] -> Variable: [T!]! -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (187) Argument: [T!] -> Variable: [T!]! -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (188) Argument: [T!] -> Variable: [T!]! -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (189) Argument: [T!] -> Variable: [T!]! -> Value: [null] -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, NonNullable, k, NonNullable, nil}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (190) Argument: [T!] -> Variable: [T!]! -> Value: [null] -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, {box.NULL}, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (191) Argument: [T!] -> Variable: [T!]! -> Value: nil -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (192) Argument: [T!] -> Variable: [T!]! -> Value: nil -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (193) Argument: [T!] -> Variable: [T!]! -> Value: nil -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (194) Argument: [T!] -> Variable: [T!]! -> Value: nil -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, NonNullable, k, NonNullable, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (195) Argument: [T!] -> Variable: [T!]! -> Value: nil -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, nil, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (196) Argument: [T!] -> Variable: [T!]! -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (197) Argument: [T!] -> Variable: [T!]! -> Value: null -> Default: [] - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (198) Argument: [T!] -> Variable: [T!]! -> Value: null -> Default: [null] - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (199) Argument: [T!] -> Variable: [T!]! -> Value: null -> Default: nil - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, NonNullable, k, NonNullable, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (200) Argument: [T!] -> Variable: [T!]! -> Value: null -> Default: null - FAIL
            {
                {{'list', Nullable, k, NonNullable, box.NULL, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (201) Argument: [T]! -> Variable: [T] -> Value: [value(s)] -> Default: [value(s)] - OK
            {{{'list', NonNullable, k, Nullable, {v.value}, Nullable, k, Nullable, {v.default}}}, nil},
            -- (202) Argument: [T]! -> Variable: [T] -> Value: [value(s)] -> Default: [nil] - OK
            {{{'list', NonNullable, k, Nullable, {v.value}, Nullable, k, Nullable, {nil}}}, nil},
            -- (203) Argument: [T]! -> Variable: [T] -> Value: [value(s)] -> Default: [null] - OK
            {{{'list', NonNullable, k, Nullable, {v.value}, Nullable, k, Nullable, {box.NULL}}}, nil},
            -- (204) Argument: [T]! -> Variable: [T] -> Value: [value(s)] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, {v.value}, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"NonNull(List('..v.var_type..'))\"',
            },
            -- (205) Argument: [T]! -> Variable: [T] -> Value: [value(s)] -> Default: null - OK
            {{{'list', NonNullable, k, Nullable, {v.value}, Nullable, k, Nullable, box.NULL}}, nil},
            -- (206) Argument: [T]! -> Variable: [T] -> Value: [] -> Default: [value(s)] - OK
            {{{'list', NonNullable, k, Nullable, {}, Nullable, k, Nullable, {v.default}}}, nil},
            -- (207) Argument: [T]! -> Variable: [T] -> Value: [] -> Default: [] - OK
            {{{'list', NonNullable, k, Nullable, {}, Nullable, k, Nullable, {nil}}}, nil},
            -- (208) Argument: [T]! -> Variable: [T] -> Value: [] -> Default: [null] - OK
            {{{'list', NonNullable, k, Nullable, {}, Nullable, k, Nullable, {box.NULL}}}, nil},
            -- (209) Argument: [T]! -> Variable: [T] -> Value: [] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, {}, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"NonNull(List('..v.var_type..'))\"',
            },
            -- (210) Argument: [T]! -> Variable: [T] -> Value: [] -> Default: null - OK
            {{{'list', NonNullable, k, Nullable, {}, Nullable, k, Nullable, box.NULL}}, nil},
            -- (211) Argument: [T]! -> Variable: [T] -> Value: [null] -> Default: [value(s)] - OK
            {{{'list', NonNullable, k, Nullable, {box.NULL}, Nullable, k, Nullable, {v.default}}}, nil},
            -- (212) Argument: [T]! -> Variable: [T] -> Value: [null] -> Default: [] - OK
            {{{'list', NonNullable, k, Nullable, {box.NULL}, Nullable, k, Nullable, {nil}}}, nil},
            -- (213) Argument: [T]! -> Variable: [T] -> Value: [null] -> Default: [null] - OK
            {{{'list', NonNullable, k, Nullable, {box.NULL}, Nullable, k, Nullable, {box.NULL}}}, nil},
            -- (214) Argument: [T]! -> Variable: [T] -> Value: [null] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"NonNull(List('..v.var_type..'))\"',
            },
            -- (215) Argument: [T]! -> Variable: [T] -> Value: [null] -> Default: null - OK
            {{{'list', NonNullable, k, Nullable, {box.NULL}, Nullable, k, Nullable, box.NULL}}, nil},
            -- (216) Argument: [T]! -> Variable: [T] -> Value: nil -> Default: [value(s)] - OK
            {{{'list', NonNullable, k, Nullable, nil, Nullable, k, Nullable, {v.default}}}, nil},
            -- (217) Argument: [T]! -> Variable: [T] -> Value: nil -> Default: [] - OK
            {{{'list', NonNullable, k, Nullable, nil, Nullable, k, Nullable, {nil}}}, nil},
            -- (218) Argument: [T]! -> Variable: [T] -> Value: nil -> Default: [null] - OK
            {{{'list', NonNullable, k, Nullable, nil, Nullable, k, Nullable, {box.NULL}}}, nil},
            -- (219) Argument: [T]! -> Variable: [T] -> Value: nil -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"NonNull(List('..v.var_type..'))\"',
            },
            -- (220) Argument: [T]! -> Variable: [T] -> Value: nil -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, Nullable, k, Nullable, box.NULL}},
                'Expected non-null for \"NonNull(List('..v.var_type..'))\", got null',
            },
            -- (221) Argument: [T]! -> Variable: [T] -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, Nullable, k, Nullable, {v.default}}},
                'Expected non-null for \"NonNull(List('..v.var_type..'))\", got null',
            },
            -- (222) Argument: [T]! -> Variable: [T] -> Value: null -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, Nullable, k, Nullable, {nil}}},
                'Expected non-null for \"NonNull(List('..v.var_type..'))\", got null',
            },
            -- (223) Argument: [T]! -> Variable: [T] -> Value: null -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, Nullable, k, Nullable, {box.NULL}}},
                'Expected non-null for \"NonNull(List('..v.var_type..'))\", got null',
            },
            -- (224) Argument: [T]! -> Variable: [T] -> Value: null -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"NonNull(List('..v.var_type..'))\"',
            },
            -- (225) Argument: [T]! -> Variable: [T] -> Value: null -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, Nullable, k, Nullable, box.NULL}},
                'Expected non-null for \"NonNull(List('..v.var_type..'))\", got null',
            },
            -- (226) Argument: [T]! -> Variable: [T!] -> Value: [value(s)] -> Default: [value(s)] - OK
            {{{'list', NonNullable, k, Nullable, {v.value}, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (227) Argument: [T]! -> Variable: [T!] -> Value: [value(s)] -> Default: [nil] - OK
            {{{'list', NonNullable, k, Nullable, {v.value}, Nullable, k, NonNullable, {nil}}}, nil},
            -- (228) Argument: [T]! -> Variable: [T!] -> Value: [value(s)] -> Default: [null] - OK
            {{{'list', NonNullable, k, Nullable, {v.value}, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (229) Argument: [T]! -> Variable: [T!] -> Value: [value(s)] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, {v.value}, Nullable, k, NonNullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List(NonNull('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List('..v.var_type..'))\"',
            },
            -- (230) Argument: [T]! -> Variable: [T!] -> Value: [value(s)] -> Default: null - OK
            {{{'list', NonNullable, k, Nullable, {v.value}, Nullable, k, NonNullable, box.NULL}}, nil},
            -- (231) Argument: [T]! -> Variable: [T!] -> Value: [] -> Default: [value(s)] - OK
            {{{'list', NonNullable, k, Nullable, {}, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (232) Argument: [T]! -> Variable: [T!] -> Value: [] -> Default: [] - OK
            {{{'list', NonNullable, k, Nullable, {}, Nullable, k, NonNullable, {nil}}}, nil},
            -- (233) Argument: [T]! -> Variable: [T!] -> Value: [] -> Default: [null] - OK
            {{{'list', NonNullable, k, Nullable, {}, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (234) Argument: [T]! -> Variable: [T!] -> Value: [] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, {}, Nullable, k, NonNullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List(NonNull('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List('..v.var_type..'))\"',
            },
            -- (235) Argument: [T]! -> Variable: [T!] -> Value: [] -> Default: null - OK
            {{{'list', NonNullable, k, Nullable, {}, Nullable, k, NonNullable, box.NULL}}, nil},
            -- (236) Argument: [T]! -> Variable: [T!] -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, Nullable, k, NonNullable, {v.default}}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (237) Argument: [T]! -> Variable: [T!] -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, Nullable, k, NonNullable, {nil}}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (238) Argument: [T]! -> Variable: [T!] -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, Nullable, k, NonNullable, {box.NULL}}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (239) Argument: [T]! -> Variable: [T!] -> Value: [null] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, Nullable, k, NonNullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List(NonNull('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List('..v.var_type..'))\"',
            },
            -- (240) Argument: [T]! -> Variable: [T!] -> Value: [null] -> Default: null - OK
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, Nullable, k, NonNullable, box.NULL}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (241) Argument: [T]! -> Variable: [T!] -> Value: nil -> Default: [value(s)] - OK
            {{{'list', NonNullable, k, Nullable, nil, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (242) Argument: [T]! -> Variable: [T!] -> Value: nil -> Default: [] - OK
            {{{'list', NonNullable, k, Nullable, nil, Nullable, k, NonNullable, {nil}}}, nil},
            -- (243) Argument: [T]! -> Variable: [T!] -> Value: nil -> Default: [null] - OK
            {{{'list', NonNullable, k, Nullable, nil, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (244) Argument: [T]! -> Variable: [T!] -> Value: nil -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, Nullable, k, NonNullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List(NonNull('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List('..v.var_type..'))\"',
            },
            -- (245) Argument: [T]! -> Variable: [T!] -> Value: nil -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, Nullable, k, NonNullable, box.NULL}},
                'Expected non-null for \"NonNull(List('..v.var_type..'))\", got null',
            },
            -- (246) Argument: [T]! -> Variable: [T!] -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, Nullable, k, NonNullable, {v.default}}},
                'Expected non-null for \"NonNull(List('..v.var_type..'))\", got null',
            },
            -- (247) Argument: [T]! -> Variable: [T!] -> Value: null -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, Nullable, k, NonNullable, {nil}}},
                'Expected non-null for \"NonNull(List('..v.var_type..'))\", got null',
            },
            -- (248) Argument: [T]! -> Variable: [T!] -> Value: null -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, Nullable, k, NonNullable, {box.NULL}}},
                'Expected non-null for \"NonNull(List('..v.var_type..'))\", got null',
            },
            -- (249) Argument: [T]! -> Variable: [T!] -> Value: null -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, Nullable, k, NonNullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List(NonNull('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List('..v.var_type..'))\"',
            },
            -- (250) Argument: [T]! -> Variable: [T!] -> Value: null -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, Nullable, k, NonNullable, box.NULL}},
                'Expected non-null for \"NonNull(List('..v.var_type..'))\", got null',
            },
            -- (251) Argument: [T]! -> Variable: [T]! -> Value: [value(s)] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {v.value}, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (252) Argument: [T]! -> Variable: [T]! -> Value: [value(s)] -> Default: [nil] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {v.value}, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (253) Argument: [T]! -> Variable: [T]! -> Value: [value(s)] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {v.value}, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (254) Argument: [T]! -> Variable: [T]! -> Value: [value(s)] -> Default: nil - OK
            {{{'list', NonNullable, k, Nullable, {v.value}, NonNullable, k, Nullable, nil}}, nil},
            -- (255) Argument: [T]! -> Variable: [T]! -> Value: [value(s)] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, {v.value}, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (256) Argument: [T]! -> Variable: [T]! -> Value: [] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {}, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (257) Argument: [T]! -> Variable: [T]! -> Value: [] -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {}, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (258) Argument: [T]! -> Variable: [T]! -> Value: [] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {}, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (259) Argument: [T]! -> Variable: [T]! -> Value: [] -> Default: nil - OK
            {{{'list', NonNullable, k, Nullable, {}, NonNullable, k, Nullable, nil}}, nil},
            -- (260) Argument: [T]! -> Variable: [T]! -> Value: [] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, {}, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (261) Argument: [T]! -> Variable: [T]! -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (262) Argument: [T]! -> Variable: [T]! -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (263) Argument: [T]! -> Variable: [T]! -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (264) Argument: [T]! -> Variable: [T]! -> Value: [null] -> Default: nil - OK
            {{{'list', NonNullable, k, Nullable, {box.NULL}, NonNullable, k, Nullable, nil}}, nil},
            -- (265) Argument: [T]! -> Variable: [T]! -> Value: [null] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (266) Argument: [T]! -> Variable: [T]! -> Value: nil -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (267) Argument: [T]! -> Variable: [T]! -> Value: nil -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (268) Argument: [T]! -> Variable: [T]! -> Value: nil -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (269) Argument: [T]! -> Variable: [T]! -> Value: nil -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (270) Argument: [T]! -> Variable: [T]! -> Value: nil -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (271) Argument: [T]! -> Variable: [T]! -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (272) Argument: [T]! -> Variable: [T]! -> Value: null -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (273) Argument: [T]! -> Variable: [T]! -> Value: null -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (274) Argument: [T]! -> Variable: [T]! -> Value: null -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (275) Argument: [T]! -> Variable: [T]! -> Value: null -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (276) Argument: [T]! -> Variable: [T!]! -> Value: [value(s)] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {v.value}, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (277) Argument: [T]! -> Variable: [T!]! -> Value: [value(s)] -> Default: [nil] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {v.value}, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (278) Argument: [T]! -> Variable: [T!]! -> Value: [value(s)] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {v.value}, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (279) Argument: [T]! -> Variable: [T!]! -> Value: [value(s)] -> Default: nil - OK
            {{{'list', NonNullable, k, Nullable, {v.value}, NonNullable, k, NonNullable, nil}}, nil},
            -- (280) Argument: [T]! -> Variable: [T!]! -> Value: [value(s)] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, {v.value}, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (281) Argument: [T]! -> Variable: [T!]! -> Value: [] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {}, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (282) Argument: [T]! -> Variable: [T!]! -> Value: [] -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {}, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (283) Argument: [T]! -> Variable: [T!]! -> Value: [] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {}, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (284) Argument: [T]! -> Variable: [T!]! -> Value: [] -> Default: nil - OK
            {{{'list', NonNullable, k, Nullable, {}, NonNullable, k, NonNullable, nil}}, nil},
            -- (285) Argument: [T]! -> Variable: [T!]! -> Value: [] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, {}, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (286) Argument: [T]! -> Variable: [T!]! -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (287) Argument: [T]! -> Variable: [T!]! -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (288) Argument: [T]! -> Variable: [T!]! -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (289) Argument: [T]! -> Variable: [T!]! -> Value: [null] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, NonNullable, k, NonNullable, nil}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (290) Argument: [T]! -> Variable: [T!]! -> Value: [null] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, {box.NULL}, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (291) Argument: [T]! -> Variable: [T!]! -> Value: nil -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (292) Argument: [T]! -> Variable: [T!]! -> Value: nil -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (293) Argument: [T]! -> Variable: [T!]! -> Value: nil -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (294) Argument: [T]! -> Variable: [T!]! -> Value: nil -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, NonNullable, k, NonNullable, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (295) Argument: [T]! -> Variable: [T!]! -> Value: nil -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, nil, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (296) Argument: [T]! -> Variable: [T!]! -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (297) Argument: [T]! -> Variable: [T!]! -> Value: null -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (298) Argument: [T]! -> Variable: [T!]! -> Value: null -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (299) Argument: [T]! -> Variable: [T!]! -> Value: null -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, NonNullable, k, NonNullable, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (300) Argument: [T]! -> Variable: [T!]! -> Value: null -> Default: null - FAIL
            {
                {{'list', NonNullable, k, Nullable, box.NULL, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (301) Argument: [T!]! -> Variable: [T] -> Value: [value(s)] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, Nullable, k, Nullable, {v.default}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (302) Argument: [T!]! -> Variable: [T] -> Value: [value(s)] -> Default: [nil] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, Nullable, k, Nullable, {nil}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (303) Argument: [T!]! -> Variable: [T] -> Value: [value(s)] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, Nullable, k, Nullable, {box.NULL}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (304) Argument: [T!]! -> Variable: [T] -> Value: [value(s)] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (305) Argument: [T!]! -> Variable: [T] -> Value: [value(s)] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, Nullable, k, Nullable, box.NULL}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (306) Argument: [T!]! -> Variable: [T] -> Value: [] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, Nullable, k, Nullable, {v.default}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (307) Argument: [T!]! -> Variable: [T] -> Value: [] -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, Nullable, k, Nullable, {nil}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (308) Argument: [T!]! -> Variable: [T] -> Value: [] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, Nullable, k, Nullable, {box.NULL}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (309) Argument: [T!]! -> Variable: [T] -> Value: [] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (310) Argument: [T!]! -> Variable: [T] -> Value: [] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, Nullable, k, Nullable, box.NULL}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (311) Argument: [T!]! -> Variable: [T] -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, Nullable, k, Nullable, {v.default}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (312) Argument: [T!]! -> Variable: [T] -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, Nullable, k, Nullable, {nil}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (313) Argument: [T!]! -> Variable: [T] -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, Nullable, k, Nullable, {box.NULL}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (314) Argument: [T!]! -> Variable: [T] -> Value: [null] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (315) Argument: [T!]! -> Variable: [T] -> Value: [null] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, Nullable, k, Nullable, box.NULL}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (316) Argument: [T!]! -> Variable: [T] -> Value: nil -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, Nullable, k, Nullable, {v.default}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (317) Argument: [T!]! -> Variable: [T] -> Value: nil -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, Nullable, k, Nullable, {nil}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (318) Argument: [T!]! -> Variable: [T] -> Value: nil -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, Nullable, k, Nullable, {box.NULL}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (319) Argument: [T!]! -> Variable: [T] -> Value: nil -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (320) Argument: [T!]! -> Variable: [T] -> Value: nil -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, Nullable, k, Nullable, box.NULL}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (321) Argument: [T!]! -> Variable: [T] -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, Nullable, k, Nullable, {v.default}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (322) Argument: [T!]! -> Variable: [T] -> Value: null -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, Nullable, k, Nullable, {nil}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (323) Argument: [T!]! -> Variable: [T] -> Value: null -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, Nullable, k, Nullable, {box.NULL}}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (324) Argument: [T!]! -> Variable: [T] -> Value: null -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, Nullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List('..v.var_type..')\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (325) Argument: [T!]! -> Variable: [T] -> Value: null -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, Nullable, k, Nullable, box.NULL}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (326) Argument: [T!]! -> Variable: [T!] -> Value: [value(s)] -> Default: [value(s)] - OK
            {{{'list', NonNullable, k, NonNullable, {v.value}, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (327) Argument: [T!]! -> Variable: [T!] -> Value: [value(s)] -> Default: [nil] - OK
            {{{'list', NonNullable, k, NonNullable, {v.value}, Nullable, k, NonNullable, {nil}}}, nil},
            -- (328) Argument: [T!]! -> Variable: [T!] -> Value: [value(s)] -> Default: [null] - OK
            {{{'list', NonNullable, k, NonNullable, {v.value}, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (329) Argument: [T!]! -> Variable: [T!] -> Value: [value(s)] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, Nullable, k, NonNullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List(NonNull('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (330) Argument: [T!]! -> Variable: [T!] -> Value: [value(s)] -> Default: null - OK
            {{{'list', NonNullable, k, NonNullable, {v.value}, Nullable, k, NonNullable, box.NULL}}, nil},
            -- (331) Argument: [T!]! -> Variable: [T!] -> Value: [] -> Default: [value(s)] - OK
            {{{'list', NonNullable, k, NonNullable, {}, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (332) Argument: [T!]! -> Variable: [T!] -> Value: [] -> Default: [] - OK
            {{{'list', NonNullable, k, NonNullable, {}, Nullable, k, NonNullable, {nil}}}, nil},
            -- (333) Argument: [T!]! -> Variable: [T!] -> Value: [] -> Default: [null] - OK
            {{{'list', NonNullable, k, NonNullable, {}, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (334) Argument: [T!]! -> Variable: [T!] -> Value: [] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, Nullable, k, NonNullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List(NonNull('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (335) Argument: [T!]! -> Variable: [T!] -> Value: [] -> Default: null - OK
            {{{'list', NonNullable, k, NonNullable, {}, Nullable, k, NonNullable, box.NULL}}, nil},
            -- (336) Argument: [T!]! -> Variable: [T!] -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, Nullable, k, NonNullable, {v.default}}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (337) Argument: [T!]! -> Variable: [T!] -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, Nullable, k, NonNullable, {nil}}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (338) Argument: [T!]! -> Variable: [T!] -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, Nullable, k, NonNullable, {box.NULL}}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (339) Argument: [T!]! -> Variable: [T!] -> Value: [null] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, Nullable, k, NonNullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List(NonNull('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (340) Argument: [T!]! -> Variable: [T!] -> Value: [null] -> Default: null - OK
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, Nullable, k, NonNullable, box.NULL}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (341) Argument: [T!]! -> Variable: [T!] -> Value: nil -> Default: [value(s)] - OK
            {{{'list', NonNullable, k, NonNullable, nil, Nullable, k, NonNullable, {v.default}}}, nil},
            -- (342) Argument: [T!]! -> Variable: [T!] -> Value: nil -> Default: [] - OK
            {{{'list', NonNullable, k, NonNullable, nil, Nullable, k, NonNullable, {nil}}}, nil},
            -- (343) Argument: [T!]! -> Variable: [T!] -> Value: nil -> Default: [null] - OK
            {{{'list', NonNullable, k, NonNullable, nil, Nullable, k, NonNullable, {box.NULL}}}, nil},
            -- (344) Argument: [T!]! -> Variable: [T!] -> Value: nil -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, Nullable, k, NonNullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List(NonNull('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (345) Argument: [T!]! -> Variable: [T!] -> Value: nil -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, Nullable, k, NonNullable, box.NULL}},
                'Expected non-null for \"NonNull(List(NonNull('..v.var_type..')))\", got null',
            },
            -- (346) Argument: [T!]! -> Variable: [T!] -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, Nullable, k, NonNullable, {v.default}}},
                'Expected non-null for \"NonNull(List(NonNull('..v.var_type..')))\", got null',
            },
            -- (347) Argument: [T!]! -> Variable: [T!] -> Value: null -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, Nullable, k, NonNullable, {nil}}},
                'Expected non-null for \"NonNull(List(NonNull('..v.var_type..')))\", got null',
            },
            -- (348) Argument: [T!]! -> Variable: [T!] -> Value: null -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, Nullable, k, NonNullable, {box.NULL}}},
                'Expected non-null for \"NonNull(List(NonNull('..v.var_type..')))\", got null',
            },
            -- (349) Argument: [T!]! -> Variable: [T!] -> Value: null -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, Nullable, k, NonNullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"List(NonNull('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (350) Argument: [T!]! -> Variable: [T!] -> Value: null -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, Nullable, k, NonNullable, box.NULL}},
                'Expected non-null for \"NonNull(List(NonNull('..v.var_type..')))\", got null',
            },
            -- (351) Argument: [T!]! -> Variable: [T]! -> Value: [value(s)] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (352) Argument: [T!]! -> Variable: [T]! -> Value: [value(s)] -> Default: [nil] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (353) Argument: [T!]! -> Variable: [T]! -> Value: [value(s)] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (354) Argument: [T!]! -> Variable: [T]! -> Value: [value(s)] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (355) Argument: [T!]! -> Variable: [T]! -> Value: [value(s)] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (356) Argument: [T!]! -> Variable: [T]! -> Value: [] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (357) Argument: [T!]! -> Variable: [T]! -> Value: [] -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (358) Argument: [T!]! -> Variable: [T]! -> Value: [] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (359) Argument: [T!]! -> Variable: [T]! -> Value: [] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (360) Argument: [T!]! -> Variable: [T]! -> Value: [] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (361) Argument: [T!]! -> Variable: [T]! -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (362) Argument: [T!]! -> Variable: [T]! -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (363) Argument: [T!]! -> Variable: [T]! -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (364) Argument: [T!]! -> Variable: [T]! -> Value: [null] -> Default: nil - OK
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (365) Argument: [T!]! -> Variable: [T]! -> Value: [null] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (366) Argument: [T!]! -> Variable: [T]! -> Value: nil -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (367) Argument: [T!]! -> Variable: [T]! -> Value: nil -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (368) Argument: [T!]! -> Variable: [T]! -> Value: nil -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (369) Argument: [T!]! -> Variable: [T]! -> Value: nil -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (370) Argument: [T!]! -> Variable: [T]! -> Value: nil -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (371) Argument: [T!]! -> Variable: [T]! -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, NonNullable, k, Nullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (372) Argument: [T!]! -> Variable: [T]! -> Value: null -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, NonNullable, k, Nullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (373) Argument: [T!]! -> Variable: [T]! -> Value: null -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, NonNullable, k, Nullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (374) Argument: [T!]! -> Variable: [T]! -> Value: null -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, NonNullable, k, Nullable, nil}},
                'Variable \"var1\" type mismatch: the variable type \"NonNull(List('..v.var_type..'))\" '..
                'is not compatible with the argument type \"NonNull(List(NonNull('..v.var_type..')))\"',
            },
            -- (375) Argument: [T!]! -> Variable: [T]! -> Value: null -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, NonNullable, k, Nullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (376) Argument: [T!]! -> Variable: [T!]! -> Value: [value(s)] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (377) Argument: [T!]! -> Variable: [T!]! -> Value: [value(s)] -> Default: [nil] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (378) Argument: [T!]! -> Variable: [T!]! -> Value: [value(s)] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (379) Argument: [T!]! -> Variable: [T!]! -> Value: [value(s)] -> Default: nil - OK
            {{{'list', NonNullable, k, NonNullable, {v.value}, NonNullable, k, NonNullable, nil}}, nil},
            -- (380) Argument: [T!]! -> Variable: [T!]! -> Value: [value(s)] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {v.value}, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (381) Argument: [T!]! -> Variable: [T!]! -> Value: [] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (382) Argument: [T!]! -> Variable: [T!]! -> Value: [] -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (383) Argument: [T!]! -> Variable: [T!]! -> Value: [] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (384) Argument: [T!]! -> Variable: [T!]! -> Value: [] -> Default: nil - OK
            {{{'list', NonNullable, k, NonNullable, {}, NonNullable, k, NonNullable, nil}}, nil},
            -- (385) Argument: [T!]! -> Variable: [T!]! -> Value: [] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {}, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (386) Argument: [T!]! -> Variable: [T!]! -> Value: [null] -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (387) Argument: [T!]! -> Variable: [T!]! -> Value: [null] -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (388) Argument: [T!]! -> Variable: [T!]! -> Value: [null] -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (389) Argument: [T!]! -> Variable: [T!]! -> Value: [null] -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, NonNullable, k, NonNullable, nil}},
                'Variable \"var1[1]\" expected to be non-null',
            },
            -- (390) Argument: [T!]! -> Variable: [T!]! -> Value: [null] -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, {box.NULL}, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (391) Argument: [T!]! -> Variable: [T!]! -> Value: nil -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (392) Argument: [T!]! -> Variable: [T!]! -> Value: nil -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (393) Argument: [T!]! -> Variable: [T!]! -> Value: nil -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (394) Argument: [T!]! -> Variable: [T!]! -> Value: nil -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, NonNullable, k, NonNullable, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (395) Argument: [T!]! -> Variable: [T!]! -> Value: nil -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, nil, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
            -- (396) Argument: [T!]! -> Variable: [T!]! -> Value: null -> Default: [value(s)] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, NonNullable, k, NonNullable, {v.default}}},
                'Non-null variables can not have default values',
            },
            -- (397) Argument: [T!]! -> Variable: [T!]! -> Value: null -> Default: [] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, NonNullable, k, NonNullable, {nil}}},
                'Non-null variables can not have default values',
            },
            -- (398) Argument: [T!]! -> Variable: [T!]! -> Value: null -> Default: [null] - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, NonNullable, k, NonNullable, {box.NULL}}},
                'Non-null variables can not have default values',
            },
            -- (399) Argument: [T!]! -> Variable: [T!]! -> Value: null -> Default: nil - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, NonNullable, k, NonNullable, nil}},
                'Variable \"var1\" expected to be non-null',
            },
            -- (400) Argument: [T!]! -> Variable: [T!]! -> Value: null -> Default: null - FAIL
            {
                {{'list', NonNullable, k, NonNullable, box.NULL, NonNullable, k, NonNullable, box.NULL}},
                'Non-null variables can not have default values',
            },
        }
        check_suite('Single list argument with vars', test_suite)
    end
end

-- Test multiple scalar, inputObject or enum arguments
g.test_multiple_nonlist_arguments_nullability = function ()
    for k, v in pairs(graphql_types) do
        local test_suite = {
            -- (1) Argument1: T, Value1: value, Argument2: T, Value2: value - OK
            {
                {{k, Nullable, nil, nil, v.value, nil, nil, nil}, {k, Nullable, nil, nil, v.value, nil, nil, nil}},
                nil,
            },
            -- (2) Argument1: T, Value1: null, Argument2: T, Value2: value - OK
            {
                {{k, Nullable, nil, nil, nil, nil, nil, nil}, {k, Nullable, nil, nil, v.value, nil, nil, nil}},
                nil,
            },
            -- (3) Argument1: T, Value1: value, Argument2: T, Value2: null - OK
            {
                {{k, Nullable, nil, nil, v.value, nil, nil, nil}, {k, Nullable, nil, nil, nil, nil, nil, nil}},
                nil,
            },
            -- (4) Argument1: T, Value1: null, Argument2: T, Value2: null - OK
            {
                {{k, Nullable, nil, nil, nil, nil, nil, nil}, {k, Nullable, nil, nil, nil, nil, nil, nil}},
                nil,
            },
            -- (5) Argument1: T, Value1: value, Argument2: T!, Value2: value - OK
            {
                {
                    {k, Nullable, nil, nil, v.value, nil, nil, nil},
                    {k, NonNullable, nil, nil, v.value, nil, nil, nil}
                },
                nil,
            },
            -- (6) Argument1: T, Value1: null, Argument2: T!, Value2: value - OK
            {
                {{k, Nullable, nil, nil, nil, nil, nil, nil}, {k, NonNullable, nil, nil, v.value, nil, nil, nil}},
                nil,
            },
            -- (7) Argument1: T, Value1: value, Argument2: T!, Value2: null - FAIL
            {
                {
                    {k, Nullable, nil, nil, v.value, nil, nil, nil},
                    {k, NonNullable, nil, nil, nil, nil, nil, nil, nil},
                },
                'Expected non-null for "NonNull('..v.var_type..')", got null',
            },
            -- (8) Argument1: T, Value1: null, Argument2: T!, Value2: null - FAIL
            {
                {{k, Nullable, nil, nil, nil, nil, nil, nil}, {k, NonNullable, nil, nil, nil, nil, nil, nil}},
                'Expected non-null for "NonNull('..v.var_type..')", got null',
            },
            -- (9) Argument1: T!, Value1: value, Argument2: T, Value2: value - OK
            {
                {
                    {k, NonNullable, nil, nil, v.value, nil, nil, nil},
                    {k, Nullable, nil, nil, v.value, nil, nil, nil}
                },
                nil,
            },
            -- (10) Argument1: T!, Value1: null, Argument2: T, Value2: value - FAIL
            {
                {{k, NonNullable, nil, nil, nil, nil, nil, nil}, {k, Nullable, nil, nil, v.value, nil, nil, nil}},
                'Expected non-null for "NonNull('..v.var_type..')", got null',
            },
            -- (11) Argument1: T!, Value1: value, Argument2: T, Value2: null - OK
            {
                {{k, NonNullable, nil, nil, v.value, nil, nil, nil}, {k, Nullable, nil, nil, nil, nil, nil, nil}},
                nil,
            },
            -- (12) Argument1: T!, Value1: null, Argument2: T, Value2: null - FAIL
            {
                {{k, NonNullable, nil, nil, nil, nil, nil, nil}, {k, Nullable, nil, nil, nil, nil, nil, nil}},
                'Expected non-null for "NonNull('..v.var_type..')", got null',
            },
            -- (13) Argument1: T!, Value1: value, Argument2: T!, Value2: value - OK
            {
                {{k, NonNullable, nil, nil, v.value, nil, nil, nil}, {k, NonNullable, nil, nil, v.value, nil, nil}},
                nil,
            },
            -- (14) Argument1: T!, Value1: null, Argument2: T!, Value2: value - FAIL
            {
                {{k, NonNullable, nil, nil, nil, nil, nil, nil}, {k, NonNullable, nil, nil, v.value, nil, nil, nil}},
                'Expected non-null for "NonNull('..v.var_type..')", got null',
            },
            -- (15) Argument1: T!, Value1: value, Argument2: T!, Value2: null - FAIL
            {
                {{k, NonNullable, nil, nil, v.value, nil, nil, nil}, {k, NonNullable, nil, nil, nil, nil, nil, nil}},
                'Expected non-null for "NonNull('..v.var_type..')", got null',
            },
            -- (16) Argument1: T!, Value1: null, Argument2: T!, Value2: null - FAIL
            {
                {{k, NonNullable, nil, nil, nil, nil, nil, nil}, {k, NonNullable, nil, nil, nil, nil, nil, nil}},
                'Expected non-null for "NonNull('..v.var_type..')", got null',
            },
        }
        check_suite('Multiple scalar, inputObject or enum arguments', test_suite)
    end
end

-- Test multiple scalar, inputObject or enum arguments and value provided with variables
g.test_multiple_nonlist_arguments_with_variables_nullability = function ()
    for k, v in pairs(graphql_types) do
        local test_suite = {
            -- (1) Argument1: T->Variable1: T->Value1: value, Argument2: T->Variable2: T->Value2: value - OK
            {{
                {k, Nullable, nil, nil, v.value, Nullable, nil, nil},
                {k, Nullable, nil, nil, v.value, Nullable, nil, nil},
            }, nil},
            -- (2) Argument1: T->Variable1: T->Value1: null, Argument2: T->Variable2: T->Value2: value - OK
            {{
                {k, Nullable, nil, nil, nil, Nullable, nil, nil},
                {k, Nullable, nil, nil, v.value, Nullable, nil, nil},
            }, nil},
            -- (3) Argument1: T->Variable1: T->Value1: value, Argument2: T->Variable2: T->Value2: null - OK
            {{
                {k, Nullable, nil, nil, v.value, Nullable, nil, nil},
                {k, Nullable, nil, nil, nil, Nullable, nil, nil},
            }, nil},
            -- (4) Argument1: T->Variable1: T->Value1: null, Argument2: T->Variable2: T->Value2: null - OK
            {{
                {k, Nullable, nil, nil, nil, Nullable, nil, nil},
                {k, Nullable, nil, nil, nil, Nullable, nil, nil},
            }, nil},
            -- (5) Argument1: T->Variable1: T->Value1: value, Argument2: T!->Variable2: T!->Value2: value - OK
            {{
                {k, Nullable, nil, nil, v.value, Nullable, nil, nil},
                {k, NonNullable, nil, nil, v.value, NonNullable, nil, nil},
            }, nil},
            -- (6) Argument1: T->Variable1: T->Value1: null, Argument2: T!->Variable2: T!->Value2: value - OK
            {{
                {k, Nullable, nil, nil, nil, Nullable, nil, nil},
                {k, NonNullable, nil, nil, v.value, NonNullable, nil, nil},
            }, nil},
            -- (7) Argument1: T->Variable1: T->Value1: value, Argument2: T!->Variable2: T!->Value2: null - FAIL
            {{
                {k, Nullable, nil, nil, v.value, Nullable, nil, nil},
                {k, NonNullable, nil, nil, nil, NonNullable, nil, nil},
            }, 'Variable "var2" expected to be non-null'},
            -- (8) Argument1: T->Variable1: T->Value1: null, Argument2: T!->Variable2: T!->Value2: null - FAIL
            {{
                {k, Nullable, nil, nil, nil, Nullable, nil, nil},
                {k, NonNullable, nil, nil, nil, NonNullable, nil, nil},
            }, 'Variable "var2" expected to be non-null' },
            -- (9) Argument1: T!->Variable1: T!->Value1: value, Argument2: T->Variable2: T->Value2: value - OK
            {{
                {k, NonNullable, nil, nil, v.value, NonNullable, nil, nil},
                {k, Nullable, nil, nil, v.value, Nullable, nil, nil},
            }, nil},
            -- (10) Argument1: T!->Variable1: T!->Value1: null, Argument2: T->Variable2: T->Value2: value - FAIL
            {{
                {k, NonNullable, nil, nil, nil, NonNullable, nil, nil},
                {k, Nullable, nil, nil, v.value, Nullable, nil, nil},
            }, 'Variable "var1" expected to be non-null'},
            -- (11) Argument1: T!->Variable1: T!->Value1: value, Argument2: T->Variable2: T->Value2: nil - OK
            {{
                {k, NonNullable, nil, nil, v.value, NonNullable, nil, nil},
                {k, Nullable, nil, nil, nil, Nullable, nil, nil},
            }, nil},
            -- (12) Argument1: T!->Variable1: T!->Value1: nil, Argument2: T->Variable2: T->Value2: nil - FAIL
            {{
                {k, NonNullable, nil, nil, nil, NonNullable, nil, nil},
                {k, Nullable, nil, nil, nil, Nullable, nil, nil},
            }, 'Variable "var1" expected to be non-null'},
            -- (13) Argument1: T!->Variable1: T!->Value1: value, Argument2: T!->Variable2: T!->Value2: value - OK
            {{
                {k, NonNullable, nil, nil, v.value, NonNullable, nil, nil},
                {k, NonNullable, nil, nil, v.value, NonNullable, nil, nil},
            }, nil},
            -- (14) Argument1: T!->Variable1: T!->Value1: null, Argument2: T!->Variable2: T!->Value2: value - FAIL
            {{
                {k, NonNullable, nil, nil, nil, NonNullable, nil, nil},
                {k, NonNullable, nil, nil, v.value, NonNullable, nil, nil},
            }, 'Variable "var1" expected to be non-null'},
            -- (15) Argument1: T!->Variable1: T!->Value1: value, Argument2: T!->Variable2: T!->Value2: null - FAIL
            {{
                {k, NonNullable, nil, nil, v.value, NonNullable, nil, nil},
                {k, NonNullable, nil, nil, nil, NonNullable, nil, nil},
            }, 'Variable "var2" expected to be non-null'},
            -- (16) Argument1: T!->Variable1: T!->Value1: null, Argument2: T!->Variable2: T!->Value2: null - FAIL
            {{
                {k, NonNullable, nil, nil, nil, NonNullable, nil, nil},
                {k, NonNullable, nil, nil, nil, NonNullable, nil, nil},
            }, 'Variable "var2" expected to be non-null'},
        }
        check_suite('Multiple scalar, inputObject or enum arguments and value provided with variables', test_suite)
    end
end
