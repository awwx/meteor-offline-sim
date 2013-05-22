Package.describe({
  summary: "offline data"
});

Package.on_use(function (api) {
  api.use('coffeescript', ['client', 'server']);
  api.use([
    'sim',
    'sim-broadcast',
    'sim-database',
    'proxytab',
    'canonical-stringify'
  ], 'client');
  api.add_files(['offline.litcoffee'], ['client', 'server']);
});
