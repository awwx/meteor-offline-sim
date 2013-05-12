# Canonical stringify

A version of `JSON.stringify` which serializes objects with keys in
sorted order.

    canonicalStringify({a: 1, b: 2})  ->  "{"a":1,"b":2}"
    canonicalStringify({b: 2, a: 1})  ->  "{"a":1,"b":2}"

If two objects are structurally equal, then their serialization will
be equal as well.
