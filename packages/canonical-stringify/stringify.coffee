# Thanks to https://github.com/mirkokiefer/canonical-json for the
# simple idea of passing a recursive copy of the object with sorted
# keys to JSON.stringify.

# The
# [replacer parameter](https://developer.mozilla.org/en-US/docs/Using_native_JSON#The_replacer_parameter)
# and the
# [toJSON method on objects](https://developer.mozilla.org/en-US/docs/JavaScript/Reference/Global_Objects/JSON/stringify#toJSON_behavior)
# are not supported.

copySorted = (x) ->
  if _.isArray(x)
    return _.map(x, copySorted)
  else if _.isObject(x)
    o = {}
    for k in _.keys(x).sort()
      o[k] = copySorted(x[k])
    return o
  else
    return x

@canonicalStringify = (value, replacer, space) ->
  throw new Error('replacer not implemented') if replacer
  JSON.stringify(copySorted(value), null, space)
