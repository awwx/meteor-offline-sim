Package.describe({
  summary: "simulated cross-browser tab messaging"
});

Package.on_use(function (api) {
  api.use(['awwx-fanout', 'coffeescript', 'sim'], 'client');
  api.add_files(['broadcast.litcoffee'], 'client');
});
