Package.describe({
  summary: "proxy tab election and dead tab detection"
});

Package.on_use(function (api) {
  api.use(['awwx-err', 'coffeescript', 'sim', 'sim-database'], 'client');
  api.add_files(['proxytab.litcoffee'], 'client');
});
