local camelcase = import 'camelcase.libsonnet';
local k8s = import 'kubernetes-spec-v1.23/api__v1_openapi.json';

{
  local this = self,
  local debug = false,

  local getVersionInDefinition(definition, version) =
    local versions = [
      v
      for v in definition.spec.versions
      if v.name == version
    ];
    if std.length(versions) == 0
    then error 'version %s in definition %s not found' % [version, definition.metadata.name]
    else if std.length(versions) > 1
    then error 'multiple versions match %s in definition' % [version, definition.metadata.name]
    else versions[0],

  local createFunction(name, parents) =
    {
      ['with' + std.asciiUpper(name[0]) + name[1:]](value):
        std.foldr(
          function(p, acc)
            if p == name
            then acc
            else { [p]+: acc }
          ,
          parents,
          { [name]: value }
        ),
    },

  local appendFunction(name, parents) =
    {
      ['with' + std.asciiUpper(name[0]) + name[1:] + 'Mixin'](value):
        std.foldr(
          function(p, acc)
            if p == name
            then acc
            else { [p]+: acc }
          ,
          parents,
          { [name]+: [value] }
        ),
    },

  local handleObject(name, parents, properties, siblings={}) =
    std.foldl(
      function(acc, p)
        acc {
          [name]+: this.propertyToValue(
            p,
            parents + [p],
            properties[p],
            siblings,
          ),
        },
      std.objectFields(properties),
      {}
    ),

  propertyToValue(name, parents, property, siblings={}):
    local infoMessage(message, return) =
      if debug
      then std.trace('INFO: ' + message, return)
      else return;

    local type =
      if std.objectHas(property, 'type')
      then property.type

      // TODO: figure out how to handle allOf, oneOf or anyOf properly,
      // would we expect 'array' or 'object' here?
      else if std.objectHas(property, 'allOf')
              || std.objectHas(property, 'oneOf')
              || std.objectHas(property, 'anyOf')
      then 'xOf'

      else if std.objectHas(property, '$ref')
      then 'ref'

      else infoMessage("can't find type for " + std.join('.', parents), '')
    ;

    createFunction(name, parents)
    + (
      if type == 'array'
      then appendFunction(name, parents)

      else if type == 'ref' && siblings != {}
      then
        local ref = std.split(property['$ref'], '/')[3];
        this.propertyToValue(
          name,
          parents,
          siblings[ref],
          siblings,
        )

      else if type == 'object'
              && name == 'metadata'
      then handleObject(
        name,
        parents,
        k8s.components.schemas['io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta'].properties,
        siblings,
      )

      else if type == 'object'
              && std.objectHas(property, 'properties')
      then handleObject(
        name,
        parents,
        property.properties,
        siblings,
      )

      else {}
    ) + (
      if std.objectHas(property, 'items')
      then (
        if std.objectHas(property.items, 'type')
           && std.member(['array', 'object'], property.items.type)
        then handleObject(
          name,
          parents,
          property.items.properties,
          siblings,
        )

        else if std.objectHas(property.items, '$ref') && siblings != {}
        then
          local ref = std.split(property.items['$ref'], '/')[3];
          handleObject(
            name,
            parents,
            siblings[ref].properties,
            siblings,
          )

        else if !std.objectHas(property.items, 'type')
                && std.objectHas(property.items, '$ref')
        then infoMessage("can't find type or ref for items in " + std.join('.', parents), {})

        else {}
      )
      else {}
    ),

  fromSchema(grouping, group, version, kind, schema, siblings={}): {
    local kindname =
      local s = camelcase.split(kind);
      std.asciiLower(s[0]) + std.join('', s[1:]),

    [grouping]+: {
      [version]+: {
        [kindname]:
          (if std.objectHas(schema, 'properties')
           then
             std.foldl(
               function(acc, p)
                 acc + this.propertyToValue(
                   p,
                   [p],
                   schema.properties[p],
                   siblings,
                 ),
               std.objectFields(schema.properties),
               {}
             )
           else {})
          +
          if std.objectHas(schema, 'x-kubernetes-group-version-kind')
          then {
            new(name):
              local gvk = schema['x-kubernetes-group-version-kind'];
              local gv =
                if gvk[0].group == ''
                then gvk[0].version
                else gvk[0].group + '/' + gvk.version;

              self.withApiVersion(gv)
              + self.withKind(kind)
              + self.metadata.withName(name),
          }
          else if std.objectHas(schema, 'properties')
                  && std.objectHas(schema.properties, 'kind')
          then {
            new(name):
              self.withApiVersion(group + '/' + version)
              + self.withKind(kind)
              + self.metadata.withName(name),
          }
          else {},
      },
    },
  },

  fromCRD(definition, group_suffix):
    local grouping =
      // If no dedicated API group, then use nogroup key for consistency
      if group_suffix == definition.spec.group
      then 'nogroup'
      else std.split(std.strReplace(definition.spec.group, '.' + group_suffix, ''), '.')[0];

    std.foldl(
      function(acc, v)
        acc
        + this.fromSchema(
          grouping,
          definition.spec.group,
          v,
          definition.spec.names.kind,
          getVersionInDefinition(definition, v).schema.openAPIV3Schema,
        ),
      [
        version.name
        for version in definition.spec.versions
      ],
      {}
    ),

  // limit recursion depth with maxDepth
  inspect(fields, maxDepth=10, depth=0):
    std.foldl(
      function(acc, p)
        acc + (
          if std.isObject(fields[p])
             && depth != maxDepth
          then { [p]+:
            this.inspect(
              fields[p],
              maxDepth,
              depth + 1
            ) }
          else if std.isFunction(fields[p])
          then { functions+: [p] }
          else { fields+: [p] }
        ),
      std.objectFields(fields),
      {}
    ),
}