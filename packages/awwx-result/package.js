Package.describe({
  summary: "async results"
});

Package.on_use(function(api) {
  api.use(['awwx-err', 'awwx-fanout', 'coffeescript']);
  return api.add_files('result.litcoffee', ['client', 'server']);
});

Package.on_test(function(api) {
  api.use('awwx-result');
  return api.add_files('result-tests.coffee', ['client', 'server']);
});
