local swagger = import 'kubernetes-spec/swagger.json';

{
  definitions: {
    [m]: swagger.definitions[m]
    for m in std.objectFields(swagger.definitions)
    if !std.endsWith(m, 'Status')
       && !std.endsWith(m, 'List')
    // Beyond this, the improvements are marginal
    //&& !std.endsWith(m, 'ListMeta')
    //&& !std.endsWith(m, 'Condition')
    //&& !std.endsWith(m, 'JSONSchemaProps')
  },
}
