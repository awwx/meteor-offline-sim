Package.describe({
  summary: "stub for centralized error reporting"
});

Package.on_use(function(api) {
  api.use('coffeescript', ['client', 'server']);
  api.add_files('err.litcoffee', ['client', 'server']);
});
