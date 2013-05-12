Package.describe({
  summary: "JSON.stringify with keys in sorted order"
});

Package.on_use(function(api) {
  api.use(['coffeescript']);
  return api.add_files('stringify.coffee', ['client', 'server']);
});

Package.on_test(function(api) {
  api.use('canonical-stringify');
  return api.add_files('stringify_tests.coffee', ['client', 'server']);
});
