Package.describe({
  summary: "Simply call listening callbacks"
});

Package.on_use(function(api) {
  api.use(['awwx-err', 'coffeescript']);
  return api.add_files('fanout.litcoffee', ['client', 'server']);
});

Package.on_test(function(api) {
  api.use('awwx-fanout');
  return api.add_files('fanout-tests.litcoffee', ['client', 'server']);
});
